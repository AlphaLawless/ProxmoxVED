# UV DNS Resolution Issues

Este documento descreve problemas conhecidos de resolução DNS ao usar o `uv` (gerenciador de pacotes Python da Astral) para instalar dependências que vêm do GitHub via `git+https`.

## Problema

Durante a instalação de pacotes Python com `uv sync`, o comando falha com erro de DNS:

```
× Failed to download and build `package @ git+https://github.com/user/repo.git@commit`
├─▶ Git operation failed
├─▶ failed to clone into: /root/.cache/uv/git-v0/db/xxxxx
├─▶ failed to fetch commit `xxxxx`
╰─▶ process didn't exit successfully: `/usr/bin/git fetch --force --update-head-ok 'https://github.com/user/repo.git'
    '+commit:refs/commit/commit'` (exit status: 128)
    --- stderr
    fatal: unable to access 'https://github.com/user/repo.git/': Could not resolve host: github.com
```

### Comportamento observado

- DNS funciona normalmente antes do comando `uv sync` (testado com `nslookup` e `ping`)
- `uv` consegue baixar pacotes do PyPI sem problemas
- Apenas dependências Git (`git+https://github.com/...`) falham
- O erro é intermitente - às vezes funciona, às vezes falha
- **Executar `uv sync` manualmente dentro do container FUNCIONA**
- **Executar via script (lxc-attach) FALHA**

## Causa Raiz

### A Investigação

O problema foi extensivamente investigado:

1. ✅ DNS funciona para `ping`, `nslookup`, `curl` executados no container
2. ✅ Git clone direto funciona (ex: RAHasher com 6 submodules)
3. ✅ **Executar `uv sync` manualmente no container FUNCIONA**
4. ❌ **Executar `uv sync` via script de instalação FALHA**

Isso indica que o problema **NÃO é**:
- DNS do container
- Configuração de rede
- NetBird/Tailscale (testado com VPN desativada - problema persistiu)
- Versão do uv (testado 0.7.19 e 0.9.18)

### O Problema Real: lxc-attach + uv Concurrent Downloads

O problema está na combinação de:

1. **Execução via `lxc-attach`**: O script é executado via `lxc-attach -n "$CTID" -- bash -c "..."` que tem um ambiente diferente de um login shell interativo (`pct enter`)

2. **uv Concurrent Downloads**: O `uv` faz downloads paralelos por padrão e isso causa problemas de DNS em ambientes containerizados

3. **Subprocessos e NSS**: Quando `uv` spawna `git` como subprocesso, o ambiente pode não ter acesso correto ao DNS resolver devido a como o NSS (Name Service Switch) funciona em containers

#### Evidência

Segundo [issue #12054 do astral-sh/uv](https://github.com/astral-sh/uv/issues/12054):
> "Users who upgraded uv experienced failing commands that could only work when concurrent downloads were limited by setting UV_CONCURRENT_DOWNLOADS to 4 or even 1."

E segundo a [documentação do lxc-attach](https://man7.org/linux/man-pages/man1/lxc-attach.1.html):
> "If no command is specified, the shell will fail if the container does not have a working nsswitch mechanism."

## Soluções

### 1. Limitar Downloads Concorrentes (Recomendado)

Adicionar ao script antes de `uv sync`:

```bash
export UV_CONCURRENT_DOWNLOADS=1
$STD uv sync --all-extras
```

Ou:

```bash
UV_CONCURRENT_DOWNLOADS=1 uv sync --all-extras
```

### 2. Usar versão específica do uv

Algumas versões do `uv` podem ter comportamentos diferentes. A versão 0.7.19 é usada no Docker oficial do RomM:

```bash
UV_VERSION="0.7.19" PYTHON_VERSION="3.13" setup_uv
```

### 3. Configurar DNS estável no container

Forçar DNS público confiável com timeouts:

```bash
cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 1.0.0.1
options timeout:10 attempts:5
EOF
```

### 4. Configurar timeouts do Git

Aumentar timeouts para operações de rede:

```bash
git config --global http.postBuffer 524288000
git config --global http.lowSpeedLimit 0
git config --global http.lowSpeedTime 999999
```

### 5. Retry automático no script

Adicionar lógica de retry para comandos `uv`:

```bash
for i in {1..3}; do
    if UV_CONCURRENT_DOWNLOADS=1 uv sync --all-extras; then
        break
    else
        echo "Attempt $i failed, retrying in 5 seconds..."
        sleep 5
    fi
done
```

### 6. Usar pct exec ao invés de lxc-attach

Se possível, usar `pct exec` que tem melhor setup de ambiente:

```bash
pct exec "$CTID" -- bash -c "cd /opt/app && uv sync --all-extras"
```

## Issues Relacionadas

### astral-sh/uv

- **[Issue #12054](https://github.com/astral-sh/uv/issues/12054)** - "UV fails to fetch during concurrent downloads"
  - DNS resolution errors durante downloads paralelos
  - Workaround: `UV_CONCURRENT_DOWNLOADS=1` ou `UV_CONCURRENT_DOWNLOADS=4`

- **[Issue #8450](https://github.com/astral-sh/uv/issues/8450)** - "`uv pip install` private pypi repo doesn't work in docker by default"
  - Problemas de DNS em ambientes containerizados

### NetBird / Tailscale (VPNs mesh)

Se você usa **NetBird** ou **Tailscale** no host Proxmox, isso pode agravar o problema:

- **[Issue #4896](https://github.com/netbirdio/netbird/issues/4896)** - "LXC-Container on a host connected via NetBird cannot use DNS"
- **[Issue #4746](https://github.com/tailscale/tailscale/issues/4746)** - "Domain name resolution fails from LXC containers run by Proxmox" (Tailscale)

**Nota**: No nosso caso, desativar NetBird NÃO resolveu o problema, indicando que a causa é o `lxc-attach` + `uv concurrent downloads`.

### Proxmox LXC

- **[Proxmox Forum - DNS resolution fails in LXC containers](https://forum.proxmox.com/threads/dns-resolution-fails-in-lxc-containers-but-only-for-apt.134596/)** 
- **[lxc-attach manual](https://man7.org/linux/man-pages/man1/lxc-attach.1.html)** - Documentação sobre ambiente e NSS

### Rust reqwest (usado internamente pelo uv)

- **[Issue #296](https://github.com/seanmonstar/reqwest/issues/296)** - "DNS caching"
  - uv usa reqwest para HTTP requests
  - Múltiplas requests paralelas podem causar DNS errors
  - Solução: DNS cache local (dnsmasq)

## Diagnóstico

### Verificar se o problema é lxc-attach vs manual

```bash
# 1. Via script (provavelmente falha):
lxc-attach -n 110 -- bash -c "cd /opt/romm && uv sync --all-extras"

# 2. Manualmente (provavelmente funciona):
pct enter 110
cd /opt/romm
uv sync --all-extras
```

Se o item 2 funciona mas o item 1 falha, confirma o problema de ambiente.

### Verificar DNS antes de operações críticas

```bash
echo "========== DNS DEBUG =========="
echo "resolv.conf:"
cat /etc/resolv.conf
echo ""
echo "Testing DNS resolution:"
nslookup github.com
echo ""
echo "Ping github.com:"
ping -c 2 -W 3 github.com
echo "================================"
```

## Ambiente onde o problema foi observado

- **Host**: Proxmox VE 8.x
- **Container**: LXC Debian 13 (unprivileged)
- **VPN no Host**: NetBird (não foi a causa, mas pode agravar)
- **DNS Chain**: Container → Proxmox → Mikrotik → AdGuard → Quad9 (DoH)
- **uv version**: 0.9.18 e 0.7.19 (problema persiste em ambas)
- **Método de execução**: `lxc-attach -n "$CTID" -- bash -c "$(curl ...)"`

## Referências

- [uv Documentation](https://docs.astral.sh/uv/)
- [uv Environment Variables](https://docs.astral.sh/uv/reference/environment/)
- [uv GitHub Repository](https://github.com/astral-sh/uv)
- [lxc-attach Manual](https://man7.org/linux/man-pages/man1/lxc-attach.1.html)
- [Proxmox Forum - LXC DNS Issues](https://forum.proxmox.com/threads/proxmox-8-possible-issue-with-dns-resolution-and-lxc.130326/)

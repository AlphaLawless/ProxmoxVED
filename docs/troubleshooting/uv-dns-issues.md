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

## Causa Raiz

O `uv` spawna o `git` como subprocesso. Segundo a [documentação de variáveis de ambiente do uv](https://docs.astral.sh/uv/reference/environment/):

> "The path to the binary that was used to invoke uv is propagated to all subprocesses spawned by uv."

O subprocesso `git` pode estar recebendo um ambiente diferente, possivelmente sem acesso correto ao DNS resolver. Isso pode afetar:

- `LD_LIBRARY_PATH`
- Configurações de NSS (Name Service Switch)
- Variáveis que afetam o resolver de DNS

## Issues Relacionadas

### astral-sh/rye

- **[Issue #412](https://github.com/astral-sh/rye/issues/412)** - "Bug: Can't resolve host name github.com"
  - DNS funciona (`ping github.com` OK) mas `uv`/`rye` falha
  - Ocorre em ambientes WSL

- **[Issue #1220](https://github.com/astral-sh/rye/issues/1220)** - "Rye installation on WSL2 Ubuntu fails"
  - Erro: "Could not resolve host: objects.githubusercontent.com"
  - Relacionado a como `uv` spawna subprocessos

### Discussões da comunidade GitHub

- **[Discussion #31567](https://github.com/orgs/community/discussions/31567)** - "git push: could not resolve host: github.com"
- **[Discussion #27498](https://github.com/orgs/community/discussions/27498)** - "I can't pull my own repository, turns out I cannot ping github.com either"
- **[Discussion #31487](https://github.com/orgs/community/discussions/31487)** - "Suddenly Could not resolve hostname github.com"

## Soluções

### 1. Usar versão específica do uv (Recomendado)

Algumas versões do `uv` podem ter comportamentos diferentes. Por exemplo, a versão 0.7.19 é usada no Docker oficial do RomM:

```bash
# Em scripts de instalação
UV_VERSION="0.7.19" PYTHON_VERSION="3.13" setup_uv
```

### 2. Configurar DNS estável no container

Forçar DNS público confiável:

```bash
cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 1.0.0.1
options timeout:10 attempts:5
EOF
```

### 3. Configurar timeouts do Git

Aumentar timeouts para operações de rede:

```bash
git config --global http.postBuffer 524288000
git config --global http.lowSpeedLimit 0
git config --global http.lowSpeedTime 999999
```

### 4. Verificar configuração de DNS no AdGuard/Pi-hole

Se você usa AdGuard Home ou Pi-hole:

1. Adicione upstream específico para GitHub:
   ```
   [/github.com/]1.1.1.1
   [/githubusercontent.com/]1.1.1.1
   ```

2. Ou adicione regras de whitelist:
   ```
   @@||github.com^
   @@||githubusercontent.com^
   ```

### 5. Retry automático no script

Adicionar lógica de retry para comandos `uv`:

```bash
for i in {1..3}; do
    if uv sync --all-extras; then
        break
    else
        echo "Attempt $i failed, retrying in 5 seconds..."
        sleep 5
    fi
done
```

### 6. Diagnóstico de DNS antes de operações críticas

Adicionar verificação de DNS antes de comandos que dependem de GitHub:

```bash
# DEBUG: DNS diagnostics
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

## Changelog do uv - Breaking Changes

### Versão 0.9.0
- Default Python version mudou de 3.13 para 3.14
- Não há breaking changes relacionadas a git/network

### Versão 0.8.0
- Mudanças em `uv python install` e `uv venv`
- Não há breaking changes relacionadas a git/network documentadas

Fonte: [uv Releases](https://github.com/astral-sh/uv/releases)

## Ambiente onde o problema foi observado

- **Host**: Proxmox VE
- **Container**: LXC Debian 13
- **DNS Chain**: Container → Proxmox → Mikrotik → AdGuard → Quad9 (DoH)
- **uv version**: 0.9.18 (problema), 0.7.19 (em teste)

## Referências

- [uv Documentation](https://docs.astral.sh/uv/)
- [uv Environment Variables](https://docs.astral.sh/uv/reference/environment/)
- [uv GitHub Repository](https://github.com/astral-sh/uv)
- [uv Changelog](https://github.com/astral-sh/uv/blob/main/CHANGELOG.md)

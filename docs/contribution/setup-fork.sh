#!/bin/bash

################################################################################
# ProxmoxVED Fork Setup Script
#
# Automatically configures documentation and scripts for your fork
# Detects your GitHub username, repository, and current branch from git config
# Updates all hardcoded links to point to your fork and current branch
#
# Usage:
#   ./setup-fork.sh                    # Auto-detect from git config (recommended)
#   ./setup-fork.sh YOUR_USERNAME      # Specify username
#   ./setup-fork.sh YOUR_USERNAME REPO_NAME  # Specify both
#
# Examples:
#   ./setup-fork.sh                    # Auto-detects user/repo/branch
#   ./setup-fork.sh john               # Uses john/ProxmoxVED with current branch
#   ./setup-fork.sh john my-fork       # Uses john/my-fork with current branch
#
# Note: This script will update URLs to use refs/heads/BRANCH_NAME format
#       for direct testing from your development branch
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
REPO_NAME="ProxmoxVED"
USERNAME=""
BRANCH_NAME=""
AUTO_DETECT=true

################################################################################
# FUNCTIONS
################################################################################

print_header() {
  echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║${NC} ProxmoxVED Fork Setup Script"
  echo -e "${BLUE}║${NC} Configuring for your fork..."
  echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"
}

print_info() {
  echo -e "${BLUE}ℹ${NC}  $1"
}

print_success() {
  echo -e "${GREEN}✓${NC}  $1"
}

print_warning() {
  echo -e "${YELLOW}⚠${NC}  $1"
}

print_error() {
  echo -e "${RED}✗${NC}  $1"
}

# Detect username from git remote
detect_username() {
  local remote_url

  # Try to get from origin
  if ! remote_url=$(git config --get remote.origin.url 2>/dev/null); then
    return 1
  fi

  # Extract username from SSH or HTTPS URL
  if [[ $remote_url =~ git@github.com:([^/]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ $remote_url =~ github.com/([^/]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    return 1
  fi
}

# Detect repo name from git remote
detect_repo_name() {
  local remote_url

  if ! remote_url=$(git config --get remote.origin.url 2>/dev/null); then
    return 1
  fi

  # Extract repo name (remove .git if present)
  if [[ $remote_url =~ /([^/]+?)(.git)?$ ]]; then
    local repo="${BASH_REMATCH[1]}"
    echo "${repo%.git}"
  else
    return 1
  fi
}

# Detect current branch name
detect_branch_name() {
  local branch

  if ! branch=$(git branch --show-current 2>/dev/null); then
    return 1
  fi

  if [[ -z "$branch" ]]; then
    return 1
  fi

  echo "$branch"
}

# Ask user for confirmation
confirm() {
  local prompt="$1"
  local response

  read -p "$(echo -e ${YELLOW})$prompt (y/n)${NC} " -r response
  [[ $response =~ ^[Yy]$ ]]
}

# Update links in files
update_links() {
  local new_owner="$1"
  local new_repo="$2"
  local new_branch="$3"
  local files_updated=0

  print_info "Scanning for hardcoded links..."

  # Detect current repo in files (could be community-scripts or already changed)
  local current_owner="community-scripts"
  local sample_file=$(find . -type f -name "*.sh" -not -path "./.git/*" | head -1)

  if [[ -f "$sample_file" ]]; then
    # Try to detect current owner from existing URLs
    if grep -q "raw.githubusercontent.com/[^/]*/ProxmoxVED" "$sample_file" 2>/dev/null; then
      current_owner=$(grep -oP 'raw\.githubusercontent\.com/\K[^/]*(?=/ProxmoxVED)' "$sample_file" 2>/dev/null | head -1)
      current_owner=${current_owner:-community-scripts}
    fi
  fi

  print_info "Detected current owner: $current_owner"
  print_info "Will update to: $new_owner"

  # Update ALL shell scripts and markdown files that contain the repo URL
  # This includes ct/, install/, misc/, vm/, tools/, docs/

  echo ""

  # Find all .sh files and update them
  while IFS= read -r -d '' file; do
    if [[ -f "$file" ]]; then
      # Count occurrences of ProxmoxVED URLs
      local count=$(grep -c "ProxmoxVED" "$file" 2>/dev/null || echo 0)

      if [[ "$count" -gt 0 ]]; then
        # Replace all variations of the URL with branch support
        sed -i "s|github.com/$current_owner/ProxmoxVED|github.com/$new_owner/$new_repo|g" "$file"
        sed -i "s|raw.githubusercontent.com/$current_owner/ProxmoxVED/main|raw.githubusercontent.com/$new_owner/$new_repo/refs/heads/$new_branch|g" "$file"
        sed -i "s|raw.githubusercontent.com/$current_owner/ProxmoxVED/refs/heads/[^/]*|raw.githubusercontent.com/$new_owner/$new_repo/refs/heads/$new_branch|g" "$file"

        ((files_updated++))
        print_success "Updated $file ($count links)"
      fi
    fi
  done < <(find . -type f \( -name "*.sh" -o -name "*.func" \) -not -path "./.git/*" -print0)

  # Also update markdown docs
  while IFS= read -r -d '' file; do
    if [[ -f "$file" ]]; then
      local count=$(grep -c "ProxmoxVED" "$file" 2>/dev/null || echo 0)

      if [[ "$count" -gt 0 ]]; then
        sed -i "s|github.com/$current_owner/ProxmoxVED|github.com/$new_owner/$new_repo|g" "$file"
        sed -i "s|raw.githubusercontent.com/$current_owner/ProxmoxVED/main|raw.githubusercontent.com/$new_owner/$new_repo/refs/heads/$new_branch|g" "$file"
        sed -i "s|raw.githubusercontent.com/$current_owner/ProxmoxVED/refs/heads/[^/]*|raw.githubusercontent.com/$new_owner/$new_repo/refs/heads/$new_branch|g" "$file"

        ((files_updated++))
        print_success "Updated $file ($count links)"
      fi
    fi
  done < <(find ./docs -type f -name "*.md" -print0 2>/dev/null)

  echo ""
  echo "Total files updated: $files_updated"

  # Return success if any files were updated
  if [[ $files_updated -gt 0 ]]; then
    return 0
  else
    return 1
  fi
}

# Create user git config setup info
create_git_setup_info() {
  local username="$1"

  cat >.git-setup-info <<'EOF'
# Git Configuration for ProxmoxVED Development

## Recommended Git Configuration

### Set up remotes for easy syncing with upstream:

```bash
# View your current remotes
git remote -v

# If you don't have 'upstream' configured, add it:
git remote add upstream https://github.com/AlphaLawless/ProxmoxVED.git

# Verify both remotes exist:
git remote -v
# Should show:
# origin     https://github.com/YOUR_USERNAME/ProxmoxVED.git (fetch)
# origin     https://github.com/YOUR_USERNAME/ProxmoxVED.git (push)
# upstream   https://github.com/AlphaLawless/ProxmoxVED.git (fetch)
# upstream   https://github.com/AlphaLawless/ProxmoxVED.git (push)
```

### Configure Git User (if not done globally)

```bash
git config user.name "Your Name"
git config user.email "your.email@example.com"

# Or configure globally:
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

### Useful Git Workflows

**Keep your fork up-to-date:**
```bash
git fetch upstream
git rebase upstream/main
git push origin main
```

**Create feature branch:**
```bash
git checkout -b feature/my-awesome-app
# Make changes...
git commit -m "feat: add my awesome app"
git push origin feature/my-awesome-app
```

**Pull latest from upstream:**
```bash
git fetch upstream
git merge upstream/main
```

---

For more help, see: docs/CONTRIBUTION_GUIDE.md
EOF

  print_success "Created .git-setup-info file"
}

################################################################################
# MAIN LOGIC
################################################################################

print_header

# Parse command line arguments
if [[ $# -gt 0 ]]; then
  USERNAME="$1"
  AUTO_DETECT=false

  if [[ $# -gt 1 ]]; then
    REPO_NAME="$2"
  fi
else
  # Try auto-detection
  if username=$(detect_username); then
    USERNAME="$username"
    print_success "Detected GitHub username: $USERNAME"
  else
    print_error "Could not auto-detect GitHub username from git config"
    echo -e "${YELLOW}Please run:${NC}"
    echo "  ./setup-fork.sh YOUR_USERNAME"
    exit 1
  fi

  if repo_name=$(detect_repo_name); then
    REPO_NAME="$repo_name"
    if [[ "$REPO_NAME" != "ProxmoxVED" ]]; then
      print_info "Detected custom repo name: $REPO_NAME"
    else
      print_success "Using default repo name: ProxmoxVED"
    fi
  fi

  # Auto-detect current branch
  if branch_name=$(detect_branch_name); then
    BRANCH_NAME="$branch_name"
    print_success "Detected current branch: $BRANCH_NAME"

    # Warn if on main branch
    if [[ "$BRANCH_NAME" == "main" ]]; then
      print_warning "You are on the 'main' branch!"
      print_warning "It's recommended to work on a feature branch."
      echo ""
      if ! confirm "Continue anyway?"; then
        print_info "Please create a feature branch first:"
        echo "  git switch -c your-feature-branch"
        exit 0
      fi
    fi
  else
    print_error "Could not detect current branch"
    exit 1
  fi
fi

# Validate inputs
if [[ -z "$USERNAME" ]]; then
  print_error "Username cannot be empty"
  exit 1
fi

if [[ -z "$REPO_NAME" ]]; then
  print_error "Repository name cannot be empty"
  exit 1
fi

if [[ -z "$BRANCH_NAME" ]]; then
  print_error "Branch name cannot be empty"
  exit 1
fi

# Show what we'll do
echo -e "${BLUE}Configuration Summary:${NC}"
echo "  GitHub User: ${GREEN}$USERNAME${NC}"
echo "  Repository: ${GREEN}$REPO_NAME${NC}"
echo "  Branch: ${GREEN}$BRANCH_NAME${NC}"
echo ""
echo "  Repository URL: https://github.com/$USERNAME/$REPO_NAME"
echo "  Raw URL: https://raw.githubusercontent.com/$USERNAME/$REPO_NAME/refs/heads/$BRANCH_NAME"
echo "  Directories to scan: ct/, install/, misc/, vm/, tools/, docs/"
echo ""

# Ask for confirmation
if ! confirm "Apply these changes?"; then
  print_warning "Setup cancelled"
  exit 0
fi

echo ""

# Update all links
if update_links "$USERNAME" "$REPO_NAME" "$BRANCH_NAME"; then
  print_success "Links updated successfully"
else
  print_warning "No links needed updating or some files not found"
fi

# Create git setup info file
create_git_setup_info "$USERNAME"

# Final summary
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC} Fork Setup Complete!                                    ${GREEN}║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

print_success "All documentation links updated to point to your fork"
print_info "Your fork: https://github.com/$USERNAME/$REPO_NAME"
print_info "Current branch: $BRANCH_NAME"
print_info "Raw URL: https://raw.githubusercontent.com/$USERNAME/$REPO_NAME/refs/heads/$BRANCH_NAME"
print_info "Upstream: https://github.com/AlphaLawless/ProxmoxVED"
echo ""

echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Review the changes: git diff"
echo "  2. Test your scripts pointing to your branch"
echo "  3. Check .git-setup-info for recommended git workflow"
echo "  4. Before creating a PR, restore URLs to upstream"
echo "  5. Read: docs/CONTRIBUTION_GUIDE.md"
echo ""

print_success "Happy contributing! 🚀"

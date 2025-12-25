#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# License: MIT | https://github.com/AlphaLawless/ProxmoxVED/raw/main/LICENSE

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ORIGINAL_URL="https://raw.githubusercontent.com/AlphaLawless/ProxmoxVED/refs/heads/add-romM

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_directory() {
    if [[ ! -d "misc" ]] || [[ ! -d "ct" ]] || [[ ! -d ".github" ]]; then
        print_error "Please run this script from the root of the ProxmoxVED repository!"
        exit 1
    fi
}

check_branch() {
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)

    if [[ -z "$CURRENT_BRANCH" ]]; then
        print_error "Not in a git repository!"
        exit 1
    fi

    if [[ "$CURRENT_BRANCH" == "main" ]]; then
        print_error "You are currently on the 'main' branch!"
        print_warning "Please switch to a feature branch before making changes."
        echo ""
        echo -e "${YELLOW}You can create and switch to a new branch with:${NC}"
        echo -e "  git switch -c your-feature-branch"
        echo ""
        exit 1
    fi

    print_success "Current branch: $CURRENT_BRANCH"
    return 0
}

detect_github_username() {
    local remote_url

    if ! remote_url=$(git config --get remote.origin.url 2>/dev/null); then
        return 1
    fi

    # Extract username from SSH URL (git@github.com:username/repo.git)
    if [[ $remote_url =~ git@github.com:([^/]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    # Extract username from HTTPS URL (https://github.com/username/repo.git)
    if [[ $remote_url =~ github.com/([^/]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

detect_github_repo() {
    local remote_url

    if ! remote_url=$(git config --get remote.origin.url 2>/dev/null); then
        return 1
    fi

    # Extract repo name (remove .git suffix if present)
    if [[ $remote_url =~ /([^/]+?)(\.git)?$ ]]; then
        local repo="${BASH_REMATCH[1]}"
        echo "${repo%.git}"
        return 0
    fi

    return 1
}

get_modified_ct_files() {
    local new_files=$(git ls-files --others --exclude-standard ct/*.sh 2>/dev/null)
    local modified_files=$(git diff --name-only ct/*.sh 2>/dev/null)
    local staged_files=$(git diff --cached --name-only ct/*.sh 2>/dev/null)

    echo -e "${new_files}\n${modified_files}\n${staged_files}" | grep -v '^$' | sort -u
}

get_user_input() {
    echo ""
    print_info "Detecting GitHub information..."
    echo ""

    # Try to auto-detect username
    if DETECTED_USER=$(detect_github_username); then
        print_success "Detected GitHub username: $DETECTED_USER"
        read -p "Use detected username? [Y/n]: " USE_DETECTED
        if [[ -z "$USE_DETECTED" ]] || [[ "$USE_DETECTED" =~ ^[Yy]$ ]]; then
            GITHUB_USER="$DETECTED_USER"
        else
            read -p "Enter your GitHub username: " GITHUB_USER
        fi
    else
        print_warning "Could not auto-detect GitHub username"
        read -p "Enter your GitHub username: " GITHUB_USER
    fi

    if [[ -z "$GITHUB_USER" ]]; then
        print_error "GitHub username cannot be empty!"
        exit 1
    fi

    # Try to auto-detect repo name
    if DETECTED_REPO=$(detect_github_repo); then
        if [[ "$DETECTED_REPO" != "ProxmoxVED" ]]; then
            print_info "Detected repository name: $DETECTED_REPO"
        fi
        GITHUB_REPO="$DETECTED_REPO"
    else
        GITHUB_REPO="ProxmoxVED"
    fi

    read -p "Repository name [default: $GITHUB_REPO]: " INPUT_REPO
    if [[ -n "$INPUT_REPO" ]]; then
        GITHUB_REPO="$INPUT_REPO"
    fi

    GITHUB_BRANCH=$(git branch --show-current)

    NEW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/refs/heads/${GITHUB_BRANCH}"

    echo ""
    print_info "Configuration summary:"
    echo -e "  GitHub User: ${GREEN}${GITHUB_USER}${NC}"
    echo -e "  Repository: ${GREEN}${GITHUB_REPO}${NC}"
    echo -e "  Branch: ${GREEN}${GITHUB_BRANCH}${NC}"
    echo ""
    echo -e "  Original URL: ${RED}${ORIGINAL_URL}${NC}"
    echo -e "  New URL: ${GREEN}${NEW_URL}${NC}"
    echo ""
}

confirm_action() {
    local action=$1
    echo ""
    if [[ "$action" == "change" ]]; then
        print_warning "This will change URLs in misc/build.func, misc/install.func, and your modified ct/*.sh files."
        read -p "Do you want to proceed? (yes/no): " CONFIRM
    else
        print_warning "This will restore URLs back to the original community-scripts URLs."
        read -p "Do you want to restore original URLs? (yes/no): " CONFIRM
    fi

    if [[ "$CONFIRM" != "yes" ]] && [[ "$CONFIRM" != "y" ]]; then
        print_info "Operation cancelled."
        exit 0
    fi
}

replace_urls() {
    local from_url=$1
    local to_url=$2
    local modified_files=0

    local from_url_escaped=$(echo "$from_url" | sed 's/[\/&]/\\&/g')
    local to_url_escaped=$(echo "$to_url" | sed 's/[\/&]/\\&/g')

    print_info "Replacing URLs in files..."
    echo ""

    if [[ -f "misc/build.func" ]]; then
        if grep -q "$from_url" "misc/build.func"; then
            sed -i "s|${from_url_escaped}|${to_url_escaped}|g" "misc/build.func"
            print_success "Updated: misc/build.func"
            ((modified_files++))
        fi
    fi

    if [[ -f "misc/install.func" ]]; then
        if grep -q "$from_url" "misc/install.func"; then
            sed -i "s|${from_url_escaped}|${to_url_escaped}|g" "misc/install.func"
            print_success "Updated: misc/install.func"
            ((modified_files++))
        fi
    fi

    local ct_files=$(get_modified_ct_files)

    if [[ -z "$ct_files" ]]; then
        echo ""
        print_warning "No new or modified ct/*.sh files found!"
        print_info "It looks like you haven't created or modified your container build script yet."
        echo -e "  ${YELLOW}Create your script in:${NC} ct/your-app.sh"
    else
        echo ""
        print_info "Found modified/new ct/*.sh files:"
        echo "$ct_files" | while read -r file; do
            echo "  - $file"
        done
        echo ""

        echo "$ct_files" | while read -r file; do
            if [[ -f "$file" ]] && grep -q "$from_url" "$file"; then
                sed -i "s|${from_url_escaped}|${to_url_escaped}|g" "$file"
                print_success "Updated: $file"
                ((modified_files++))
            fi
        done
    fi

    echo ""
    if [[ $modified_files -eq 0 ]]; then
        print_warning "No files were modified. URLs might already be set correctly."
    else
        print_success "Successfully modified $modified_files file(s)!"
    fi
}

show_menu() {
    echo ""
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║        ProxmoxVED Path Changer for Development         ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo ""
    echo "This script helps you change repository URLs for development."
    echo ""
    echo "Options:"
    echo "  1) Change to development URLs (your fork/branch)"
    echo "  2) Restore to original URLs (community-scripts/main)"
    echo "  3) Exit"
    echo ""
    read -p "Select an option [1-3]: " OPTION

    case $OPTION in
        1)
            get_user_input
            confirm_action "change"
            replace_urls "$ORIGINAL_URL" "$NEW_URL"
            echo ""
            print_warning "Remember to restore URLs before creating a Pull Request!"
            ;;
        2)
            confirm_action "restore"
            CURRENT_URL=$(grep -oP 'https://raw\.githubusercontent\.com/[^/]+/[^/]+/refs/heads/[^/]+' misc/build.func 2>/dev/null | head -n1)
            if [[ -z "$CURRENT_URL" ]]; then
                CURRENT_URL="https://raw.githubusercontent.com/.*/.*/(refs/heads/.*|main)"
            fi
            replace_urls "$CURRENT_URL" "$ORIGINAL_URL"
            print_success "URLs restored to original community-scripts repository!"
            ;;
        3)
            print_info "Exiting..."
            exit 0
            ;;
        *)
            print_error "Invalid option!"
            exit 1
            ;;
    esac
}

main() {
    check_directory
    check_branch
    show_menu
}

main

#!/bin/bash

# This script sets up Oh My Zsh and rbenv for a non-root user.
# It should be run *after* the main server setup script (run as root),
# and executed by the new non-root user (e.g., after logging in via SSH).

# Exit immediately if a command exits with a non-zero status
set -e

# Color Definitions ANSI Escape Codes
RED='\033[0;31m'    # Red
GREEN='\033[0;32m'  # Green
YELLOW='\033[0;33m' # Yellow
NC='\033[0m'       # No Color (Reset)

# Function to display messages
log_info() {
    echo -e "${YELLOW}INFO:${NC} $1" # Added -e to interpret backslash escapes
}

log_error() {
    echo -e "${RED}ERROR:${NC} $1" >&2 # Added -e to interpret backslash escapes
}

log_success() {
    echo -e "${GREEN}SUCCESS:${NC} $1" # Added -e to interpret backslash escapes
}

# Ensure script is run by the non-root user for whom it's intended
if [ "$(id -u)" -eq 0 ]; then
    log_error "This script should be run as the non-root user, NOT as root. Exiting."
    exit 1
fi

# Get the current username (this script is run by the user themselves)
NEW_USERNAME=$(whoami)
log_info "Starting user-specific setup for user: ${NEW_USERNAME}"

# --- 1. Oh My Zsh Installation for Current User ---
log_info "Installing Oh My Zsh for user '${NEW_USERNAME}'..."
# Oh My Zsh installer will handle setting zsh as default shell.
# CHSH=yes ensures it prompts to change default shell, RUNZSH=no prevents immediate shell change within script.
sh -c "CHSH=yes RUNZSH=no $(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || log_error "Oh My Zsh installation for '${NEW_USERNAME}' might have failed or already exists. Please check manually."
log_success "Oh My Zsh installed for '${NEW_USERNAME}'. You might need to open a new terminal session."


# --- 2. rbenv Installation for Current User ---
log_info "Installing rbenv for Ruby version management..."

# Install rbenv and ruby-build for the current user
if [ ! -d "$HOME/.rbenv" ]; then
    git clone https://github.com/rbenv/rbenv.git "$HOME"/.rbenv
    log_success "rbenv cloned to $HOME/.rbenv."
else
    log_info "rbenv directory already exists. Skipping cloning."
fi

if [ ! -d "$HOME/.rbenv/plugins/ruby-build" ]; then
    git clone https://github.com/rbenv/ruby-build.git "$HOME"/.rbenv/plugins/ruby-build
    log_success "ruby-build cloned to $HOME/.rbenv/plugins/ruby-build."
else
    log_info "ruby-build directory already exists. Skipping cloning."
fi

# Add rbenv to .zshrc
RC_FILE="$HOME/.zshrc"
RBENV_INIT='
# rbenv setup
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - zsh)"
'
if ! grep -q "rbenv init" "$RC_FILE"; then
    echo -e "$RBENV_INIT" | tee -a "$RC_FILE" > /dev/null # Added -e
    log_info "rbenv initialization added to ${RC_FILE}."
else
    log_info "rbenv initialization already present in ${RC_FILE}."
fi

log_success "rbenv installed. Remember to run 'source ~/.zshrc' or open a new terminal session for rbenv to be active."

# --- 3. Optional Ruby Installation via rbenv ---
log_info "Optional Ruby Installation via rbenv..."
read -p "$(echo -e "${YELLOW}Do you want to install a Ruby version now using rbenv? (y/N):${NC} ")" -n 1 -r RBENV_INSTALL_CHOICE
echo # Newline

if [[ "$RBENV_INSTALL_CHOICE" =~ ^[Yy]$ ]]; then
    read -p "$(echo -e "${YELLOW}Enter the Ruby version you want to install (e.g., 3.2.2):${NC} ")" RUBY_VERSION
    if [ -z "$RUBY_VERSION" ]; then
        log_error "Ruby version cannot be empty. Skipping Ruby installation."
    else
        log_info "Installing Ruby version ${RUBY_VERSION}..."
        # Ensure rbenv is sourced for this shell
        export PATH="$HOME/.rbenv/bin:$PATH"
        eval "$(rbenv init - zsh)"

        if rbenv install "$RUBY_VERSION"; then
            log_success "Ruby version ${RUBY_VERSION} installed successfully."
            log_info "Setting Ruby version ${RUBY_VERSION} as global default..."
            if rbenv global "$RUBY_VERSION"; then
                log_success "Ruby version ${RUBY_VERSION} set as global default."
                log_info "You can verify by running 'ruby -v' in a new terminal session."
            else
                log_error "Failed to set Ruby version ${RUBY_VERSION} as global default."
            fi
        else
            log_error "Failed to install Ruby version ${RUBY_VERSION}. Please check rbenv output for details."
        fi
    fi
else
    log_info "Skipping Ruby version installation for now."
    log_info "You can install Ruby later by running 'rbenv install <version>' and 'rbenv global <version>'."
fi

log_info "---------------------------------------------------------"
log_info "USER-SPECIFIC SETUP COMPLETE FOR '${NEW_USERNAME}'!"
log_info "---------------------------------------------------------"
log_info "Please run 'source ~/.zshrc' or open a new terminal session for changes to take effect."
log_info "---------------------------------------------------------"

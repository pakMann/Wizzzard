#!/bin/bash

# This script sets up PHP, Composer, and database for Laravel development.
# It should be run by a non-root user on Ubuntu (WSL2).
# Prerequisites: zsh and git already installed

# Exit immediately if a command exits with a non-zero status
set -e

# Color Definitions ANSI Escape Codes
RED='\033[0;31m'    # Red
GREEN='\033[0;32m'  # Green
YELLOW='\033[0;33m' # Yellow
BLUE='\033[0;34m'   # Blue
NC='\033[0m'        # No Color (Reset)

# Function to display messages
log_info() {
    echo -e "${YELLOW}INFO:${NC} $1"
}

log_error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}SUCCESS:${NC} $1"
}

log_step() {
    echo -e "${BLUE}==>${NC} $1"
}

# Ensure script is run by the non-root user
if [ "$(id -u)" -eq 0 ]; then
    log_error "This script should be run as the non-root user, NOT as root. Exiting."
    exit 1
fi

NEW_USERNAME=$(whoami)
log_info "Starting Laravel environment setup for user: ${NEW_USERNAME}"

# --- 1. Update Package Lists ---
log_step "Updating package lists..."
sudo apt-get update
log_success "Package lists updated."

# --- 2. PHP Version Selection ---
echo ""
log_step "PHP Version Selection"
echo -e "${BLUE}Available PHP versions:${NC}"
echo "  1) PHP 8.3 (Latest)"
echo "  2) PHP 8.2"
echo "  3) PHP 8.1"
echo "  4) PHP 8.0"
echo "  5) PHP 7.4"
read -p "$(echo -e "${YELLOW}Select PHP version (1-5):${NC} ")" PHP_CHOICE

case $PHP_CHOICE in
    1) PHP_VERSION="8.3" ;;
    2) PHP_VERSION="8.2" ;;
    3) PHP_VERSION="8.1" ;;
    4) PHP_VERSION="8.0" ;;
    5) PHP_VERSION="7.4" ;;
    *)
        log_error "Invalid choice. Defaulting to PHP 8.2"
        PHP_VERSION="8.2"
        ;;
esac

log_info "Selected PHP version: ${PHP_VERSION}"

# --- 3. Install PHP and Required Extensions ---
log_step "Installing PHP ${PHP_VERSION} and extensions..."

# Add ondrej/php PPA for latest PHP versions
if ! grep -q "ondrej/php" /etc/apt/sources.list.d/*.list 2>/dev/null; then
    log_info "Adding ondrej/php PPA..."
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y ppa:ondrej/php
    sudo apt-get update
fi

# Install PHP and common Laravel extensions
sudo apt-get install -y \
    php${PHP_VERSION} \
    php${PHP_VERSION}-cli \
    php${PHP_VERSION}-common \
    php${PHP_VERSION}-curl \
    php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-xml \
    php${PHP_VERSION}-bcmath \
    php${PHP_VERSION}-zip \
    php${PHP_VERSION}-gd \
    php${PHP_VERSION}-intl \
    php${PHP_VERSION}-readline \
    unzip

log_success "PHP ${PHP_VERSION} and extensions installed."

# Verify PHP installation
PHP_INSTALLED_VERSION=$(php -v | head -n 1)
log_info "Installed: ${PHP_INSTALLED_VERSION}"

# --- 4. Database Selection ---
echo ""
log_step "Database Selection"
echo -e "${BLUE}Available databases:${NC}"
echo "  1) MySQL"
echo "  2) PostgreSQL"
echo "  3) MongoDB"
echo "  4) Skip database installation"
read -p "$(echo -e "${YELLOW}Select database (1-4):${NC} ")" DB_CHOICE

case $DB_CHOICE in
    1)
        log_info "Installing MySQL..."
        sudo apt-get install -y mysql-server php${PHP_VERSION}-mysql
        
        # Start MySQL service
        sudo service mysql start
        
        log_success "MySQL installed and started."
        log_info "To secure MySQL, run: sudo mysql_secure_installation"
        log_info "To access MySQL: sudo mysql"
        
        # Optional: Create Laravel database
        read -p "$(echo -e "${YELLOW}Create a database for Laravel? (y/N):${NC} ")" -n 1 -r CREATE_DB
        echo
        if [[ "$CREATE_DB" =~ ^[Yy]$ ]]; then
            read -p "$(echo -e "${YELLOW}Enter database name:${NC} ")" DB_NAME
            read -p "$(echo -e "${YELLOW}Enter database user:${NC} ")" DB_USER
            read -sp "$(echo -e "${YELLOW}Enter database password:${NC} ")" DB_PASS
            echo
            
            sudo mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
            sudo mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
            sudo mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
            sudo mysql -e "FLUSH PRIVILEGES;"
            
            log_success "Database '${DB_NAME}' created with user '${DB_USER}'."
        fi
        ;;
    2)
        log_info "Installing PostgreSQL..."
        sudo apt-get install -y postgresql postgresql-contrib php${PHP_VERSION}-pgsql
        
        # Start PostgreSQL service
        sudo service postgresql start
        
        log_success "PostgreSQL installed and started."
        log_info "To access PostgreSQL: sudo -u postgres psql"
        
        # Optional: Create Laravel database
        read -p "$(echo -e "${YELLOW}Create a database for Laravel? (y/N):${NC} ")" -n 1 -r CREATE_DB
        echo
        if [[ "$CREATE_DB" =~ ^[Yy]$ ]]; then
            read -p "$(echo -e "${YELLOW}Enter database name:${NC} ")" DB_NAME
            read -p "$(echo -e "${YELLOW}Enter database user:${NC} ")" DB_USER
            read -sp "$(echo -e "${YELLOW}Enter database password:${NC} ")" DB_PASS
            echo
            
            sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME};"
            sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
            sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
            
            log_success "Database '${DB_NAME}' created with user '${DB_USER}'."
        fi
        ;;
    3)
        log_info "Installing MongoDB..."
        
        # Install MongoDB
        curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
        echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
        sudo apt-get update
        sudo apt-get install -y mongodb-org php${PHP_VERSION}-mongodb
        
        # Start MongoDB service
        sudo service mongod start
        
        log_success "MongoDB installed and started."
        log_info "To access MongoDB: mongosh"
        ;;
    4)
        log_info "Skipping database installation."
        ;;
    *)
        log_error "Invalid choice. Skipping database installation."
        ;;
esac

# --- 5. Install Composer ---
echo ""
log_step "Installing Composer..."

if command -v composer &> /dev/null; then
    log_info "Composer is already installed."
    composer --version
else
    log_info "Downloading and installing Composer..."
    
    cd ~
    curl -sS https://getcomposer.org/installer -o composer-setup.php
    
    # Verify installer (optional but recommended)
    HASH="$(curl -sS https://composer.github.io/installer.sig)"
    php -r "if (hash_file('SHA384', 'composer-setup.php') === '$HASH') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
    
    sudo php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm composer-setup.php
    
    log_success "Composer installed successfully."
    composer --version
fi

# --- 6. Install Node.js and npm (for Laravel Mix/Vite) ---
echo ""
read -p "$(echo -e "${YELLOW}Install Node.js and npm for frontend assets? (Y/n):${NC} ")" -n 1 -r INSTALL_NODE
echo
if [[ ! "$INSTALL_NODE" =~ ^[Nn]$ ]]; then
    log_step "Installing Node.js and npm..."
    
    if command -v node &> /dev/null; then
        log_info "Node.js is already installed."
        node --version
        npm --version
    else
        # Install Node.js via NodeSource
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt-get install -y nodejs
        
        log_success "Node.js and npm installed successfully."
        node --version
        npm --version
    fi
fi

# --- 7. Configure PHP CLI ini (optional) ---
echo ""
read -p "$(echo -e "${YELLOW}Configure PHP memory_limit and upload size? (y/N):${NC} ")" -n 1 -r CONFIG_PHP
echo
if [[ "$CONFIG_PHP" =~ ^[Yy]$ ]]; then
    PHP_INI="/etc/php/${PHP_VERSION}/cli/php.ini"
    log_info "Configuring ${PHP_INI}..."
    
    sudo sed -i 's/memory_limit = .*/memory_limit = 512M/' "$PHP_INI"
    sudo sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$PHP_INI"
    sudo sed -i 's/post_max_size = .*/post_max_size = 64M/' "$PHP_INI"
    
    log_success "PHP configuration updated."
fi

# --- 8. Add Composer to PATH in .zshrc ---
echo ""
log_step "Configuring shell environment..."

RC_FILE="$HOME/.zshrc"
COMPOSER_PATH='
# Composer global bin directory
export PATH="$HOME/.config/composer/vendor/bin:$PATH"
'

if ! grep -q "composer/vendor/bin" "$RC_FILE"; then
    echo -e "$COMPOSER_PATH" >> "$RC_FILE"
    log_info "Composer global bin path added to ${RC_FILE}."
else
    log_info "Composer path already present in ${RC_FILE}."
fi

# --- 9. Install Laravel Installer (optional) ---
echo ""
read -p "$(echo -e "${YELLOW}Install Laravel Installer globally? (Y/n):${NC} ")" -n 1 -r INSTALL_LARAVEL
echo
if [[ ! "$INSTALL_LARAVEL" =~ ^[Nn]$ ]]; then
    log_info "Installing Laravel Installer..."
    composer global require laravel/installer
    log_success "Laravel Installer installed globally."
    log_info "You can create a new Laravel project with: laravel new project-name"
fi

# --- 10. Summary ---
echo ""
log_info "========================================================="
log_success "LARAVEL ENVIRONMENT SETUP COMPLETE FOR '${NEW_USERNAME}'!"
log_info "========================================================="
echo ""
log_info "Installed components:"
echo "  - PHP ${PHP_VERSION}"
echo "  - Composer"
if [[ ! "$INSTALL_NODE" =~ ^[Nn]$ ]]; then
    echo "  - Node.js & npm"
fi
case $DB_CHOICE in
    1) echo "  - MySQL" ;;
    2) echo "  - PostgreSQL" ;;
    3) echo "  - MongoDB" ;;
esac
echo ""
log_info "Next steps:"
echo "  1. Run 'source ~/.zshrc' or open a new terminal"
echo "  2. Create a new Laravel project:"
echo "     - Using Composer: composer create-project laravel/laravel project-name"
if [[ ! "$INSTALL_LARAVEL" =~ ^[Nn]$ ]]; then
    echo "     - Using Laravel Installer: laravel new project-name"
fi
echo "  3. Configure your .env file with database credentials"
echo "  4. Run 'php artisan serve' to start development server"
echo ""
log_info "========================================================="

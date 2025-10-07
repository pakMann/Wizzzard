#!/bin/bash
set -e
set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${YELLOW}INFO:${NC} $1"; }
log_error() { echo -e "${RED}ERROR:${NC} $1" >&2; }
log_success() { echo -e "${GREEN}SUCCESS:${NC} $1"; }
log_step() { echo -e "${BLUE}==>${NC} $1"; }

if [ "$(id -u)" -eq 0 ]; then
    log_error "Run as non-root user. Exiting."
    exit 1
fi

USER_NAME=$(whoami)
log_info "Starting Laravel environment setup for user: ${USER_NAME}"

log_step "Updating package lists..."
sudo apt-get update -y
sudo apt-get upgrade -y
log_success "Package lists updated."

# --- PHP Version Selection ---
echo ""
log_step "PHP Version Selection"
echo "  1) PHP 8.3"
echo "  2) PHP 8.2"
echo "  3) PHP 8.1"
echo "  4) PHP 8.0"
echo "  5) PHP 7.4"
read -p "$(echo -e "${YELLOW}Select PHP version (1-5) [default 2]:${NC} ")" PHP_CHOICE
PHP_CHOICE=${PHP_CHOICE:-2}
case $PHP_CHOICE in
    1) PHP_VERSION="8.3";;
    2) PHP_VERSION="8.2";;
    3) PHP_VERSION="8.1";;
    4) PHP_VERSION="8.0";;
    5) PHP_VERSION="7.4";;
    *) log_error "Invalid choice. Defaulting to PHP 8.2"; PHP_VERSION="8.2";;
esac
log_info "Selected PHP version: ${PHP_VERSION}"

# --- PHP Installation ---
log_step "Installing PHP ${PHP_VERSION} and extensions..."
if ! grep -q "ondrej/php" /etc/apt/sources.list.d/*.list 2>/dev/null; then
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y ppa:ondrej/php
    sudo apt-get update -y
fi

sudo apt-get install -y \
    php${PHP_VERSION} php${PHP_VERSION}-cli php${PHP_VERSION}-common \
    php${PHP_VERSION}-curl php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml \
    php${PHP_VERSION}-bcmath php${PHP_VERSION}-zip php${PHP_VERSION}-gd \
    php${PHP_VERSION}-intl php${PHP_VERSION}-readline unzip

log_success "PHP ${PHP_VERSION} installed."
log_info "Installed: $(php -v | head -n 1)"

# --- Database Selection ---
echo ""
log_step "Database Selection"
echo "  1) MySQL"
echo "  2) PostgreSQL"
echo "  3) MongoDB"
echo "  4) Skip"
read -p "$(echo -e "${YELLOW}Select database (1-4) [default 4]:${NC} ")" DB_CHOICE
DB_CHOICE=${DB_CHOICE:-4}

case $DB_CHOICE in
    1)
        log_info "Installing MySQL..."
        sudo apt-get install -y mysql-server php${PHP_VERSION}-mysql
        sudo systemctl enable mysql
        sudo systemctl start mysql
        log_success "MySQL installed and started."

        read -p "$(echo -e "${YELLOW}Create a Laravel database? (y/N):${NC} ")" -n 1 -r CREATE_DB
        echo
        if [[ "$CREATE_DB" =~ ^[Yy]$ ]]; then
            read -p "$(echo -e "${YELLOW}Database name [laravel]:${NC} ")" DB_NAME
            DB_NAME=${DB_NAME:-laravel}
            read -p "$(echo -e "${YELLOW}Database user [laravel]:${NC} ")" DB_USER
            DB_USER=${DB_USER:-laravel}
            read -sp "$(echo -e "${YELLOW}Database password:${NC} ")" DB_PASS
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
        sudo systemctl enable postgresql
        sudo systemctl start postgresql
        log_success "PostgreSQL installed and started."

        read -p "$(echo -e "${YELLOW}Create a Laravel database? (y/N):${NC} ")" -n 1 -r CREATE_DB
        echo
        if [[ "$CREATE_DB" =~ ^[Yy]$ ]]; then
            read -p "$(echo -e "${YELLOW}Database name [laravel]:${NC} ")" DB_NAME
            DB_NAME=${DB_NAME:-laravel}
            read -p "$(echo -e "${YELLOW}Database user [laravel]:${NC} ")" DB_USER
            DB_USER=${DB_USER:-laravel}
            read -sp "$(echo -e "${YELLOW}Database password:${NC} ")" DB_PASS
            echo
            sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME};"
            sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
            sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
            log_success "Database '${DB_NAME}' created with user '${DB_USER}'."
        fi
        ;;
    3)
        log_info "Installing MongoDB..."
        curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
        echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
        sudo apt-get update
        sudo apt-get install -y mongodb-org php${PHP_VERSION}-mongodb
        sudo systemctl enable mongod
        sudo systemctl start mongod
        log_success "MongoDB installed and started."
        ;;
    4) log_info "Skipping database installation." ;;
    *) log_error "Invalid choice. Skipping database installation." ;;
esac

# --- Composer Installation ---
echo ""
log_step "Installing Composer..."
if command -v composer &>/dev/null; then
    log_info "Composer already installed: $(composer --version)"
else
    cd ~
    curl -sS https://getcomposer.org/installer -o composer-setup.php
    HASH="$(curl -sS https://composer.github.io/installer.sig)"
    php -r "if (hash_file('SHA384','composer-setup.php')==='$HASH'){echo 'Installer verified';}else{echo 'Installer corrupt';unlink('composer-setup.php');exit(1);} echo PHP_EOL;"
    php composer-setup.php --install-dir=$HOME/.local/bin --filename=composer
    rm composer-setup.php
    export PATH="$HOME/.local/bin:$PATH"
    log_success "Composer installed: $(composer --version)"
fi

# --- Node.js Installation ---
echo ""
read -p "$(echo -e "${YELLOW}Install Node.js & npm? (Y/n):${NC} ")" -n 1 -r INSTALL_NODE
echo
INSTALL_NODE=${INSTALL_NODE:-Y}
if [[ ! "$INSTALL_NODE" =~ ^[Nn]$ ]]; then
    if command -v node &>/dev/null; then
        log_info "Node.js already installed: $(node -v)"
    else
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt-get install -y nodejs
        log_success "Node.js installed: $(node -v)"
    fi
fi

# --- PHP CLI Configuration ---
echo ""
read -p "$(echo -e "${YELLOW}Configure PHP memory_limit and upload size? (y/N):${NC} ")" -n 1 -r CONFIG_PHP
echo
CONFIG_PHP=${CONFIG_PHP:-N}
if [[ "$CONFIG_PHP" =~ ^[Yy]$ ]]; then
    PHP_INI="/etc/php/${PHP_VERSION}/cli/php.ini"
    sudo sed -i 's/memory_limit = .*/memory_limit = 512M/' "$PHP_INI"
    sudo sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$PHP_INI"
    sudo sed -i 's/post_max_size = .*/post_max_size = 64M/' "$PHP_INI"
    log_success "PHP configuration updated."
fi

# --- Composer PATH in .zshrc ---
echo ""
RC_FILE="$HOME/.zshrc"
if ! grep -q "composer/vendor/bin" "$RC_FILE"; then
    echo -e '\n# Composer global bin\export PATH="$HOME/.config/composer/vendor/bin:$PATH"' >> "$RC_FILE"
    log_info "Composer path added to $RC_FILE"
fi

# --- Laravel Installer ---
echo ""
read -p "$(echo -e "${YELLOW}Install Laravel Installer globally? (Y/n):${NC} ")" -n 1 -r INSTALL_LARAVEL
echo
INSTALL_LARAVEL=${INSTALL_LARAVEL:-Y}
if [[ ! "$INSTALL_LARAVEL" =~ ^[Nn]$ ]]; then
    composer global require laravel/installer
    log_success "Laravel Installer installed globally."
fi

# --- Summary ---
echo ""
log_info "========================================================="
log_success "LARAVEL ENVIRONMENT SETUP COMPLETE for ${USER_NAME}!"
log_info "Installed components:"
echo "  - PHP ${PHP_VERSION}"
echo "  - Composer"
[[ ! "$INSTALL_NODE" =~ ^[Nn]$ ]] && echo "  - Node.js & npm"
case $DB_CHOICE in
    1) echo "  - MySQL" ;;
    2) echo "  - PostgreSQL" ;;
    3) echo "  - MongoDB" ;;
esac
[[ ! "$INSTALL_LARAVEL" =~ ^[Nn]$ ]] && echo "  - Laravel Installer"

log_info "Next steps:"
echo "  1. Run 'source ~/.zshrc' or open a new terminal"
echo "  2. Create new Laravel project: composer create-project laravel/laravel project-name"
[[ ! "$INSTALL_LARAVEL" =~ ^[Nn]$ ]] && echo "     or: laravel new project-name"
echo "  3. Configure .env with database credentials"
echo "  4. Run 'php artisan serve' to start server"
log_info "========================================================="

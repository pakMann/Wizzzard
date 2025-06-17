#!/bin/bash

# This script automates the initial setup of an Ubuntu server, including:
# - System updates and essential package installation
# - Creation of a non-root user with sudo privileges
# - SSH hardening (changing port, disabling root login, disabling password auth)
# - Installation and configuration of Oh My Zsh for root
# - Installation of Node.js and npm
# - Optional: Installation and basic configuration of PostgreSQL
# - Optional: Installation and configuration of Let's Encrypt (Certbot) for SSL
# - Installation of Nginx web server
# - Configuration and enabling of UFW firewall
#
# IMPORTANT NOTES BEFORE RUNNING:
# 1.  **RUN AS ROOT:** This script *must* be run as the root user or with `sudo`.
# 2.  **SSH ACCESS:** After the script finishes, you *must* use SSH keys to log in as the new non-root user. Password authentication for SSH will be disabled.
# 3.  **NEW SSH PORT:** The SSH port will be the one you specify. Remember this for future connections.
# 4.  **INTERACTIVITY:** The script will prompt you for a new non-root username and the desired SSH port. If you choose to install PostgreSQL or Let's Encrypt, it will also ask for additional details.
# 5.  **REVIEW CAREFULLY:** It's highly recommended to review the script content before execution to understand all changes being made to your system.
# 6.  **BACKUP:** Always back up important data before running significant system configuration scripts.

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

# --- 1. Initial System Update and Essential Packages ---
log_info "Starting initial system update and package installation..."
sudo apt update -y
sudo apt upgrade -y

log_info "Installing essential packages..."
sudo apt install -y build-essential curl git zsh gnupg software-properties-common apt-transport-https ca-certificates ruby-full libpq-dev

log_success "System updated and essential packages installed."

# --- 2. Oh My Zsh Installation for Root ---
log_info "Installing Oh My Zsh for root user..."
# Check if zsh is already the default shell for root
if [ "$(basename "$SHELL")" != "zsh" ]; then
    # Install Oh My Zsh for root
    # Use -y for non-interactive installation if possible, or bypass prompts
    CHSH=no RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || log_error "Oh My Zsh installation for root might have failed or already exists."
    # Set Zsh as default shell for root
    sudo chsh -s "$(which zsh)" root
    log_success "Oh My Zsh installed and Zsh set as default shell for root."
else
    log_info "Oh My Zsh or Zsh already configured for root. Skipping."
fi


# --- 3. Create Non-Root User and Configure Sudoers ---
log_info "Creating a new non-root user..."
read -p "Enter the desired non-root username: " NEW_USERNAME

if id "$NEW_USERNAME" &>/dev/null; then
    log_info "User '${NEW_USERNAME}' already exists. Skipping user creation."
else
    sudo adduser "$NEW_USERNAME"
    sudo usermod -aG sudo "$NEW_USERNAME"
    log_success "User '${NEW_USERNAME}' created and added to sudo group."
fi

# Set up SSH directory and authorized_keys for the new user
log_info "Setting up SSH for the new user."
sudo -u "$NEW_USERNAME" mkdir -p /home/"$NEW_USERNAME"/.ssh
# Copy root's authorized_keys to the new user's, assuming root already has keys
# This assumes you connected as root using SSH keys. If not, you'll need to manually
# add your public key to /home/$NEW_USERNAME/.ssh/authorized_keys after the script runs.
if [ -f /root/.ssh/authorized_keys ]; then
    sudo cp /root/.ssh/authorized_keys /home/"$NEW_USERNAME"/.ssh/authorized_keys
    sudo chown "$NEW_USERNAME":"$NEW_USERNAME" /home/"$NEW_USERNAME"/.ssh/authorized_keys
    sudo chmod 600 /home/"$NEW_USERNAME"/.ssh/authorized_keys
    log_success "Copied root's authorized_keys to '${NEW_USERNAME}'."
else
    log_info "No authorized_keys found for root. You will need to manually add your public SSH key to /home/${NEW_USERNAME}/.ssh/authorized_keys for the new user to log in."
fi

# Edit sudoers for the new user (e.g., enable passwordless sudo for specific commands or general sudo)
# For security, we will keep password required for sudo by default.
# The user can then run `sudo visudo` to modify this if desired.
log_info "Sudoers configuration: Keeping password required for sudo for '${NEW_USERNAME}'."
log_info "To enable passwordless sudo for this user, run 'sudo visudo' and add the following line:"
log_info "  ${NEW_USERNAME} ALL=(ALL) NOPASSWD:ALL"
log_info "To enable passwordless sudo for ALL users in sudo group, add the following line:"
log_info "  %sudo ALL=(ALL) NOPASSWD:ALL"
log_success "Non-root user setup complete."

# --- 4. SSH Hardening ---
log_info "Hardening SSH configuration..."
SSH_CONFIG="/etc/ssh/sshd_config"
# Prompt for SSH Port
read -p "$(echo -e "${YELLOW}Enter the desired SSH port (e.g., 2222): ${NC}")" SSH_PORT

# Validate SSH Port input
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1024 ] || [ "$SSH_PORT" -gt 65535 ]; then
    log_error "Invalid SSH port. Please enter a number between 1024 and 65535. Exiting."
    exit 1
fi


# Backup original sshd_config
sudo cp "$SSH_CONFIG" "$SSH_CONFIG".bak

# Change SSH port
sudo sed -i "s/^#\?Port .*/Port $SSH_PORT/" "$SSH_CONFIG"
log_info "SSH port changed to ${SSH_PORT}."

# Disable root login
sudo sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin no/" "$SSH_CONFIG"
log_info "Root login via SSH disabled."

# Disable password authentication (rely on SSH keys)
sudo sed -i "s/^#\?PasswordAuthentication .*/PasswordAuthentication no/" "$SSH_CONFIG"
log_info "Password authentication for SSH disabled."

# Disallow empty passwords
sudo sed -i "s/^#\?PermitEmptyPasswords .*/PermitEmptyPasswords no/" "$SSH_CONFIG"

# Use strict modes for SSH keys
sudo sed -i "s/^#\?StrictModes .*/StrictModes yes/" "$SSH_CONFIG"

# Allow only the new user to login (optional, but good for single-user servers)
# This assumes only the new user is allowed to log in via SSH.
if ! grep -q "^AllowUsers ${NEW_USERNAME}" "$SSH_CONFIG"; then
    echo "AllowUsers ${NEW_USERNAME}" | sudo tee -a "$SSH_CONFIG" > /dev/null
    log_info "SSH access restricted to user '${NEW_USERNAME}'."
fi

# Reload SSH service
log_info "Reloading SSH service to apply changes..."
sudo systemctl reload sshd || sudo systemctl restart sshd
log_success "SSH hardened. Remember to connect on port ${SSH_PORT} as '${NEW_USERNAME}' with your SSH key."


# --- 5. Node.js and npm Installation (via NodeSource PPA) ---
log_info "Installing Node.js and npm..."
# Add NodeSource APT repository
# Use the latest LTS version (e.g., node_20.x, node_21.x)
NODE_MAJOR_VERSION="20" # You can change this to '21', '22', etc. for newer versions

if ! grep -q "nodesource.com" /etc/apt/sources.list.d/nodesource.list &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_"$NODE_MAJOR_VERSION".x | sudo -E bash -
    log_info "NodeSource repository added for Node.js ${NODE_MAJOR_VERSION}.x."
else
    log_info "NodeSource repository already exists. Skipping adding it again."
fi

sudo apt install -y nodejs
log_success "Node.js and npm installed."
log_info "Node.js version: $(node -v)"
log_info "npm version: $(npm -v)"

# --- 6. PostgreSQL Installation (Optional) ---
log_info "PostgreSQL Setup (Optional)..."
read -p "$(echo -e "${YELLOW}Do you want to install and configure PostgreSQL? (y/N):${NC} ")" -n 1 -r PG_INSTALL_CHOICE
echo # Newline

POSTGRES_INSTALLED="no" # Initialize flag

if [[ "$PG_INSTALL_CHOICE" =~ ^[Yy]$ ]]; then
    log_info "Proceeding with PostgreSQL installation."
    read -p "$(echo -e "Enter desired PostgreSQL username (e.g., '${YELLOW}appuser${NC}'): ")" PG_USERNAME
    read -s -p "$(echo -e "Enter desired PostgreSQL password for '${YELLOW}${PG_USERNAME}${NC}': ")" PG_PASSWORD
    echo # Newline
    read -p "$(echo -e "Enter desired PostgreSQL database name for '${YELLOW}${PG_USERNAME}${NC}': ")" PG_DBNAME

    # Validate inputs (basic check)
    if [ -z "$PG_USERNAME" ] || [ -z "$PG_PASSWORD" ] || [ -z "$PG_DBNAME" ]; then
        log_error "PostgreSQL username, password, or database name cannot be empty. Skipping PostgreSQL setup."
    else
        sudo apt install -y postgresql postgresql-contrib
        log_success "PostgreSQL installed."

        log_info "Configuring PostgreSQL..."

        # Check if PostgreSQL user already exists
        if sudo -u postgres psql -tAc "SELECT 1 FROM pg_user WHERE usename = '$PG_USERNAME'" | grep -q 1; then
            log_info "PostgreSQL user '${PG_USERNAME}' already exists. Skipping user creation."
        else
            log_info "Creating PostgreSQL user '${PG_USERNAME}'..."
            if sudo -u postgres psql -c "CREATE USER $PG_USERNAME WITH PASSWORD '$PG_PASSWORD';" &>/dev/null; then
                log_success "PostgreSQL user '${PG_USERNAME}' created successfully."
            else
                log_error "Failed to create PostgreSQL user '${PG_USERNAME}'. Please check PostgreSQL logs. Skipping further PostgreSQL setup."
                exit 1 # Exit on critical failure
            fi
        fi

        # Check if PostgreSQL database already exists
        if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname = '$PG_DBNAME'" | grep -q 1; then
            log_info "PostgreSQL database '${PG_DBNAME}' already exists. Skipping database creation."
        else
            log_info "Creating PostgreSQL database '${PG_DBNAME}'..."
            if sudo -u postgres psql -c "CREATE DATABASE $PG_DBNAME OWNER $PG_USERNAME;" &>/dev/null; then
                log_success "PostgreSQL database '${PG_DBNAME}' created successfully."
            else
                log_error "Failed to create PostgreSQL database '${PG_DBNAME}'. Please check PostgreSQL logs. Exiting."
                exit 1
            fi
        fi

        PG_VERSION=$(ls -d /etc/postgresql/*/main | head -n 1 | cut -d'/' -f4)
        PG_HBA_FILE="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"
        PG_HBA_LINE="local   ${PG_DBNAME}       ${PG_USERNAME}         md5"

        if ! sudo grep -q "$PG_HBA_LINE" "$PG_HBA_FILE"; then
            log_info "Adding local PostgreSQL user authentication for '${PG_USERNAME}' to ${PG_HBA_FILE}."
            echo "$PG_HBA_LINE" | sudo tee -a "$PG_HBA_FILE" > /dev/null
            log_success "Added PostgreSQL authentication entry."
        else
            log_info "PostgreSQL authentication entry for '${PG_USERNAME}' already exists in ${PG_HBA_FILE}."
        fi

        log_info "Restarting PostgreSQL service to apply changes..."
        if sudo systemctl restart postgresql; then
            log_success "PostgreSQL restarted successfully."
        else
            log_error "Failed to restart PostgreSQL. Please check logs for details. Exiting."
            exit 1
        fi
        log_success "PostgreSQL installed and configured. User '${PG_USERNAME}' can access database '${PG_DBNAME}'."
        POSTGRES_INSTALLED="yes" # Set flag if successful
    fi
else
    log_info "Skipping PostgreSQL installation."
fi

# --- 7. Nginx Installation ---
log_info "Installing Nginx..."
sudo apt install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx

# Remove default Nginx site to prepare for custom configurations
if [ -f /etc/nginx/sites-enabled/default ]; then
    sudo rm /etc/nginx/sites-enabled/default
    log_info "Removed default Nginx site."
fi

log_success "Nginx installed and started."

# --- 8. Let's Encrypt (Certbot) Installation (Optional) ---
log_info "Let's Encrypt (Certbot) Setup (Optional)..."
read -p "$(echo -e "${YELLOW}Do you want to install Let's Encrypt (Certbot) for SSL? (y/N):${NC} ")" -n 1 -r LETSENCRYPT_INSTALL_CHOICE
echo # Newline

LETSENCRYPT_INSTALLED="no" # Initialize flag

if [[ "$LETSENCRYPT_INSTALL_CHOICE" =~ ^[Yy]$ ]]; then
    log_info "Proceeding with Let's Encrypt (Certbot) installation."
    read -p "$(echo -e "Enter your domain name (e.g., '${YELLOW}yourdomain.com${NC}'): ")" DOMAIN_NAME
    read -p "$(echo -e "Enter your email address for urgent renewal notices (e.g., '${YELLOW}admin@yourdomain.com${NC}'): ")" ADMIN_EMAIL

    if [ -z "$DOMAIN_NAME" ] || [ -z "$ADMIN_EMAIL" ]; then
        log_error "Domain name and email cannot be empty. Skipping Let's Encrypt setup."
    else
        log_info "Installing snapd and Certbot..."
        sudo apt update
        sudo apt install -y snapd
        sudo snap install core
        sudo snap refresh core

        # Remove any pre-existing Certbot installations from apt
        sudo apt remove -y certbot

        # Install Certbot via snap
        sudo snap install --classic certbot
        sudo ln -s /snap/bin/certbot /usr/bin/certbot

        log_success "Certbot installed."

        log_info "Configuring Certbot for domain ${DOMAIN_NAME}..."
        # Before running certbot, ensure Nginx is running and serving a basic page for domain validation.
        # This script already installs Nginx. You might need to manually set up a basic Nginx server block
        # for your domain if Certbot auto-detection fails, but --nginx plugin usually handles this.
        if certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos -m "$ADMIN_EMAIL" --redirect --staple-ocsp; then
            log_success "Let's Encrypt certificate obtained and configured for ${DOMAIN_NAME}."
            LETSENCRYPT_INSTALLED="yes" # Set flag if successful
        else
            log_error "Failed to obtain Let's Encrypt certificate for ${DOMAIN_NAME}. Please check Certbot logs."
            log_error "Ensure your domain's DNS A/AAAA records point to this server."
        fi
    fi
else
    log_info "Skipping Let's Encrypt (Certbot) installation."
fi


# --- 9. UFW (Uncomplicated Firewall) Configuration ---
log_info "Configuring UFW firewall..."
sudo apt install -y ufw

sudo ufw allow "$SSH_PORT"/tcp comment 'Allow SSH on custom port'
sudo ufw allow http comment 'Allow HTTP (port 80)'
sudo ufw allow https comment 'Allow HTTPS (port 443)'

# Enable UFW
log_info "Enabling UFW. This will activate the firewall rules."
sudo ufw enable <<EOF
y
EOF

sudo ufw status verbose
log_success "UFW configured and enabled."

# --- 10. Additional Hardening & Cleanup ---
log_info "Performing additional hardening and cleanup..."

# Disable unwanted services (example: Avahi-daemon, CUPS if not needed)
# sudo systemctl disable avahi-daemon.service || true
# sudo systemctl stop avahi-daemon.service || true
# sudo systemctl disable cups.service || true
# sudo systemctl stop cups.service || true

# Remove unused packages
sudo apt autoremove -y
sudo apt clean

log_success "Additional hardening and cleanup complete."

# --- 11. IMPORTANT INFORMATION & NEXT STEPS ---
# Get the current public IP address of the server
SERVER_PUBLIC_IP=$(curl -s https://api.ipify.org)
if [ -z "$SERVER_PUBLIC_IP" ]; then
    log_error "Could not determine the server's public IP address. Please find it manually from your VPS provider."
    SERVER_PUBLIC_IP="YOUR_SERVER_IP" # Fallback to placeholder if IP cannot be fetched
fi

log_info "---------------------------------------------------------"
log_info "SERVER SETUP COMPLETE!"
log_info "---------------------------------------------------------"
log_info "IMPORTANT NOTES BEFORE RUNNING THE SCRIPT:"
log_info "1.  ${YELLOW}RUN AS ROOT:${NC} This script *must* be run as the root user or with `sudo`."
log_info "2.  ${YELLOW}SSH ACCESS:${NC} After the script finishes, you *must* use SSH keys to log in as the new non-root user. Password authentication for SSH will be disabled."
log_info "3.  ${YELLOW}NEW SSH PORT:${NC} The SSH port will be the one you enter during script execution. Remember this for future connections."
log_info "4.  ${YELLOW}INTERACTIVITY:${NC} The script will prompt you to enter the new non-root username and the desired SSH port. If you choose to install PostgreSQL or Let's Encrypt, you will be prompted for additional details."
log_info "5.  ${YELLOW}REVIEW CAREFULLY:${NC} It is highly recommended to review the script contents before execution to understand all changes being made to your system."
log_info "6.  ${YELLOW}BACKUP:${NC} Always back up important data before running significant system configuration scripts."
log_info ""
log_info "NEXT STEPS (AFTER LOGGING OUT FROM ROOT):"
log_info "1.  ${GREEN}DISCONNECT:${NC} Disconnect from the current root SSH session."
log_info "2.  ${GREEN}LOGIN AS NEW USER:${NC} ssh -p ${SSH_PORT} ${NEW_USERNAME}@${SERVER_PUBLIC_IP}"
log_info "    (Make sure your SSH public key is in /home/${NEW_USERNAME}/.ssh/authorized_keys on the server.)"
log_info "3.  ${GREEN}VERIFY SUDO:${NC} After logging in as '${NEW_USERNAME}', try 'sudo ls /root' to verify sudo works."
log_info "4.  ${GREEN}RUN USER SETUP:${NC} Download and run the 'user-setup.sh' script (provided separately) as user '${NEW_USERNAME}'."
log_info "    ${YELLOW}curl -sL <URL_GIST_USER_SETUP_SCRIPT> -o user-setup.sh${NC}"
log_info "    ${YELLOW}chmod +x user-setup.sh${NC}"
log_info "    ${YELLOW}./user-setup.sh${NC}"
# Use a conditional message for PostgreSQL
if [[ "$POSTGRES_INSTALLED" == "yes" ]]; then
    log_info "5.  ${GREEN}POSTGRESQL (OPTIONAL):${NC} If you installed PostgreSQL, you can connect using 'psql -U ${PG_USERNAME} -d ${PG_DBNAME}'."
fi
# Use a conditional message for Let's Encrypt
if [[ "$LETSENCRYPT_INSTALLED" == "yes" ]]; then
    log_info "6.  ${GREEN}LET'S ENCRYPT SSL:${NC} A certificate for ${DOMAIN_NAME} has been installed. Certbot will automatically renew it."
    log_info "    You can test your SSL setup at: https://www.ssllabs.com/ssltest/analyze.html?d=${DOMAIN_NAME}"
fi
log_info "7.  ${GREEN}NGINX:${NC} Place your web files in /var/www/html or configure new sites in /etc/nginx/sites-available/."
log_info "8.  ${GREEN}AUTOMATIC UPDATES:${NC} Consider setting up 'unattended-upgrades' for automatic security updates."
log_info "9.  ${GREEN}REVIEW CONFIGURATION:${NC} Review all configurations and adjust them to your specific needs."
log_info "---------------------------------------------------------"

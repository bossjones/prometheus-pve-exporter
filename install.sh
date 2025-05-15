#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status messages
print_status() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_error() {
    echo -e "${RED}[!]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run this script as root or with sudo"
    exit 1
fi

# Create necessary directories
print_status "Creating necessary directories..."
mkdir -p /etc/prometheus
mkdir -p /var/log

# Create prometheus user and group with specific IDs to match Docker setup
print_status "Setting up prometheus user and group..."
if ! getent group prometheus >/dev/null; then
    groupadd -r -g 1002 prometheus
fi
if ! getent passwd prometheus >/dev/null; then
    useradd -r -u 1002 -g prometheus -d /nonexistent -s /sbin/nologin prometheus
fi

# Check and update environment variables in the .env file
print_status "Checking for environment variables..."
if [ -f "prometheus-pve-exporter.env" ]; then
    # Create a temporary file
    tmp_env=$(mktemp)
    cp prometheus-pve-exporter.env "$tmp_env"

    # Update PVE_USER if set
    if [ ! -z "$PVE_USER" ]; then
        print_status "Setting PVE_USER from environment"
        sed -i "s|^PVE_USER=.*|PVE_USER=$PVE_USER|" "$tmp_env"
    fi

    # Update PVE_PASSWORD if set
    if [ ! -z "$PVE_PASSWORD" ]; then
        print_status "Setting PVE_PASSWORD from environment"
        sed -i "s|^PVE_PASSWORD=.*|PVE_PASSWORD=$PVE_PASSWORD|" "$tmp_env"
    fi

    # Update PVE_HOST if set
    if [ ! -z "$PVE_HOST" ]; then
        print_status "Setting PVE_HOST from environment"
        sed -i "s|^PVE_HOST=.*|PVE_HOST=$PVE_HOST|" "$tmp_env"
    fi

    # Install the updated environment file
    mv "$tmp_env" /etc/prometheus/prometheus-pve-exporter.env
    chown prometheus:prometheus /etc/prometheus/prometheus-pve-exporter.env
    chmod 600 /etc/prometheus/prometheus-pve-exporter.env
    print_status "Installed prometheus-pve-exporter.env to /etc/prometheus/"

    # Check if any required variables are still not set
    if grep -q "YOUR_PASSWORD_HERE" /etc/prometheus/prometheus-pve-exporter.env; then
        print_warning "Some required variables are not set in the environment file!"
        print_warning "Please edit /etc/prometheus/prometheus-pve-exporter.env to set them."
    fi
else
    print_error "prometheus-pve-exporter.env not found in current directory!"
    exit 1
fi

# Install the systemd service
print_status "Installing systemd service..."
if [ -f "prometheus-pve-exporter.service" ]; then
    cp prometheus-pve-exporter.service /etc/systemd/system/
    chmod 644 /etc/systemd/system/prometheus-pve-exporter.service
    print_status "Installed prometheus-pve-exporter.service to /etc/systemd/system/"
else
    print_error "prometheus-pve-exporter.service not found in current directory!"
    exit 1
fi

# Create log file
print_status "Setting up log file..."
touch /var/log/pve-exporter.log
chown prometheus:prometheus /var/log/pve-exporter.log
chmod 644 /var/log/pve-exporter.log

# Reload systemd and enable service
print_status "Configuring systemd service..."
systemctl daemon-reload
systemctl enable prometheus-pve-exporter

# Only show warning if required variables are not set
if grep -q "YOUR_PASSWORD_HERE" /etc/prometheus/prometheus-pve-exporter.env; then
    print_warning "Before starting the service, please edit /etc/prometheus/prometheus-pve-exporter.env with your Proxmox credentials!"
    print_warning "Edit the file using: sudo nano /etc/prometheus/prometheus-pve-exporter.env"
fi

# Ask user if they want to start the service now
read -p "Would you like to start the service now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Starting prometheus-pve-exporter service..."
    systemctl start prometheus-pve-exporter

    # Check if service started successfully
    if systemctl is-active --quiet prometheus-pve-exporter; then
        print_status "Service started successfully!"
        print_status "You can check the status using: systemctl status prometheus-pve-exporter"
        print_status "The exporter will be accessible at: http://localhost:9221/pve?target=${PVE_HOST}"
    else
        print_error "Service failed to start. Please check the logs:"
        print_error "journalctl -u prometheus-pve-exporter -n 50"
    fi
else
    print_warning "Service not started. You can start it later using:"
    print_warning "sudo systemctl start prometheus-pve-exporter"
fi

print_status "Installation completed!"
echo
print_status "Next steps:"
if grep -q "YOUR_PASSWORD_HERE" /etc/prometheus/prometheus-pve-exporter.env; then
    echo "1. Edit /etc/prometheus/prometheus-pve-exporter.env with your Proxmox credentials"
fi
echo "2. Start the service if you haven't already: sudo systemctl start prometheus-pve-exporter"
echo "3. Check the service status: sudo systemctl status prometheus-pve-exporter"
echo "4. View logs: sudo journalctl -u prometheus-pve-exporter -f"

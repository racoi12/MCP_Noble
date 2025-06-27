#!/bin/bash
# =============================================================================
# MCP Ubuntu Shell Server - One-Line Installer
# =============================================================================
# Quick installer for Model Context Protocol shell server on Ubuntu Noble
# Repository: https://github.com/racoi12/MCP_Noble
# Usage: curl -fsSL https://raw.githubusercontent.com/racoi12/MCP_Noble/main/install.sh | bash
# =============================================================================

set -euo pipefail

# Colors and styling
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Configuration
readonly REPO_URL="https://raw.githubusercontent.com/racoi12/MCP_Noble/main"
readonly INSTALL_DIR="$HOME/mcp-installer"
readonly LOG_FILE="$INSTALL_DIR/install.log"

# =============================================================================
# Utility Functions
# =============================================================================

info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${YELLOW}[WARNING]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${RED}[ERROR]${NC} $*"
}

step() {
    echo -e "${CYAN}[STEP]${NC} $*" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${CYAN}[STEP]${NC} $*"
}

show_banner() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║              MCP Ubuntu Shell Server Installer                  ║
║                                                                  ║
║  🚀 One-command setup for Model Context Protocol               ║
║  🌐 Shell access via web interface                             ║
║  🛡️ Secure, whitelist-based command execution                 ║
║  ⚡ Ready in 2-5 minutes                                       ║
║                                                                  ║
║  Repository: github.com/racoi12/MCP_Noble                      ║
╚══════════════════════════════════════════════════════════════════╝
EOF
}

# =============================================================================
# Pre-flight Checks
# =============================================================================

check_requirements() {
    step "Checking system requirements..."
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot detect operating system"
        exit 1
    fi
    
    local os_id=$(grep '^ID=' /etc/os-release | cut -d'=' -f2)
    local version_id=$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    
    if [[ "$os_id" != "ubuntu" ]]; then
        error "This installer requires Ubuntu (detected: $os_id)"
        exit 1
    fi
    
    if [[ "$version_id" != "24.04" ]]; then
        warning "This installer is designed for Ubuntu 24.04 (detected: $version_id)"
        warning "Proceeding anyway, but some features may not work correctly"
    fi
    
    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        error "No internet connection detected"
        exit 1
    fi
    
    # Check disk space (need at least 1GB)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 1048576 ]]; then  # 1GB in KB
        error "Insufficient disk space (need at least 1GB free)"
        exit 1
    fi
    
    success "System requirements check passed"
}

check_permissions() {
    step "Checking permissions..."
    
    if [[ $EUID -eq 0 ]]; then
        error "This installer should not be run as root"
        error "Please run as a regular user with sudo privileges"
        exit 1
    fi
    
    if ! sudo -n true 2>/dev/null; then
        info "Sudo access is required for this installation"
        
        if ! sudo true; then
            error "Sudo access is required but not available"
            exit 1
        fi
    fi
    
    success "Permission check passed"
}

# =============================================================================
# Download and Setup
# =============================================================================

setup_environment() {
    step "Setting up installation environment..."
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # Initialize log file
    echo "=== MCP Ubuntu Shell Server Installation Started - $(date) ===" > "$LOG_FILE"
    
    success "Installation environment ready"
}

download_scripts() {
    step "Downloading installation scripts..."
    
    local files=(
        "mcp.sh"
        "simple_http_server.py"
    )
    
    for file in "${files[@]}"; do
        info "Downloading $file..."
        if curl -fsSL "$REPO_URL/$file" -o "$file"; then
            chmod +x "$file"
            success "Downloaded $file"
        else
            error "Failed to download $file from $REPO_URL/$file"
            error "Please check your internet connection and try again"
            exit 1
        fi
    done
    
    success "All scripts downloaded successfully"
}

# =============================================================================
# Installation Process
# =============================================================================

run_main_installation() {
    step "Running main MCP installation..."
    
    info "This will install:"
    info "  • Model Context Protocol (MCP) server"
    info "  • Python dependencies and pipx"
    info "  • Systemd service for auto-start"
    info "  • Security configurations"
    info "  • Testing and monitoring tools"
    
    # Run main setup script with automatic yes
    if ./mcp.sh --yes install; then
        success "Main MCP installation completed successfully"
    else
        error "Main installation failed"
        error "Check log file: $LOG_FILE"
        error "Try manual installation: ./mcp.sh --debug install"
        exit 1
    fi
}

setup_web_server() {
    step "Setting up web interface..."
    
    # Copy web server to config directory
    if [[ ! -d ~/.config/mcp ]]; then
        error "MCP config directory not found. Main installation may have failed."
        exit 1
    fi
    
    cp simple_http_server.py ~/.config/mcp/
    chmod +x ~/.config/mcp/simple_http_server.py
    
    success "Web interface copied to ~/.config/mcp/"
}

# =============================================================================
# Post-Installation
# =============================================================================

configure_firewall() {
    step "Configuring firewall..."
    
    # Check if ufw is installed and enabled
    if command -v ufw &> /dev/null; then
        # Allow MCP web server port
        sudo ufw allow 8080/tcp &> /dev/null || true
        info "Firewall rule added for port 8080"
    else
        warning "UFW firewall not found - you may need to manually configure firewall rules"
    fi
    
    success "Firewall configuration completed"
}

run_verification() {
    step "Running installation verification..."
    
    # Wait for services to start
    sleep 5
    
    # Check MCP shell server
    if systemctl is-active --quiet mcp-shell-server 2>/dev/null; then
        success "✓ MCP shell server is running"
    else
        warning "✗ MCP shell server is not running"
        warning "  Check status: sudo systemctl status mcp-shell-server"
    fi
    
    # Check if we can start web server
    if [[ -x ~/.config/mcp/simple_http_server.py ]]; then
        success "✓ Web server script is ready"
    else
        warning "✗ Web server script not found or not executable"
    fi
    
    # Run test suite if available
    if [[ -x ~/.config/mcp/test_mcp.sh ]]; then
        info "Running automated test suite..."
        ~/.config/mcp/test_mcp.sh 2>&1 | tee -a "$LOG_FILE" || true
    fi
}

get_server_info() {
    step "Getting server information..."
    
    # Get IP addresses
    local internal_ip=$(ip route get 1 2>/dev/null | awk '{print $7}' | head -1 || echo "localhost")
    
    info "Server IP address: $internal_ip"
    
    return 0
}

show_completion() {
    local internal_ip=$(ip route get 1 2>/dev/null | awk '{print $7}' | head -1 || echo "localhost")
    
    cat << EOF

╔══════════════════════════════════════════════════════════════════╗
║                    🎉 Installation Complete! 🎉                 ║
╚══════════════════════════════════════════════════════════════════╝

🚀 MCP Ubuntu Shell Server is now installed!

🌐 To start the web interface:
  python3 ~/.config/mcp/simple_http_server.py

📍 Then access via:
  • Web Interface: http://${internal_ip}:8080
  • Local Access:  http://localhost:8080
  • Health Check:  http://${internal_ip}:8080/health

🧪 Test Commands:
  curl http://${internal_ip}:8080/health
  curl -X POST http://${internal_ip}:8080/execute -d "command=uname -a"

🔧 Management Commands:
  • Check status:    sudo systemctl status mcp-shell-server
  • View logs:       sudo journalctl -u mcp-shell-server -f
  • Test suite:      ~/.config/mcp/test_mcp.sh
  • Monitor:         ~/.config/mcp/monitor_mcp.sh

📁 Configuration:
  • Config dir:      ~/.config/mcp/
  • Main config:     ~/.config/mcp/.env
  • Web server:      ~/.config/mcp/simple_http_server.py

🛡️ Security:
  • Only whitelisted commands are allowed
  • Edit ~/.config/mcp/.env to customize allowed commands
  • Use firewall rules to restrict network access

📚 Documentation:
  • GitHub: https://github.com/racoi12/MCP_Noble
  • Issues: https://github.com/racoi12/MCP_Noble/issues

🚀 Quick Start Web Server:
  cd ~/.config/mcp && python3 simple_http_server.py

Happy shell commanding! 🚀

EOF

    success "Installation completed successfully!"
    info "Installation log saved to: $LOG_FILE"
}

# =============================================================================
# Main Installation Flow
# =============================================================================

main() {
    show_banner
    echo
    
    # Pre-flight checks
    check_requirements
    check_permissions
    
    # Setup
    setup_environment
    download_scripts
    
    # Installation
    run_main_installation
    setup_web_server
    
    # Post-installation
    configure_firewall
    run_verification
    get_server_info
    
    # Completion
    show_completion
}

# =============================================================================
# Error Handling
# =============================================================================

cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo
        error "Installation failed with exit code $exit_code"
        error "Check the log file for details: $LOG_FILE"
        error "You can also try manual installation:"
        error "  1. wget https://raw.githubusercontent.com/racoi12/MCP_Noble/main/mcp.sh"
        error "  2. chmod +x mcp.sh"
        error "  3. ./mcp.sh --yes install"
        echo
        error "For support, visit: https://github.com/racoi12/MCP_Noble/issues"
    fi
    exit $exit_code
}

trap cleanup EXIT

# =============================================================================
# Entry Point
# =============================================================================

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

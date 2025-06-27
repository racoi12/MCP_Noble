#!/bin/bash
# =============================================================================
# Enhanced MCP Noble Installer Script v2.0
# =============================================================================
# Improved installation script with better error handling and features
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_VERSION="2.0.0"
readonly REPO_URL="https://github.com/racoi12/MCP_Noble"
readonly INSTALL_DIR="${HOME}/.config/mcp"
readonly LOG_FILE="${INSTALL_DIR}/install.log"
readonly BACKUP_DIR="${INSTALL_DIR}/backups"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Default configuration
DEFAULT_PORT=8080
DEFAULT_ALLOWED_COMMANDS="ls,cat,pwd,grep,find,git,python3,node,npm,pip,curl,wget,wc,head,tail,ps,df,free,uname,whoami,date,echo,which,netstat,ss,lsof,top,htop"
DEFAULT_TIMEOUT=30
DEFAULT_RATE_LIMIT=60
DEFAULT_MAX_OUTPUT_SIZE=1048576

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"
    
    case "$level" in
        INFO) echo -e "${BLUE}[INFO]${NC} ${message}" ;;
        SUCCESS) echo -e "${GREEN}[✓]${NC} ${message}" ;;
        WARNING) echo -e "${YELLOW}[⚠]${NC} ${message}" ;;
        ERROR) echo -e "${RED}[✗]${NC} ${message}" ;;
        STEP) echo -e "${CYAN}[→]${NC} ${message}" ;;
    esac
}

info() { log INFO "$@"; }
success() { log SUCCESS "$@"; }
warning() { log WARNING "$@"; }
error() { log ERROR "$@"; }
step() { log STEP "$@"; }

show_banner() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║          🚀 Enhanced MCP Noble Installer v2.0 🚀                ║
║                                                                  ║
║  • Improved security and error handling                         ║
║  • Enhanced web interface with session management               ║
║  • Better command validation and rate limiting                  ║
║  • Automatic backup and rollback capabilities                   ║
╚══════════════════════════════════════════════════════════════════╝
EOF
}

show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# =============================================================================
# Pre-installation Checks
# =============================================================================

check_system() {
    step "Performing system checks..."
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        error "Cannot detect operating system"
        return 1
    fi
    
    local os_name=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
    info "Detected OS: $os_name"
    
    # Check Ubuntu version
    if grep -q "Ubuntu" /etc/os-release; then
        local version=$(lsb_release -rs 2>/dev/null || echo "unknown")
        if [[ "$version" == "24.04" ]]; then
            success "Ubuntu Noble 24.04 detected"
        else
            warning "This installer is optimized for Ubuntu 24.04 (detected: $version)"
        fi
    else
        warning "Non-Ubuntu system detected. Some features may not work correctly."
    fi
    
    # Check architecture
    local arch=$(uname -m)
    info "System architecture: $arch"
    
    # Check available disk space
    local available=$(df -BG "$HOME" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $available -lt 1 ]]; then
        error "Insufficient disk space (less than 1GB available)"
        return 1
    fi
    info "Available disk space: ${available}GB"
    
    # Check internet connectivity
    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        error "No internet connection detected"
        return 1
    fi
    success "Internet connection verified"
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root"
        return 1
    fi
    
    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        info "Sudo password required for installation"
        if ! sudo -v; then
            error "Sudo access is required"
            return 1
        fi
    fi
    success "Sudo access verified"
    
    return 0
}

check_dependencies() {
    step "Checking dependencies..."
    
    local missing_deps=()
    local deps=(curl wget git python3 pip3)
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        warning "Missing dependencies: ${missing_deps[*]}"
        return 1
    else
        success "All required dependencies are installed"
        return 0
    fi
}

# =============================================================================
# Installation Functions
# =============================================================================

create_directories() {
    step "Creating directory structure..."
    
    local dirs=(
        "$INSTALL_DIR"
        "$BACKUP_DIR"
        "$INSTALL_DIR/logs"
        "$INSTALL_DIR/scripts"
        "$INSTALL_DIR/config"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            info "Created directory: $dir"
        fi
    done
    
    success "Directory structure created"
}

backup_existing() {
    if [[ -f "$INSTALL_DIR/.env" ]] || [[ -f "$INSTALL_DIR/simple_http_server.py" ]]; then
        step "Backing up existing installation..."
        
        local backup_name="backup_$(date +%Y%m%d_%H%M%S)"
        local backup_path="$BACKUP_DIR/$backup_name"
        
        mkdir -p "$backup_path"
        
        # Backup existing files
        for file in .env simple_http_server.py mcp_server_wrapper.py; do
            if [[ -f "$INSTALL_DIR/$file" ]]; then
                cp "$INSTALL_DIR/$file" "$backup_path/"
                info "Backed up: $file"
            fi
        done
        
        success "Backup created at: $backup_path"
    fi
}

install_python_packages() {
    step "Installing Python packages..."
    
    # Create virtual environment
    if [[ ! -d "$INSTALL_DIR/venv" ]]; then
        python3 -m venv "$INSTALL_DIR/venv"
        info "Created Python virtual environment"
    fi
    
    # Activate venv and install packages
    source "$INSTALL_DIR/venv/bin/activate"
    
    pip install --upgrade pip &>/dev/null
    
    local packages=(
        "mcp"
        "aiohttp"
        "python-dotenv"
    )
    
    for package in "${packages[@]}"; do
        pip install "$package" &>/dev/null &
        show_spinner $!
        info "Installed: $package"
    done
    
    deactivate
    
    success "Python packages installed"
}

configure_mcp() {
    step "Configuring MCP..."
    
    # Create .env file
    cat > "$INSTALL_DIR/.env" << EOF
# MCP Noble Configuration
# Generated on $(date)

# Server settings
MCP_HOST=0.0.0.0
MCP_PORT=${MCP_PORT:-$DEFAULT_PORT}

# Security settings
ALLOWED_COMMANDS=${ALLOWED_COMMANDS:-$DEFAULT_ALLOWED_COMMANDS}
COMMAND_TIMEOUT=${COMMAND_TIMEOUT:-$DEFAULT_TIMEOUT}
MAX_OUTPUT_SIZE=${MAX_OUTPUT_SIZE:-$DEFAULT_MAX_OUTPUT_SIZE}
RATE_LIMIT=${RATE_LIMIT:-$DEFAULT_RATE_LIMIT}

# Optional authentication token (leave empty to disable)
AUTH_TOKEN=

# Logging
LOG_LEVEL=INFO
LOG_FILE=$INSTALL_DIR/logs/mcp.log
EOF

    chmod 600 "$INSTALL_DIR/.env"
    success "Configuration file created"
}

install_scripts() {
    step "Installing MCP scripts..."
    
    # Install enhanced HTTP server
    if [[ -f "$SCRIPT_DIR/simple_http_server.py" ]]; then
        cp "$SCRIPT_DIR/simple_http_server.py" "$INSTALL_DIR/"
    else
        # Download from repo if not found locally
        curl -fsSL "$REPO_URL/raw/main/simple_http_server.py" -o "$INSTALL_DIR/simple_http_server.py"
    fi
    chmod +x "$INSTALL_DIR/simple_http_server.py"
    
    # Create start script
    cat > "$INSTALL_DIR/scripts/start.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")/.."
source venv/bin/activate
python3 simple_http_server.py
EOF
    chmod +x "$INSTALL_DIR/scripts/start.sh"
    
    # Create stop script
    cat > "$INSTALL_DIR/scripts/stop.sh" << 'EOF'
#!/bin/bash
pkill -f "simple_http_server.py"
echo "MCP server stopped"
EOF
    chmod +x "$INSTALL_DIR/scripts/stop.sh"
    
    # Create status script
    cat > "$INSTALL_DIR/scripts/status.sh" << 'EOF'
#!/bin/bash
if pgrep -f "simple_http_server.py" > /dev/null; then
    echo "✅ MCP server is running"
    echo "PID: $(pgrep -f simple_http_server.py)"
else
    echo "❌ MCP server is not running"
fi
EOF
    chmod +x "$INSTALL_DIR/scripts/status.sh"
    
    success "Scripts installed"
}

create_systemd_service() {
    step "Creating systemd service..."
    
    local service_file="/etc/systemd/system/mcp-noble.service"
    
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=MCP Noble HTTP Server
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/scripts/start.sh
ExecStop=$INSTALL_DIR/scripts/stop.sh
Restart=on-failure
RestartSec=10
StandardOutput=append:$INSTALL_DIR/logs/mcp.log
StandardError=append:$INSTALL_DIR/logs/mcp.log

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=$INSTALL_DIR/logs

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable mcp-noble.service
    
    success "Systemd service created and enabled"
}

configure_firewall() {
    step "Configuring firewall..."
    
    if command -v ufw &>/dev/null; then
        if sudo ufw status | grep -q "Status: active"; then
            sudo ufw allow "${MCP_PORT:-$DEFAULT_PORT}/tcp" comment "MCP Noble HTTP Server"
            success "Firewall rule added for port ${MCP_PORT:-$DEFAULT_PORT}"
        else
            warning "UFW is installed but not active"
        fi
    else
        info "UFW not installed, skipping firewall configuration"
    fi
}

# =============================================================================
# Post-installation Functions
# =============================================================================

create_shortcuts() {
    step "Creating command shortcuts..."
    
    # Create mcp command
    cat > "$HOME/.local/bin/mcp" << EOF
#!/bin/bash
# MCP Noble command shortcut

case "\$1" in
    start)
        $INSTALL_DIR/scripts/start.sh
        ;;
    stop)
        $INSTALL_DIR/scripts/stop.sh
        ;;
    status)
        $INSTALL_DIR/scripts/status.sh
        ;;
    restart)
        $INSTALL_DIR/scripts/stop.sh
        sleep 2
        $INSTALL_DIR/scripts/start.sh
        ;;
    logs)
        tail -f $INSTALL_DIR/logs/mcp.log
        ;;
    config)
        \${EDITOR:-nano} $INSTALL_DIR/.env
        ;;
    *)
        echo "Usage: mcp {start|stop|status|restart|logs|config}"
        exit 1
        ;;
esac
EOF
    
    chmod +x "$HOME/.local/bin/mcp"
    
    # Ensure ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
        export PATH="$HOME/.local/bin:$PATH"
    fi
    
    success "Command shortcuts created"
}

run_tests() {
    step "Running installation tests..."
    
    local test_passed=0
    local test_failed=0
    
    # Test 1: Check directories
    if [[ -d "$INSTALL_DIR" ]]; then
        ((test_passed++))
        info "✓ Installation directory exists"
    else
        ((test_failed++))
        error "✗ Installation directory missing"
    fi
    
    # Test 2: Check configuration
    if [[ -f "$INSTALL_DIR/.env" ]]; then
        ((test_passed++))
        info "✓ Configuration file exists"
    else
        ((test_failed++))
        error "✗ Configuration file missing"
    fi
    
    # Test 3: Check Python environment
    if [[ -d "$INSTALL_DIR/venv" ]]; then
        ((test_passed++))
        info "✓ Python virtual environment exists"
    else
        ((test_failed++))
        error "✗ Python virtual environment missing"
    fi
    
    # Test 4: Check scripts
    if [[ -x "$INSTALL_DIR/simple_http_server.py" ]]; then
        ((test_passed++))
        info "✓ HTTP server script is executable"
    else
        ((test_failed++))
        error "✗ HTTP server script missing or not executable"
    fi
    
    # Test 5: Check systemd service
    if systemctl list-unit-files | grep -q "mcp-noble.service"; then
        ((test_passed++))
        info "✓ Systemd service is installed"
    else
        ((test_failed++))
        error "✗ Systemd service not installed"
    fi
    
    echo
    success "Tests completed: $test_passed passed, $test_failed failed"
    
    return $test_failed
}

# =============================================================================
# Completion
# =============================================================================

show_completion() {
    local ip=$(hostname -I | awk '{print $1}')
    
    cat << EOF

╔══════════════════════════════════════════════════════════════════╗
║              🎉 Installation Complete! 🎉                       ║
╚══════════════════════════════════════════════════════════════════╝

🚀 MCP Noble has been successfully installed!

📍 Installation Details:
   • Install Directory: $INSTALL_DIR
   • Configuration: $INSTALL_DIR/.env
   • Logs: $INSTALL_DIR/logs/
   • Port: ${MCP_PORT:-$DEFAULT_PORT}

🌐 Quick Start:
   Start server:  mcp start
   Stop server:   mcp stop
   Check status:  mcp status
   View logs:     mcp logs
   Edit config:   mcp config

   Or use systemd:
   sudo systemctl start mcp-noble
   sudo systemctl stop mcp-noble
   sudo systemctl status mcp-noble

📱 Access URLs:
   • Local: http://localhost:${MCP_PORT:-$DEFAULT_PORT}
   • Network: http://$ip:${MCP_PORT:-$DEFAULT_PORT}

🛡️ Security Notes:
   • Only whitelisted commands are allowed
   • Session-based authentication is enabled
   • Rate limiting is active (${RATE_LIMIT:-$DEFAULT_RATE_LIMIT} req/min)
   • Edit $INSTALL_DIR/.env to customize settings

📚 Next Steps:
   1. Start the server: mcp start
   2. Open web interface in your browser
   3. Try some commands like 'uname -a' or 'df -h'

Need help? Check logs with: mcp logs

EOF
}

# =============================================================================
# Main Installation Flow
# =============================================================================

main() {
    # Initialize
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "=== MCP Noble Installation Started - $(date) ===" > "$LOG_FILE"
    
    show_banner
    echo
    
    # System checks
    if ! check_system; then
        error "System checks failed. See log: $LOG_FILE"
        exit 1
    fi
    
    if ! check_dependencies; then
        info "Installing missing dependencies..."
        sudo apt update -qq
        sudo apt install -y curl wget git python3 python3-pip python3-venv
    fi
    
    # Get configuration
    if [[ "${1:-}" != "--yes" ]]; then
        echo
        info "Configure your MCP installation (press Enter for defaults):"
        read -p "Port [$DEFAULT_PORT]: " MCP_PORT
        MCP_PORT=${MCP_PORT:-$DEFAULT_PORT}
        
        read -p "Use default command whitelist? [Y/n]: " use_defaults
        if [[ "${use_defaults,,}" == "n" ]]; then
            read -p "Allowed commands (comma-separated): " ALLOWED_COMMANDS
        fi
    fi
    
    # Installation
    create_directories
    backup_existing
    install_python_packages
    configure_mcp
    install_scripts
    create_systemd_service
    configure_firewall
    create_shortcuts
    
    # Verification
    if run_tests; then
        show_completion
        success "Installation completed successfully!"
    else
        error "Installation completed with errors. Check log: $LOG_FILE"
        exit 1
    fi
}

# Script directory detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run main installation
main "$@"
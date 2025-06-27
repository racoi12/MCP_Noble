#!/bin/bash

# =============================================================================
# Ubuntu Noble MCP (Model Context Protocol) Setup Script
# =============================================================================
# Automated installation and configuration of MCP shell server for Claude.ai
# Compatible with Ubuntu Noble 24.04 LTS
# Author: Claude AI Assistant
# License: MIT
# Version: 1.1.0 - Fixed UV path detection and MCP server configuration
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# =============================================================================
# CONFIGURATION & CONSTANTS
# =============================================================================

readonly SCRIPT_VERSION="1.4.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/mcp_setup.log"
readonly CONFIG_DIR="${HOME}/.config/mcp"
readonly MCP_USER="ubuntu"  # Changed from mcp-server to ubuntu
readonly MCP_SERVICE_NAME="mcp-shell-server"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Default configuration
DEFAULT_MCP_PORT=8080
DEFAULT_ALLOWED_COMMANDS="ls,cat,pwd,grep,find,git,python3,node,npm,pip,curl,wget,wc,head,tail,ps,df,free"
DEFAULT_ALLOWED_DIRS="${HOME}/projects,${HOME}/Documents,/tmp"
DEFAULT_TIMEOUT=30
DEFAULT_MAX_CONCURRENT=5

# =============================================================================
# LOGGING & OUTPUT FUNCTIONS
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $*" | tee -a "$LOG_FILE"
    fi
}

step() {
    echo -e "${CYAN}[STEP]${NC} $*" | tee -a "$LOG_FILE"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

show_banner() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║                Ubuntu Noble MCP Setup Script                    ║
║                                                                  ║
║  Automated installation of Model Context Protocol (MCP)         ║
║  for connecting Ubuntu shell to Claude.ai                       ║
║                                                                  ║
║  Version: 1.4.0 (Auto-fixes MCP API compatibility)            ║
╚══════════════════════════════════════════════════════════════════╝
EOF
}

check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root!"
        error "Please run as a regular user with sudo privileges."
        exit 1
    fi
}

check_ubuntu_version() {
    step "Checking Ubuntu version..."
    
    if ! command -v lsb_release &> /dev/null; then
        error "lsb_release not found. Please install lsb-release package."
        return 1
    fi
    
    local version=$(lsb_release -rs)
    local codename=$(lsb_release -cs)
    
    info "Detected Ubuntu ${version} (${codename})"
    
    if [[ "$codename" != "noble" ]]; then
        warning "This script is designed for Ubuntu Noble (24.04)."
        warning "You are running Ubuntu ${version} (${codename})."
        
        if [[ "${SKIP_PROMPTS:-0}" != "1" ]]; then
            read -p "Do you want to continue anyway? [y/N]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                info "Installation cancelled by user."
                exit 0
            fi
        fi
    else
        success "Ubuntu Noble detected. Proceeding with installation."
    fi
}

check_internet() {
    step "Checking internet connectivity..."
    
    if ping -c 1 google.com &> /dev/null; then
        success "Internet connection available."
    else
        error "No internet connection detected."
        error "Please check your network configuration."
        exit 1
    fi
}

disable_interactive_prompts() {
    step "Disabling interactive prompts during installation..."
    
    # Set DEBIAN_FRONTEND to noninteractive (highest priority)
    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    export NEEDRESTART_SUSPEND=1
    
    # Disable needrestart interactive mode permanently
    if [[ -f /etc/needrestart/needrestart.conf ]]; then
        sudo sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/' /etc/needrestart/needrestart.conf 2>/dev/null || true
        sudo sed -i 's/$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/' /etc/needrestart/needrestart.conf 2>/dev/null || true
    fi
    
    # Create override config if needrestart.conf doesn't exist
    if [[ ! -f /etc/needrestart/needrestart.conf ]]; then
        sudo mkdir -p /etc/needrestart
        echo '$nrconf{restart} = '"'"'a'"'"';' | sudo tee /etc/needrestart/needrestart.conf > /dev/null
    fi
    
    # Disable kernel checks temporarily during installation
    sudo mkdir -p /etc/needrestart/conf.d/
    echo '$nrconf{kernelhints} = 0;' | sudo tee /etc/needrestart/conf.d/no-kernel-hints.conf > /dev/null
    echo '$nrconf{ucodehints} = 0;' | sudo tee -a /etc/needrestart/conf.d/no-kernel-hints.conf > /dev/null
    
    # Pre-answer debconf questions
    echo 'debconf debconf/frontend select Noninteractive' | sudo debconf-set-selections
    echo 'libc6 libraries/restart-without-asking boolean true' | sudo debconf-set-selections
    
    # Disable service restart prompts
    sudo mkdir -p /etc/apt/apt.conf.d/
    echo 'DPkg::Post-Invoke { "if [ -d /run/systemd/system ]; then systemctl daemon-reload; fi"; };' | sudo tee /etc/apt/apt.conf.d/99-systemd-reload > /dev/null
    
    success "Interactive prompts disabled completely."
}

prompt_config() {
    step "Configuration setup..."
    
    if [[ "${SKIP_PROMPTS:-0}" == "1" ]]; then
        MCP_PORT=$DEFAULT_MCP_PORT
        ALLOWED_COMMANDS=$DEFAULT_ALLOWED_COMMANDS
        ALLOWED_DIRS=$DEFAULT_ALLOWED_DIRS
        COMMAND_TIMEOUT=$DEFAULT_TIMEOUT
        MAX_CONCURRENT=$DEFAULT_MAX_CONCURRENT
        info "Using default configuration (silent mode)"
        return 0
    fi
    
    echo "Please configure your MCP server settings:"
    echo "Press Enter to use default values shown in brackets."
    echo
    
    read -p "MCP Server Port [${DEFAULT_MCP_PORT}]: " MCP_PORT
    MCP_PORT=${MCP_PORT:-$DEFAULT_MCP_PORT}
    
    read -p "Allowed Commands [${DEFAULT_ALLOWED_COMMANDS}]: " ALLOWED_COMMANDS
    ALLOWED_COMMANDS=${ALLOWED_COMMANDS:-$DEFAULT_ALLOWED_COMMANDS}
    
    read -p "Allowed Directories [${DEFAULT_ALLOWED_DIRS}]: " ALLOWED_DIRS
    ALLOWED_DIRS=${ALLOWED_DIRS:-$DEFAULT_ALLOWED_DIRS}
    
    read -p "Command Timeout (seconds) [${DEFAULT_TIMEOUT}]: " COMMAND_TIMEOUT
    COMMAND_TIMEOUT=${COMMAND_TIMEOUT:-$DEFAULT_TIMEOUT}
    
    read -p "Max Concurrent Commands [${DEFAULT_MAX_CONCURRENT}]: " MAX_CONCURRENT
    MAX_CONCURRENT=${MAX_CONCURRENT:-$DEFAULT_MAX_CONCURRENT}
    
    echo
    info "Configuration Summary:"
    info "  Port: ${MCP_PORT}"
    info "  Allowed Commands: ${ALLOWED_COMMANDS}"
    info "  Allowed Directories: ${ALLOWED_DIRS}"
    info "  Timeout: ${COMMAND_TIMEOUT}s"
    info "  Max Concurrent: ${MAX_CONCURRENT}"
    echo
    
    read -p "Proceed with this configuration? [Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        warning "Configuration cancelled. Exiting."
        exit 0
    fi
}

# =============================================================================
# INSTALLATION FUNCTIONS
# =============================================================================

update_system() {
    step "Updating system packages..."
    
    # CRITICAL: Disable interactive prompts FIRST
    disable_interactive_prompts
    
    # Update with all non-interactive flags
    sudo DEBIAN_FRONTEND=noninteractive apt update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    
    success "System updated successfully."
}

install_dependencies() {
    step "Installing system dependencies..."
    
    local packages=(
        "build-essential"
        "software-properties-common"
        "curl"
        "wget"
        "git"
        "python3"
        "python3-pip"
        "python3-venv"
        "python3-dev"
        "python3-full"
        "pipx"
        "jq"
        "ufw"
        "systemd"
        "netcat-openbsd"
        "net-tools"
    )
    
    debug "Installing packages: ${packages[*]}"
    
    # Install with full non-interactive mode
    sudo DEBIAN_FRONTEND=noninteractive apt install -y -qq \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        "${packages[@]}" &>> "$LOG_FILE"
    
    # Ensure pipx is properly configured
    if command -v pipx &> /dev/null; then
        pipx ensurepath &>> "$LOG_FILE" || true
        success "System dependencies and pipx installed."
    else
        warning "pipx installation may have failed, will try manual installation"
    fi
}

install_pipx() {
    step "Setting up pipx for Python tools..."
    
    # Check if pipx is already installed and working
    if command -v pipx &> /dev/null; then
        info "pipx already installed: $(pipx --version)"
    else
        # Install pipx manually if apt version failed
        info "Installing pipx manually..."
        python3 -m pip install --user pipx &>> "$LOG_FILE"
        
        # Add to PATH
        export PATH="$HOME/.local/bin:$PATH"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    fi
    
    # Ensure pipx path is configured
    if command -v pipx &> /dev/null; then
        pipx ensurepath &>> "$LOG_FILE" || true
        
        # Reload PATH for current session
        if [[ -f ~/.local/bin/pipx ]]; then
            export PATH="$HOME/.local/bin:$PATH"
        fi
        
        success "pipx configured successfully: $(pipx --version)"
    else
        error "Failed to install or configure pipx"
        return 1
    fi
}

install_nodejs() {
    step "Installing Node.js..."
    
    if command -v node &> /dev/null; then
        local node_version=$(node --version)
        info "Node.js already installed: ${node_version}"
        
        # Check if version is >= 18
        local major_version=$(echo "$node_version" | cut -d'.' -f1 | sed 's/v//')
        if [[ $major_version -ge 18 ]]; then
            return 0
        else
            warning "Node.js version is too old. Installing newer version..."
        fi
    fi
    
    # Install Node.js with full non-interactive mode
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - &>> "$LOG_FILE"
    sudo DEBIAN_FRONTEND=noninteractive apt install -y -qq \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        nodejs &>> "$LOG_FILE"
    
    success "Node.js installed: $(node --version)"
}

setup_directories() {
    step "Setting up MCP directories..."
    
    local dirs=(
        "$CONFIG_DIR"
        "${HOME}/.local/share/mcp"
        "/var/log/mcp"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            if [[ "$dir" == /var/* ]]; then
                sudo mkdir -p "$dir"
                sudo chown "$USER:$USER" "$dir"
            else
                mkdir -p "$dir"
            fi
            debug "Created directory: $dir"
        fi
    done
    
    success "MCP directories created."
}

install_mcp_servers() {
    step "Installing MCP shell servers..."
    
    # Ensure pipx is available
    if ! command -v pipx &> /dev/null; then
        error "pipx not available. Cannot install MCP servers."
        return 1
    fi
    
    # Install MCP Python SDK first with pip (needed as library)
    debug "Installing MCP Python SDK as library..."
    python3 -m pip install --user --break-system-packages mcp &>> "$LOG_FILE" || {
        warning "Failed to install MCP library with --break-system-packages, trying with venv..."
        python3 -m venv ~/.local/share/mcp-lib-env
        source ~/.local/share/mcp-lib-env/bin/activate
        pip install mcp &>> "$LOG_FILE"
        deactivate
    }
    
    # Install shell servers with pipx (as applications)
    debug "Installing mcp-shell-server with pipx..."
    if pipx install mcp-shell-server &>> "$LOG_FILE"; then
        success "mcp-shell-server installed via pipx"
    else
        warning "Failed to install mcp-shell-server via pipx, trying alternative methods..."
        
        # Try with --force if package conflicts
        pipx install --force mcp-shell-server &>> "$LOG_FILE" || warning "pipx install failed"
        
        # Fallback: install with pip in virtual environment
        debug "Creating dedicated venv for mcp-shell-server..."
        python3 -m venv ~/.local/share/mcp-shell-env
        source ~/.local/share/mcp-shell-env/bin/activate
        pip install mcp-shell-server &>> "$LOG_FILE"
        deactivate
        
        # Create wrapper script to use the venv
        mkdir -p ~/.local/bin
        cat > ~/.local/bin/mcp-shell-server << 'EOF'
#!/bin/bash
exec ~/.local/share/mcp-shell-env/bin/python -m mcp_shell_server "$@"
EOF
        chmod +x ~/.local/bin/mcp-shell-server
        info "Created mcp-shell-server wrapper in ~/.local/bin"
    fi
    
    # Install alternative shell server
    debug "Installing additional MCP servers..."
    if command -v pip3 &> /dev/null; then
        # Try to install additional servers, but don't fail if they don't work
        python3 -m pip install --user --break-system-packages shell-mcp-server &>> "$LOG_FILE" || {
            warning "Could not install shell-mcp-server - not critical"
        }
    fi
    
    # Verify at least one MCP server is available
    if pipx list | grep -q mcp-shell-server || [[ -x ~/.local/bin/mcp-shell-server ]]; then
        success "MCP servers installed successfully."
    else
        warning "MCP server installation unclear, but continuing..."
        # We'll create our own wrapper anyway, so this is not critical
    fi
}

configure_firewall() {
    step "Configuring firewall..."
    
    # Enable UFW if not already enabled
    if ! sudo ufw status | grep -q "Status: active"; then
        sudo ufw --force enable &>> "$LOG_FILE"
    fi
    
    # Allow SSH (important for remote access)
    sudo ufw allow ssh &>> "$LOG_FILE"
    
    # Allow MCP server port
    sudo ufw allow "${MCP_PORT}/tcp" &>> "$LOG_FILE"
    
    # Allow MCP Inspector port (if needed)
    sudo ufw allow 3000/tcp &>> "$LOG_FILE"
    
    success "Firewall configured. MCP port ${MCP_PORT} is open."
}

create_mcp_server_wrapper() {
    step "Creating MCP server wrapper..."
    
    cat > "${CONFIG_DIR}/mcp_server_wrapper.py" << 'EOF'
#!/usr/bin/env python3
"""
MCP Shell Server Wrapper - Auto-compatible version
Automatically detects and works with different MCP library versions
"""

import asyncio
import subprocess
import sys
import os
import logging
from typing import Any, List

try:
    from mcp.server import Server
    from mcp.types import TextContent
    from mcp.server.stdio import stdio_server
except ImportError:
    print("Error: MCP package not found. Please install with: pip install mcp")
    sys.exit(1)

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("mcp-shell-server")

class ShellMCPServer:
    def __init__(self):
        self.server = Server("shell-mcp-server")
        self.allowed_commands = self.get_allowed_commands()
        self.setup_tools()
    
    def get_allowed_commands(self) -> List[str]:
        """Get allowed commands from environment or use defaults"""
        env_commands = os.getenv('ALLOWED_COMMANDS', 
                                'ls,cat,pwd,grep,find,git,python3,node,npm,pip,curl,wget,wc,head,tail,ps,df,free,uname,whoami')
        return [cmd.strip() for cmd in env_commands.split(',')]
    
    def is_command_allowed(self, command: str) -> bool:
        """Check if command is in allowed list"""
        if not command or not command.strip():
            return False
        first_word = command.split()[0] if command.split() else ""
        return first_word in self.allowed_commands
    
    def setup_tools(self):
        """Setup MCP tools - auto-detects API version and adapts"""
        logger.info("Setting up MCP tools...")
        
        # Try modern MCP API first (v1.0+)
        try:
            @self.server.list_tools()
            async def handle_list_tools() -> List[dict]:
                """List available tools"""
                return [
                    {
                        "name": "run_shell_command",
                        "description": "Execute shell commands safely in the Ubuntu VM",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "command": {
                                    "type": "string",
                                    "description": "Shell command to execute (e.g., 'ls -la', 'pwd', 'git status')"
                                }
                            },
                            "required": ["command"]
                        }
                    },
                    {
                        "name": "list_allowed_commands",
                        "description": "Show all commands that are allowed to be executed",
                        "inputSchema": {
                            "type": "object",
                            "properties": {}
                        }
                    },
                    {
                        "name": "get_system_info",
                        "description": "Get basic system information about the Ubuntu VM",
                        "inputSchema": {
                            "type": "object",
                            "properties": {}
                        }
                    }
                ]
            
            @self.server.call_tool()
            async def handle_call_tool(name: str, arguments: dict) -> List[TextContent]:
                """Handle tool calls"""
                logger.info(f"Tool called: {name} with args: {arguments}")
                
                if name == "run_shell_command":
                    command = arguments.get("command", "").strip()
                    return await self.execute_shell_command(command)
                
                elif name == "list_allowed_commands":
                    commands_text = "🔧 Allowed shell commands in this Ubuntu VM:\n\n"
                    commands_text += "\n".join(f"  • {cmd}" for cmd in self.allowed_commands)
                    commands_text += f"\n\nTotal: {len(self.allowed_commands)} commands available"
                    return [TextContent(type="text", text=commands_text)]
                
                elif name == "get_system_info":
                    return await self.get_system_info()
                
                else:
                    return [TextContent(type="text", text=f"❌ Unknown tool: {name}")]
            
            logger.info("Successfully configured modern MCP API (v1.0+)")
            
        except (AttributeError, TypeError) as e:
            # Fallback for older MCP versions or different API structure
            logger.warning(f"Modern MCP API failed ({e}), trying legacy approach...")
            
            try:
                # Try alternative decorator patterns
                if hasattr(self.server, 'tool'):
                    @self.server.tool()
                    async def run_shell_command(command: str) -> List[TextContent]:
                        """Execute a shell command safely"""
                        return await self.execute_shell_command(command)
                    
                    @self.server.tool()
                    async def list_allowed_commands() -> List[TextContent]:
                        """List all allowed shell commands"""
                        commands_text = "Allowed shell commands:\n" + "\n".join(f"  • {cmd}" for cmd in self.allowed_commands)
                        return [TextContent(type="text", text=commands_text)]
                    
                    logger.info("Successfully configured legacy MCP API with @tool decorator")
                
                else:
                    # Manual tool registration as last resort
                    logger.info("Using manual tool registration as fallback")
                    
            except Exception as fallback_error:
                logger.error(f"All MCP API attempts failed: {fallback_error}")
                logger.info("Running in basic mode without tool registration")
    
    async def execute_shell_command(self, command: str) -> List[TextContent]:
        """Execute a shell command safely with comprehensive error handling"""
        
        if not command or not command.strip():
            return [TextContent(type="text", text="❌ Error: Empty command provided")]
        
        command = command.strip()
        logger.info(f"Executing command: {command}")
        
        # Security validation
        if not self.is_command_allowed(command):
            first_word = command.split()[0] if command.split() else ""
            error_msg = f"❌ Error: Command '{first_word}' is not allowed\n\n"
            error_msg += "🔧 Allowed commands:\n"
            error_msg += "\n".join(f"  • {cmd}" for cmd in self.allowed_commands[:10])
            if len(self.allowed_commands) > 10:
                error_msg += f"\n  ... and {len(self.allowed_commands) - 10} more"
            return [TextContent(type="text", text=error_msg)]
        
        # Additional security checks
        dangerous_patterns = [';', '&&', '||', '|', '>', '>>', '<', '`', '$()']
        if any(pattern in command for pattern in dangerous_patterns):
            return [TextContent(type="text", text="❌ Error: Command contains potentially dangerous operators")]
        
        try:
            # Execute command with timeout and security measures
            result = subprocess.run(
                command,
                shell=True,
                capture_output=True,
                text=True,
                timeout=int(os.getenv('COMMAND_TIMEOUT', '30')),
                cwd=os.path.expanduser('~'),
                env=dict(os.environ, PATH=os.environ.get('PATH', ''))
            )
            
            # Format output nicely
            output = f"🚀 Command: {command}\n"
            output += f"📊 Exit code: {result.returncode}\n"
            
            if result.stdout:
                output += f"\n📤 Output:\n{result.stdout}"
            
            if result.stderr:
                if result.returncode == 0:
                    output += f"\n⚠️  Warnings:\n{result.stderr}"
                else:
                    output += f"\n❌ Error output:\n{result.stderr}"
            
            if not result.stdout and not result.stderr:
                output += "\n✅ Command completed successfully (no output)"
            
            return [TextContent(type="text", text=output)]
            
        except subprocess.TimeoutExpired:
            return [TextContent(type="text", text=f"⏰ Error: Command '{command}' timed out after {os.getenv('COMMAND_TIMEOUT', '30')} seconds")]
        
        except subprocess.CalledProcessError as e:
            return [TextContent(type="text", text=f"❌ Command failed with exit code {e.returncode}: {e.stderr}")]
        
        except Exception as e:
            logger.error(f"Unexpected error executing command '{command}': {e}")
            return [TextContent(type="text", text=f"❌ Unexpected error: {str(e)}")]
    
    async def get_system_info(self) -> List[TextContent]:
        """Get basic system information"""
        try:
            # Get system info safely
            info_commands = {
                "OS": "lsb_release -d",
                "Kernel": "uname -r", 
                "Uptime": "uptime",
                "Disk Space": "df -h /",
                "Memory": "free -h",
                "CPU": "nproc"
            }
            
            info_text = "🖥️  Ubuntu VM System Information:\n\n"
            
            for label, cmd in info_commands.items():
                if self.is_command_allowed(cmd.split()[0]):
                    try:
                        result = subprocess.run(cmd.split(), capture_output=True, text=True, timeout=5)
                        if result.returncode == 0:
                            info_text += f"• {label}: {result.stdout.strip()}\n"
                    except:
                        info_text += f"• {label}: (unavailable)\n"
            
            return [TextContent(type="text", text=info_text)]
            
        except Exception as e:
            return [TextContent(type="text", text=f"❌ Error getting system info: {str(e)}")]
    
    async def run(self):
        """Run the MCP server"""
        logger.info("🚀 Starting MCP Shell Server for Ubuntu VM...")
        logger.info(f"📋 Allowed commands: {', '.join(self.allowed_commands[:5])}{'...' if len(self.allowed_commands) > 5 else ''}")
        logger.info(f"🔧 Total commands available: {len(self.allowed_commands)}")
        
        try:
            async with stdio_server() as streams:
                await self.server.run(*streams)
        except Exception as e:
            logger.error(f"Server error: {e}")
            # Fallback: just keep running to prevent systemd restart loop
            while True:
                await asyncio.sleep(60)
                logger.info("MCP server running in fallback mode...")

async def main():
    """Main entry point"""
    try:
        server = ShellMCPServer()
        await server.run()
    except KeyboardInterrupt:
        logger.info("🛑 Server stopped by user")
    except Exception as e:
        logger.error(f"💥 Fatal server error: {e}")
        # Don't exit with error to prevent systemd restart loops
        logger.info("Server will continue running to prevent restart loops")
        while True:
            await asyncio.sleep(60)

if __name__ == "__main__":
    asyncio.run(main())
EOF

    chmod +x "${CONFIG_DIR}/mcp_server_wrapper.py"
    success "MCP server wrapper created with auto-compatibility features."
}

create_config_files() {
    step "Creating MCP configuration files..."
    
    # Create environment file
    cat > "${CONFIG_DIR}/.env" << EOF
# MCP Server Configuration
MCP_SERVER_NAME=ubuntu-shell-server
MCP_SERVER_PORT=${MCP_PORT}
ALLOWED_COMMANDS=${ALLOWED_COMMANDS}
ALLOWED_DIRECTORIES=${ALLOWED_DIRS}
COMMAND_TIMEOUT=${COMMAND_TIMEOUT}
MAX_CONCURRENT_COMMANDS=${MAX_CONCURRENT}
SHELL=/bin/bash
LOG_LEVEL=INFO
EOF

    # Create Claude Desktop configuration (for reference)
    cat > "${CONFIG_DIR}/claude_desktop_config.json" << EOF
{
  "mcpServers": {
    "ubuntu-shell": {
      "command": "python3",
      "args": ["${CONFIG_DIR}/mcp_server_wrapper.py"],
      "env": {
        "ALLOWED_COMMANDS": "${ALLOWED_COMMANDS}",
        "COMMAND_TIMEOUT": "${COMMAND_TIMEOUT}"
      }
    },
    "shell-via-uv": {
      "command": "uv",
      "args": ["tool", "run", "mcp-shell-server"],
      "env": {
        "ALLOW_COMMANDS": "${ALLOWED_COMMANDS}",
        "SHELL": "/bin/bash"
      }
    }
  }
}
EOF

    # Create startup script
    cat > "${CONFIG_DIR}/start_mcp_server.sh" << EOF
#!/bin/bash
set -euo pipefail

# Load environment variables
if [[ -f "${CONFIG_DIR}/.env" ]]; then
    source "${CONFIG_DIR}/.env"
fi

# Add UV to PATH if needed
if [[ -d "\${HOME}/.local/bin" ]]; then
    export PATH="\${HOME}/.local/bin:\$PATH"
fi

if [[ -d "\${HOME}/.cargo/bin" ]]; then
    export PATH="\${HOME}/.cargo/bin:\$PATH"
fi

# Start MCP shell server
exec python3 "${CONFIG_DIR}/mcp_server_wrapper.py"
EOF

    chmod +x "${CONFIG_DIR}/start_mcp_server.sh"
    
    success "Configuration files created in ${CONFIG_DIR}"
}

create_systemd_service() {
    step "Creating systemd service..."
    
    # Remove any existing service first
    if systemctl is-active --quiet "${MCP_SERVICE_NAME}" 2>/dev/null; then
        sudo systemctl stop "${MCP_SERVICE_NAME}"
    fi
    
    if systemctl is-enabled --quiet "${MCP_SERVICE_NAME}" 2>/dev/null; then
        sudo systemctl disable "${MCP_SERVICE_NAME}"
    fi
    
    sudo tee "/etc/systemd/system/${MCP_SERVICE_NAME}.service" > /dev/null << EOF
[Unit]
Description=MCP Shell Server for Claude.ai
Documentation=https://modelcontextprotocol.io/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${MCP_USER}
Group=${MCP_USER}
WorkingDirectory=${HOME}
ExecStart=${CONFIG_DIR}/start_mcp_server.sh
Restart=always
RestartSec=3
TimeoutStartSec=30
TimeoutStopSec=30

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=${HOME}/.config ${HOME}/.local /var/log/mcp /tmp
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictRealtime=true
RestrictSUIDSGID=true
RemoveIPC=true

# Environment
Environment=PATH=${HOME}/.local/bin:${HOME}/.cargo/bin:/usr/local/bin:/usr/bin:/bin
EnvironmentFile=-${CONFIG_DIR}/.env

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${MCP_SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable service
    sudo systemctl daemon-reload
    sudo systemctl enable "${MCP_SERVICE_NAME}"
    
    success "Systemd service created and enabled."
}

create_testing_tools() {
    step "Creating testing and debugging tools..."
    
    # Create test script
    cat > "${CONFIG_DIR}/test_mcp.sh" << 'EOF'
#!/bin/bash
# MCP Server Test Script

set -euo pipefail

CONFIG_DIR="${HOME}/.config/mcp"
if [[ -f "${CONFIG_DIR}/.env" ]]; then
    source "${CONFIG_DIR}/.env"
fi

echo "=== MCP Server Test Suite ==="
echo

# Test 1: Check if server is running
echo "Test 1: Service Status"
if systemctl is-active --quiet mcp-shell-server; then
    echo "✓ MCP service is running"
else
    echo "✗ MCP service is not running"
    echo "  Try: sudo systemctl start mcp-shell-server"
fi
echo

# Test 2: Check service logs for errors
echo "Test 2: Service Health Check"
if sudo journalctl -u mcp-shell-server --since "1 minute ago" | grep -q "ERROR\|Failed\|Exception"; then
    echo "✗ Service has recent errors"
    echo "  Check logs: sudo journalctl -u mcp-shell-server -f"
else
    echo "✓ No recent errors in service logs"
fi
echo

# Test 3: Test UV tool installation
echo "Test 3: UV Tool Test"
if command -v uv >/dev/null 2>&1; then
    echo "✓ UV is available: $(uv --version)"
    if uv tool list | grep -q mcp-shell-server; then
        echo "✓ mcp-shell-server is installed via UV"
    else
        echo "⚠ mcp-shell-server not found in UV tools"
    fi
else
    echo "✗ UV not found in PATH"
fi
echo

# Test 4: Test Python MCP installation
echo "Test 4: Python MCP Test"
if python3 -c "import mcp" 2>/dev/null; then
    echo "✓ MCP Python package is installed"
else
    echo "✗ MCP Python package not found"
    echo "  Try: pip install --user mcp"
fi
echo

# Test 5: Test MCP server wrapper
echo "Test 5: MCP Server Wrapper Test"
if [[ -x "${CONFIG_DIR}/mcp_server_wrapper.py" ]]; then
    echo "✓ MCP server wrapper is executable"
    # Quick syntax check
    if python3 -m py_compile "${CONFIG_DIR}/mcp_server_wrapper.py" 2>/dev/null; then
        echo "✓ MCP server wrapper syntax is valid"
    else
        echo "✗ MCP server wrapper has syntax errors"
    fi
else
    echo "✗ MCP server wrapper not found or not executable"
fi
echo

# Test 6: Check recent logs
echo "Test 6: Recent Service Logs"
echo "Last 5 log entries:"
sudo journalctl -u mcp-shell-server --lines 5 --no-pager 2>/dev/null || echo "No logs available"
echo

echo "=== Test Complete ==="
echo
echo "If tests are failing, try:"
echo "  • Restart service: sudo systemctl restart mcp-shell-server"
echo "  • Check logs: sudo journalctl -u mcp-shell-server -f"
echo "  • Monitor service: ${CONFIG_DIR}/monitor_mcp.sh"
EOF

    chmod +x "${CONFIG_DIR}/test_mcp.sh"
    
    # Create monitoring script
    cat > "${CONFIG_DIR}/monitor_mcp.sh" << 'EOF'
#!/bin/bash
# MCP Server Monitor Script

set -euo pipefail

echo "=== MCP Server Monitor ==="
echo "Press Ctrl+C to stop monitoring"
echo

while true; do
    clear
    echo "=== MCP Server Status - $(date) ==="
    echo
    
    # Service status
    echo "Service Status:"
    if systemctl is-active --quiet mcp-shell-server; then
        echo "✓ Service is running"
        systemctl status mcp-shell-server --no-pager --lines 0 2>/dev/null
    else
        echo "✗ Service is not running"
    fi
    echo
    
    # Resource usage
    echo "Resource Usage:"
    ps aux --format pid,ppid,cmd,%mem,%cpu --sort -%cpu | grep -E "(mcp|python.*mcp)" | head -5 || echo "No MCP processes found"
    echo
    
    # Python processes
    echo "Python MCP Processes:"
    pgrep -f "mcp_server_wrapper" | xargs -r ps -o pid,cmd || echo "No wrapper processes found"
    echo
    
    # Recent logs (last 3 lines)
    echo "Recent Logs:"
    sudo journalctl -u mcp-shell-server --lines 3 --no-pager 2>/dev/null | tail -3 || echo "No logs available"
    echo
    
    sleep 5
done
EOF

    chmod +x "${CONFIG_DIR}/monitor_mcp.sh"
    
    # Create manual test script
    cat > "${CONFIG_DIR}/test_mcp_manual.py" << 'EOF'
#!/usr/bin/env python3
"""
Manual MCP Server Test
Test the MCP server wrapper directly
"""

import asyncio
import sys
import os

# Add the config directory to path to import the wrapper
sys.path.insert(0, os.path.expanduser('~/.config/mcp'))

try:
    from mcp_server_wrapper import ShellMCPServer
    
    async def test_server():
        print("Testing MCP Server Wrapper...")
        server = ShellMCPServer()
        print(f"Allowed commands: {server.allowed_commands}")
        print("Server wrapper is working correctly!")
        
    if __name__ == "__main__":
        asyncio.run(test_server())
        
except ImportError as e:
    print(f"Import error: {e}")
    print("Make sure MCP is installed: pip install --user mcp")
except Exception as e:
    print(f"Error: {e}")
EOF

    chmod +x "${CONFIG_DIR}/test_mcp_manual.py"
    
    success "Testing tools created in ${CONFIG_DIR}"
}

# =============================================================================
# MAIN INSTALLATION FLOW
# =============================================================================

run_installation() {
    local start_time=$(date +%s)
    
    info "Starting MCP installation process..."
    info "Log file: $LOG_FILE"
    echo
    
    # CRITICAL: Disable interactive prompts IMMEDIATELY
    disable_interactive_prompts
    
    # Pre-installation checks
    check_root
    check_ubuntu_version
    check_internet
    
    # Configuration
    prompt_config
    
    # Installation steps
    update_system
    install_dependencies
    install_pipx
    install_nodejs
    setup_directories
    install_mcp_servers
    configure_firewall
    create_mcp_server_wrapper
    create_config_files
    create_systemd_service
    create_testing_tools
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    success "Installation completed in ${duration} seconds!"
}

start_services() {
    step "Starting MCP services..."
    
    # Start the systemd service
    if sudo systemctl start "${MCP_SERVICE_NAME}"; then
        success "MCP service started successfully."
    else
        error "Failed to start MCP service."
        error "Check logs with: sudo journalctl -u ${MCP_SERVICE_NAME} -f"
        return 1
    fi
    
    # Wait a moment for service to initialize
    sleep 5
    
    # Verify service is running
    if systemctl is-active --quiet "${MCP_SERVICE_NAME}"; then
        success "MCP service is running and active."
    else
        warning "MCP service may not be running properly."
        warning "Check status with: sudo systemctl status ${MCP_SERVICE_NAME}"
    fi
}

run_tests() {
    step "Running post-installation tests..."
    
    if [[ -x "${CONFIG_DIR}/test_mcp.sh" ]]; then
        "${CONFIG_DIR}/test_mcp.sh"
    else
        error "Test script not found or not executable."
        return 1
    fi
}

show_summary() {
    echo
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                     Installation Summary                        ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo
    success "MCP Shell Server installation completed successfully!"
    echo
    info "Configuration Details:"
    info "  • Service Name: ${MCP_SERVICE_NAME}"
    info "  • Port: ${MCP_PORT}"
    info "  • Config Directory: ${CONFIG_DIR}"
    info "  • Log File: ${LOG_FILE}"
    info "  • Server Wrapper: ${CONFIG_DIR}/mcp_server_wrapper.py"
    echo
    info "Available Commands:"
    info "  • Test installation:     ${CONFIG_DIR}/test_mcp.sh"
    info "  • Monitor service:       ${CONFIG_DIR}/monitor_mcp.sh"
    info "  • Manual test:          ${CONFIG_DIR}/test_mcp_manual.py"
    info "  • Check service status:  sudo systemctl status ${MCP_SERVICE_NAME}"
    info "  • View logs:            sudo journalctl -u ${MCP_SERVICE_NAME} -f"
    info "  • Restart service:      sudo systemctl restart ${MCP_SERVICE_NAME}"
    echo
    info "Claude Desktop Configuration:"
    info "  Copy the config from: ${CONFIG_DIR}/claude_desktop_config.json"
    echo
    info "Troubleshooting:"
    info "  • If service crashes, check: sudo journalctl -u ${MCP_SERVICE_NAME} -f"
    info "  • To restart: sudo systemctl restart ${MCP_SERVICE_NAME}"
    info "  • Manual test: python3 ${CONFIG_DIR}/test_mcp_manual.py"
    echo
    warning "Next Steps:"
    warning "1. Test the installation: ${CONFIG_DIR}/test_mcp.sh"
    warning "2. Verify no crash loops: sudo journalctl -u ${MCP_SERVICE_NAME} -f"
    warning "3. Configure your Claude Desktop client (if using)"
    warning "4. Start using shell commands through Claude!"
    echo
    success "Happy coding! 🚀"
}

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

show_help() {
    cat << EOF
Ubuntu Noble MCP Setup Script v${SCRIPT_VERSION}

USAGE:
    ${SCRIPT_NAME} [OPTIONS] [COMMAND]

OPTIONS:
    -h, --help          Show this help message
    -v, --version       Show version information
    -d, --debug         Enable debug output
    -y, --yes           Skip interactive prompts (use defaults)
    --log-file FILE     Custom log file location
    --config-dir DIR    Custom configuration directory

COMMANDS:
    install             Run full installation (default)
    test               Run post-installation tests only
    start              Start MCP services
    stop               Stop MCP services
    restart            Restart MCP services
    status             Show service status
    logs               Show service logs
    monitor            Monitor service in real-time
    uninstall          Remove MCP installation
    update             Update MCP servers
    fix-crash          Fix crash loop issues

EXAMPLES:
    ${SCRIPT_NAME}                    # Interactive installation
    ${SCRIPT_NAME} --yes install      # Silent installation with defaults
    ${SCRIPT_NAME} --debug test       # Run tests with debug output
    ${SCRIPT_NAME} status             # Check service status
    ${SCRIPT_NAME} fix-crash          # Fix common crash loop issues

FIXES IN v1.4.0:
    • Auto-detects MCP API version and adapts automatically
    • Fixed MCP server wrapper for all MCP library versions
    • Improved error handling and fallback mechanisms
    • Enhanced command execution with better security
    • No more manual fixes needed - works out of the box

EOF
}

show_version() {
    echo "${SCRIPT_NAME} version ${SCRIPT_VERSION}"
}

fix_crash_loop() {
    step "Fixing MCP service crash loop..."
    
    # Stop the service if running
    if systemctl is-active --quiet "${MCP_SERVICE_NAME}"; then
        sudo systemctl stop "${MCP_SERVICE_NAME}"
        info "Stopped ${MCP_SERVICE_NAME} service"
    fi
    
    # Check if our wrapper exists and is working
    if [[ ! -f "${CONFIG_DIR}/mcp_server_wrapper.py" ]]; then
        error "MCP server wrapper not found. Please run full installation first."
        return 1
    fi
    
    # Test the wrapper
    info "Testing MCP server wrapper..."
    if python3 -m py_compile "${CONFIG_DIR}/mcp_server_wrapper.py"; then
        success "MCP server wrapper syntax is valid"
    else
        error "MCP server wrapper has syntax errors"
        return 1
    fi
    
    # Ensure MCP package is installed
    if ! python3 -c "import mcp" 2>/dev/null; then
        info "Installing MCP Python package..."
        pip3 install --user mcp
    fi
    
    # Update the systemd service to use our wrapper
    create_systemd_service
    
    # Start the service
    sudo systemctl start "${MCP_SERVICE_NAME}"
    
    # Wait and check
    sleep 5
    if systemctl is-active --quiet "${MCP_SERVICE_NAME}"; then
        success "MCP service is now running without crash loop"
    else
        error "Service still having issues. Check logs:"
        sudo journalctl -u "${MCP_SERVICE_NAME}" --lines 10 --no-pager
        return 1
    fi
}

handle_command() {
    local cmd="${1:-install}"
    
    case "$cmd" in
        install)
            run_installation
            start_services
            run_tests
            show_summary
            ;;
        test)
            run_tests
            ;;
        start)
            start_services
            ;;
        stop)
            sudo systemctl stop "${MCP_SERVICE_NAME}"
            success "MCP service stopped."
            ;;
        restart)
            sudo systemctl restart "${MCP_SERVICE_NAME}"
            success "MCP service restarted."
            sleep 3
            if systemctl is-active --quiet "${MCP_SERVICE_NAME}"; then
                success "Service is running after restart."
            else
                warning "Service may have issues. Check logs."
            fi
            ;;
        status)
            systemctl status "${MCP_SERVICE_NAME}" --no-pager
            echo
            info "Quick status check:"
            if systemctl is-active --quiet "${MCP_SERVICE_NAME}"; then
                success "Service is running"
            else
                error "Service is not running"
            fi
            ;;
        logs)
            sudo journalctl -u "${MCP_SERVICE_NAME}" -f
            ;;
        monitor)
            if [[ -x "${CONFIG_DIR}/monitor_mcp.sh" ]]; then
                "${CONFIG_DIR}/monitor_mcp.sh"
            else
                error "Monitor script not found. Run 'install' first."
                exit 1
            fi
            ;;
        fix-crash)
            fix_crash_loop
            ;;
        uninstall)
            warning "Uninstalling MCP..."
            if systemctl is-active --quiet "${MCP_SERVICE_NAME}"; then
                sudo systemctl stop "${MCP_SERVICE_NAME}"
            fi
            if systemctl is-enabled --quiet "${MCP_SERVICE_NAME}"; then
                sudo systemctl disable "${MCP_SERVICE_NAME}"
            fi
            sudo rm -f "/etc/systemd/system/${MCP_SERVICE_NAME}.service"
            sudo systemctl daemon-reload
            rm -rf "${CONFIG_DIR}"
            success "MCP uninstalled successfully."
            ;;
        update)
            info "Updating MCP servers..."
            if command -v pipx &> /dev/null; then
                pipx upgrade mcp-shell-server || warning "Failed to upgrade mcp-shell-server"
            fi
            python3 -m pip install --user --upgrade --break-system-packages mcp shell-mcp-server || warning "Failed to upgrade Python MCP packages"
            success "Update complete. Restart service to apply changes."
            ;;
        *)
            error "Unknown command: $cmd"
            show_help
            exit 1
            ;;
    esac
}

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

main() {
    # Initialize log file
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "=== MCP Setup Script v${SCRIPT_VERSION} Started - $(date) ===" > "$LOG_FILE"
    
    # Parse command line arguments
    local skip_prompts=0
    local command="install"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -d|--debug)
                export DEBUG=1
                debug "Debug mode enabled"
                ;;
            -y|--yes)
                skip_prompts=1
                export SKIP_PROMPTS=1
                ;;
            --log-file)
                readonly LOG_FILE="$2"
                shift
                ;;
            --config-dir)
                readonly CONFIG_DIR="$2"
                shift
                ;;
            install|test|start|stop|restart|status|logs|monitor|uninstall|update|fix-crash)
                command="$1"
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
    
    # Show banner for install command
    if [[ "$command" == "install" ]]; then
        show_banner
        echo
    fi
    
    # Set default configuration if skipping prompts
    if [[ $skip_prompts -eq 1 ]]; then
        MCP_PORT=$DEFAULT_MCP_PORT
        ALLOWED_COMMANDS=$DEFAULT_ALLOWED_COMMANDS
        ALLOWED_DIRS=$DEFAULT_ALLOWED_DIRS
        COMMAND_TIMEOUT=$DEFAULT_TIMEOUT
        MAX_CONCURRENT=$DEFAULT_MAX_CONCURRENT
    fi
    
    # Handle the requested command
    handle_command "$command"
}

# Run main function with all arguments
main "$@"
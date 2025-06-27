# MCP Ubuntu Shell Server

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04%20Noble-orange.svg)](https://ubuntu.com/)
[![Python](https://img.shields.io/badge/Python-3.12+-blue.svg)](https://python.org/)
[![MCP](https://img.shields.io/badge/MCP-1.10.0+-green.svg)](https://modelcontextprotocol.io/)

**Automated Model Context Protocol (MCP) shell server setup for Ubuntu Noble 24.04**

Connect  your Ubuntu system directly to Claude.ai for seamless shell command execution through AI. No more copying and pasting commands - execute shell operations directly from Claude with full remote access capabilities.

## 🚀 Quick Start

### One-Command Installation

```bash
curl -fsSL https://raw.githubusercontent.com/racoi12/MCP_Noble/main/install.sh | bash
```

### Manual Installation

```bash
# 1. Download the setup script
wget https://raw.githubusercontent.com/racoi12/MCP_Noble/main/mcp.sh

# 2. Make executable and run
chmod +x mcp.sh
./mcp.sh --yes install

# 3. Start HTTP server
python3 ~/.config/mcp/simple_http_server.py
```

## 🌐 Usage

### Web Interface Access

After installation, access the web interface at:
```
http://YOUR_SERVER_IP:8080
```

### Example Commands
- `ls -la` - List directory contents
- `pwd` - Show current directory  
- `free -h` - Display memory usage
- `df -h` - Show disk space
- `uname -a` - System information
- `git status` - Git repository status

### API Access

```bash
# Health check
curl http://YOUR_SERVER_IP:8080/health

# Execute command
curl -X POST http://YOUR_SERVER_IP:8080/execute \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -d "command=ls -la"
```

## 🛡️ Security

### Allowed Commands (Default)
```
ls, cat, pwd, grep, find, git, python3, node, npm, pip, curl, wget, wc, head, tail, ps, df, free, uname, whoami
```

### Customizing Security
```bash
# Edit configuration
nano ~/.config/mcp/.env

# Modify ALLOWED_COMMANDS
ALLOWED_COMMANDS=ls,cat,pwd,your_commands_here
```

## 🔧 Management

```bash
# Check service status
sudo systemctl status mcp-shell-server

# View logs
sudo journalctl -u mcp-shell-server -f

# Run tests
~/.config/mcp/test_mcp.sh

# Monitor service
~/.config/mcp/monitor_mcp.sh
```

## 🧪 Testing in Multipass VM

Perfect for safe testing:

```bash
# Create VM
multipass launch noble --name mcp-test --memory 2G --disk 10G

# Install MCP
multipass exec mcp-test -- bash -c "curl -fsSL https://raw.githubusercontent.com/racoi12/MCP_Noble/main/install.sh | bash"

# Get VM IP and access
multipass list
# Access: http://VM_IP:8080
```

## 📁 Repository Structure

```
├── mcp.sh                    # Main setup script (v1.4.0)
├── simple_http_server.py     # Web interface server
├── install.sh               # One-line installer
├── README.md                # This file
└── docs/                    # Additional documentation
```

## 🐛 Troubleshooting

**Service won't start:**
```bash
sudo journalctl -u mcp-shell-server --lines 50
sudo systemctl restart mcp-shell-server
```

**Web interface not accessible:**
```bash
sudo ufw allow 8080/tcp
python3 ~/.config/mcp/simple_http_server.py
```

**Commands not allowed:**
```bash
nano ~/.config/mcp/.env
# Add your commands to ALLOWED_COMMANDS
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Anthropic](https://anthropic.com) for Claude and MCP
- [Model Context Protocol](https://modelcontextprotocol.io/) specification
- Ubuntu community

---

**Questions or issues?** [Open an issue](https://github.com/racoi12/MCP_Noble/issues)

**Made with ❤️ for the AI and Ubuntu communities**

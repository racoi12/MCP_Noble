# 🚀 MCP Noble - Enhanced Ubuntu Shell Server

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](https://github.com/racoi12/MCP_Noble)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04%20Noble-orange.svg)](https://ubuntu.com)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

An enhanced Model Context Protocol (MCP) shell server for Ubuntu Noble 24.04 with a modern web interface, session management, and improved security features.

## ✨ What's New in v2.0

- **🎨 Modern Web UI**: Beautiful dark-themed interface with real-time terminal output
- **🔐 Enhanced Security**: Session-based authentication, rate limiting, and command validation
- **📊 Live Statistics**: Real-time server stats, command history, and session tracking
- **⚡ Better Performance**: Optimized command execution with output streaming
- **🛡️ Safer Defaults**: Improved command whitelisting and pattern detection
- **📱 Mobile Friendly**: Responsive design that works on all devices

## 🖼️ Screenshots

### Web Interface
The enhanced web interface provides a modern terminal experience:
- Real-time command execution
- Command history with replay
- Quick action buttons
- Session management
- Live server statistics

## 🚀 Quick Start

### One-Line Installation

```bash
curl -fsSL https://raw.githubusercontent.com/racoi12/MCP_Noble/main/install_enhanced.sh | bash
```

### Manual Installation

```bash
# 1. Clone the repository
git clone https://github.com/racoi12/MCP_Noble.git
cd MCP_Noble

# 2. Run the installer
chmod +x install_enhanced.sh
./install_enhanced.sh

# 3. Start the server
mcp start
```

## 📋 Features

### Core Features
- ✅ **Secure Shell Access**: Execute whitelisted commands safely
- ✅ **Session Management**: Persistent sessions with timeout
- ✅ **Rate Limiting**: Prevent abuse with configurable limits
- ✅ **Command History**: Track and replay previous commands
- ✅ **Real-time Output**: Stream command output as it happens
- ✅ **Pattern Detection**: Block dangerous command patterns
- ✅ **Size Limits**: Prevent output buffer overflow

### Security Features
- 🔒 Session-based authentication
- 🛡️ Command whitelisting
- ⚠️ Dangerous pattern detection
- 🚫 Path traversal prevention
- ⏱️ Command timeout protection
- 📊 Rate limiting per IP
- 🔍 Comprehensive logging

### Web Interface Features
- 🎨 Modern dark theme UI
- ⌨️ Command autocomplete
- 🔄 History navigation (↑/↓ keys)
- 📱 Mobile responsive design
- 📊 Live server statistics
- 🏷️ Clickable command tags
- ⚡ Quick action buttons

## 🛠️ Configuration

### Environment Variables

Edit `~/.config/mcp/.env` to customize:

```bash
# Server settings
MCP_HOST=0.0.0.0              # Listen on all interfaces
MCP_PORT=8080                 # Server port

# Security settings
ALLOWED_COMMANDS=ls,cat,pwd,grep,find,git,python3,node,npm,pip,curl,wget
COMMAND_TIMEOUT=30            # Maximum execution time (seconds)
MAX_OUTPUT_SIZE=1048576       # Maximum output size (bytes)
RATE_LIMIT=60                 # Requests per minute

# Optional authentication
AUTH_TOKEN=                   # Leave empty to disable
```

### Adding Custom Commands

To allow additional commands:

```bash
# Edit configuration
mcp config

# Add commands to ALLOWED_COMMANDS (comma-separated)
ALLOWED_COMMANDS=ls,cat,pwd,your_custom_command
```

## 📦 Usage

### Using the Command Line Tool

```bash
# Start the server
mcp start

# Stop the server
mcp stop

# Check status
mcp status

# View logs
mcp logs

# Edit configuration
mcp config

# Restart server
mcp restart
```

### Using Systemd

```bash
# Start service
sudo systemctl start mcp-noble

# Enable auto-start
sudo systemctl enable mcp-noble

# Check status
sudo systemctl status mcp-noble

# View logs
sudo journalctl -u mcp-noble -f
```

### API Endpoints

#### Execute Command
```bash
curl -X POST http://localhost:8080/execute \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "command=ls -la&session_id=YOUR_SESSION_ID"
```

#### Health Check
```bash
curl http://localhost:8080/health
```

#### Get Configuration
```bash
curl http://localhost:8080/api/config
```

#### Get Session History
```bash
curl http://localhost:8080/api/history?session_id=YOUR_SESSION_ID
```

## 🔒 Security Best Practices

1. **Firewall Configuration**
   ```bash
   # Allow only specific IPs
   sudo ufw allow from 192.168.1.0/24 to any port 8080
   ```

2. **Use Authentication Token**
   ```bash
   # Set in .env file
   AUTH_TOKEN=your_secure_token_here
   ```

3. **Restrict Commands**
   - Only whitelist necessary commands
   - Avoid commands that can modify system files
   - Never allow sudo, rm -rf, or similar dangerous commands

4. **Monitor Logs**
   ```bash
   # Watch for suspicious activity
   mcp logs
   ```

## 🐛 Troubleshooting

### Server Won't Start

```bash
# Check if port is in use
sudo lsof -i :8080

# Check logs
mcp logs

# Try different port
MCP_PORT=8081 mcp start
```

### Permission Denied

```bash
# Ensure proper permissions
chmod +x ~/.config/mcp/scripts/*.sh
chmod +x ~/.config/mcp/simple_http_server.py
```

### Commands Not Working

1. Check if command is whitelisted:
   ```bash
   grep ALLOWED_COMMANDS ~/.config/mcp/.env
   ```

2. Test command directly:
   ```bash
   which your_command
   ```

3. Add to whitelist if needed:
   ```bash
   mcp config
   # Add command to ALLOWED_COMMANDS
   ```

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Setup

```bash
# Clone repo
git clone https://github.com/racoi12/MCP_Noble.git
cd MCP_Noble

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run tests
python -m pytest tests/
```

## 📈 Performance Tips

1. **Adjust Rate Limits**: Increase for trusted networks
   ```bash
   RATE_LIMIT=120  # 120 requests per minute
   ```

2. **Optimize Output Size**: Reduce for faster responses
   ```bash
   MAX_OUTPUT_SIZE=524288  # 512KB
   ```

3. **Use Command Aliases**: Create shortcuts for common commands

## 🗺️ Roadmap

- [ ] WebSocket support for real-time output
- [ ] Multi-user authentication system
- [ ] Command scheduling and automation
- [ ] Docker container support
- [ ] Kubernetes deployment manifests
- [ ] Plugin system for extensions
- [ ] Terminal color support
- [ ] File upload/download capability

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Anthropic](https://anthropic.com) for Claude and MCP
- [Model Context Protocol](https://modelcontextprotocol.io/) specification
- Ubuntu community for the excellent Noble 24.04 release
- All contributors and testers

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/racoi12/MCP_Noble/issues)
- **Discussions**: [GitHub Discussions](https://github.com/racoi12/MCP_Noble/discussions)
- **Wiki**: [Project Wiki](https://github.com/racoi12/MCP_Noble/wiki)

---

<p align="center">
Made with ❤️ for the AI and Ubuntu communities
</p>
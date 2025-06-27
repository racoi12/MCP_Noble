#!/usr/bin/env python3
"""
Enhanced MCP HTTP Server with Web UI
An improved version of the MCP Noble HTTP server with better features and security
"""

import asyncio
import json
import os
import subprocess
import sys
import time
import uuid
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse
import html
import hashlib
import hmac
import secrets
from typing import Dict, List, Optional, Tuple

# Configuration
DEFAULT_PORT = 8080
DEFAULT_HOST = '0.0.0.0'
CONFIG_FILE = os.path.expanduser('~/.config/mcp/.env')
SESSION_TIMEOUT = 3600  # 1 hour

# Load environment variables
def load_config():
    config = {
        'ALLOWED_COMMANDS': 'ls,cat,pwd,grep,find,git,python3,node,npm,pip,curl,wget,wc,head,tail,ps,df,free,uname,whoami,date,echo,which',
        'COMMAND_TIMEOUT': '30',
        'MAX_OUTPUT_SIZE': '1048576',  # 1MB
        'RATE_LIMIT': '60',  # requests per minute
        'AUTH_TOKEN': '',  # Optional authentication token
    }
    
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r') as f:
            for line in f:
                if '=' in line and not line.strip().startswith('#'):
                    key, value = line.strip().split('=', 1)
                    config[key] = value.strip('"\'')
    
    return config

CONFIG = load_config()

# Session management
class SessionManager:
    def __init__(self):
        self.sessions = {}
        self.command_history = {}
    
    def create_session(self) -> str:
        session_id = secrets.token_urlsafe(32)
        self.sessions[session_id] = {
            'created': time.time(),
            'last_access': time.time(),
            'commands_run': 0
        }
        self.command_history[session_id] = []
        return session_id
    
    def validate_session(self, session_id: str) -> bool:
        if session_id not in self.sessions:
            return False
        
        session = self.sessions[session_id]
        if time.time() - session['last_access'] > SESSION_TIMEOUT:
            del self.sessions[session_id]
            if session_id in self.command_history:
                del self.command_history[session_id]
            return False
        
        session['last_access'] = time.time()
        return True
    
    def add_command(self, session_id: str, command: str, result: dict):
        if session_id in self.command_history:
            self.command_history[session_id].append({
                'timestamp': datetime.now().isoformat(),
                'command': command,
                'result': result
            })
            # Keep only last 100 commands
            if len(self.command_history[session_id]) > 100:
                self.command_history[session_id].pop(0)
            
            self.sessions[session_id]['commands_run'] += 1

session_manager = SessionManager()

# Rate limiting
class RateLimiter:
    def __init__(self, limit: int = 60):
        self.limit = limit
        self.requests = {}
    
    def is_allowed(self, client_ip: str) -> bool:
        now = time.time()
        minute_ago = now - 60
        
        if client_ip not in self.requests:
            self.requests[client_ip] = []
        
        # Clean old requests
        self.requests[client_ip] = [t for t in self.requests[client_ip] if t > minute_ago]
        
        if len(self.requests[client_ip]) >= self.limit:
            return False
        
        self.requests[client_ip].append(now)
        return True

rate_limiter = RateLimiter(int(CONFIG.get('RATE_LIMIT', '60')))

# Enhanced request handler
class MCPHTTPHandler(BaseHTTPRequestHandler):
    
    def do_GET(self):
        """Handle GET requests"""
        parsed_path = urlparse(self.path)
        path = parsed_path.path
        
        if path == '/':
            self.serve_web_ui()
        elif path == '/health':
            self.serve_health()
        elif path == '/api/config':
            self.serve_config()
        elif path == '/api/history':
            self.serve_history()
        elif path == '/api/stats':
            self.serve_stats()
        else:
            self.send_error(404, "Not Found")
    
    def do_POST(self):
        """Handle POST requests"""
        parsed_path = urlparse(self.path)
        path = parsed_path.path
        
        # Check rate limiting
        client_ip = self.client_address[0]
        if not rate_limiter.is_allowed(client_ip):
            self.send_error(429, "Too Many Requests")
            return
        
        if path == '/execute':
            self.handle_execute()
        elif path == '/api/session':
            self.handle_session()
        else:
            self.send_error(404, "Not Found")
    
    def serve_web_ui(self):
        """Serve the enhanced web interface"""
        html_content = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MCP Noble Shell Server</title>
    <style>
        :root {
            --bg-primary: #0a0e27;
            --bg-secondary: #1a1f3a;
            --text-primary: #e4e4e7;
            --text-secondary: #a1a1aa;
            --accent: #3b82f6;
            --success: #10b981;
            --error: #ef4444;
            --warning: #f59e0b;
        }
        
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', system-ui, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
        }
        
        header {
            background: var(--bg-secondary);
            padding: 1rem 2rem;
            border-bottom: 1px solid rgba(255,255,255,0.1);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        h1 {
            font-size: 1.5rem;
            font-weight: 600;
            color: var(--accent);
        }
        
        .stats {
            display: flex;
            gap: 2rem;
            font-size: 0.875rem;
        }
        
        .stat {
            color: var(--text-secondary);
        }
        
        .stat span {
            color: var(--text-primary);
            font-weight: 500;
        }
        
        main {
            flex: 1;
            display: flex;
            padding: 2rem;
            gap: 2rem;
            max-width: 1400px;
            width: 100%;
            margin: 0 auto;
        }
        
        .terminal-section {
            flex: 1;
            display: flex;
            flex-direction: column;
        }
        
        .terminal {
            background: var(--bg-secondary);
            border-radius: 8px;
            padding: 1.5rem;
            flex: 1;
            display: flex;
            flex-direction: column;
            box-shadow: 0 4px 6px rgba(0,0,0,0.3);
        }
        
        .output {
            flex: 1;
            overflow-y: auto;
            font-family: 'Consolas', 'Monaco', monospace;
            font-size: 0.875rem;
            line-height: 1.6;
            white-space: pre-wrap;
            word-wrap: break-word;
            margin-bottom: 1rem;
            max-height: 500px;
        }
        
        .command-line {
            display: flex;
            gap: 0.5rem;
            align-items: center;
        }
        
        .prompt {
            color: var(--success);
            font-family: monospace;
        }
        
        #commandInput {
            flex: 1;
            background: var(--bg-primary);
            border: 1px solid rgba(255,255,255,0.1);
            color: var(--text-primary);
            padding: 0.5rem;
            border-radius: 4px;
            font-family: monospace;
            font-size: 0.875rem;
        }
        
        #commandInput:focus {
            outline: none;
            border-color: var(--accent);
        }
        
        button {
            background: var(--accent);
            color: white;
            border: none;
            padding: 0.5rem 1rem;
            border-radius: 4px;
            cursor: pointer;
            font-weight: 500;
            transition: background 0.2s;
        }
        
        button:hover {
            background: #2563eb;
        }
        
        button:disabled {
            background: var(--text-secondary);
            cursor: not-allowed;
        }
        
        .sidebar {
            width: 300px;
        }
        
        .panel {
            background: var(--bg-secondary);
            border-radius: 8px;
            padding: 1.5rem;
            margin-bottom: 1.5rem;
            box-shadow: 0 4px 6px rgba(0,0,0,0.3);
        }
        
        .panel h2 {
            font-size: 1.125rem;
            margin-bottom: 1rem;
            color: var(--accent);
        }
        
        .allowed-commands {
            display: flex;
            flex-wrap: wrap;
            gap: 0.5rem;
        }
        
        .command-tag {
            background: var(--bg-primary);
            padding: 0.25rem 0.75rem;
            border-radius: 4px;
            font-size: 0.75rem;
            font-family: monospace;
            color: var(--text-secondary);
            cursor: pointer;
            transition: all 0.2s;
        }
        
        .command-tag:hover {
            color: var(--text-primary);
            background: rgba(59, 130, 246, 0.2);
        }
        
        .history-item {
            padding: 0.5rem;
            margin-bottom: 0.5rem;
            background: var(--bg-primary);
            border-radius: 4px;
            font-size: 0.875rem;
            cursor: pointer;
            transition: background 0.2s;
        }
        
        .history-item:hover {
            background: rgba(59, 130, 246, 0.1);
        }
        
        .history-command {
            color: var(--text-primary);
            font-family: monospace;
        }
        
        .history-time {
            color: var(--text-secondary);
            font-size: 0.75rem;
        }
        
        .success { color: var(--success); }
        .error { color: var(--error); }
        .warning { color: var(--warning); }
        
        .loading {
            display: inline-block;
            animation: spin 1s linear infinite;
        }
        
        @keyframes spin {
            from { transform: rotate(0deg); }
            to { transform: rotate(360deg); }
        }
        
        @media (max-width: 768px) {
            main {
                flex-direction: column;
            }
            .sidebar {
                width: 100%;
            }
        }
    </style>
</head>
<body>
    <header>
        <h1>🚀 MCP Noble Shell Server</h1>
        <div class="stats">
            <div class="stat">Session: <span id="sessionId">-</span></div>
            <div class="stat">Commands: <span id="commandCount">0</span></div>
            <div class="stat">Uptime: <span id="uptime">0s</span></div>
        </div>
    </header>
    
    <main>
        <div class="terminal-section">
            <div class="terminal">
                <div class="output" id="output">Welcome to MCP Noble Shell Server!
Type 'help' for available commands or click on any command tag.
</div>
                <div class="command-line">
                    <span class="prompt">ubuntu@mcp:~$</span>
                    <input type="text" id="commandInput" placeholder="Enter command..." autofocus>
                    <button id="executeBtn" onclick="executeCommand()">Execute</button>
                    <button onclick="clearTerminal()">Clear</button>
                </div>
            </div>
        </div>
        
        <div class="sidebar">
            <div class="panel">
                <h2>📋 Allowed Commands</h2>
                <div class="allowed-commands" id="allowedCommands"></div>
            </div>
            
            <div class="panel">
                <h2>📜 Command History</h2>
                <div id="history"></div>
            </div>
            
            <div class="panel">
                <h2>⚡ Quick Actions</h2>
                <button onclick="runCommand('uname -a')" style="width: 100%; margin-bottom: 0.5rem;">System Info</button>
                <button onclick="runCommand('df -h')" style="width: 100%; margin-bottom: 0.5rem;">Disk Usage</button>
                <button onclick="runCommand('free -h')" style="width: 100%; margin-bottom: 0.5rem;">Memory Usage</button>
                <button onclick="runCommand('ps aux | head -10')" style="width: 100%;">Top Processes</button>
            </div>
        </div>
    </main>
    
    <script>
        let sessionId = null;
        let commandHistory = [];
        let historyIndex = -1;
        let startTime = Date.now();
        
        // Initialize session
        async function initSession() {
            try {
                const response = await fetch('/api/session', { method: 'POST' });
                const data = await response.json();
                sessionId = data.session_id;
                document.getElementById('sessionId').textContent = sessionId.substring(0, 8) + '...';
                localStorage.setItem('mcp_session', sessionId);
            } catch (error) {
                console.error('Failed to initialize session:', error);
            }
        }
        
        // Load configuration
        async function loadConfig() {
            try {
                const response = await fetch('/api/config');
                const data = await response.json();
                const commands = data.allowed_commands.split(',');
                const container = document.getElementById('allowedCommands');
                container.innerHTML = commands.map(cmd => 
                    `<div class="command-tag" onclick="runCommand('${cmd}')">${cmd}</div>`
                ).join('');
            } catch (error) {
                console.error('Failed to load config:', error);
            }
        }
        
        // Execute command
        async function executeCommand() {
            const input = document.getElementById('commandInput');
            const command = input.value.trim();
            
            if (!command) return;
            
            if (command === 'help') {
                showHelp();
                input.value = '';
                return;
            }
            
            if (command === 'clear') {
                clearTerminal();
                input.value = '';
                return;
            }
            
            const btn = document.getElementById('executeBtn');
            btn.disabled = true;
            btn.innerHTML = '<span class="loading">⚡</span> Running...';
            
            appendOutput(`$ ${command}`, 'prompt');
            
            try {
                const formData = new URLSearchParams();
                formData.append('command', command);
                formData.append('session_id', sessionId);
                
                const response = await fetch('/execute', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/x-www-form-urlencoded',
                    },
                    body: formData
                });
                
                const result = await response.json();
                
                if (result.success) {
                    if (result.output) {
                        appendOutput(result.output, 'success');
                    }
                    if (result.error) {
                        appendOutput(result.error, 'warning');
                    }
                } else {
                    appendOutput(`Error: ${result.error}`, 'error');
                }
                
                // Update history
                commandHistory.push(command);
                historyIndex = commandHistory.length;
                updateHistory();
                updateStats();
                
            } catch (error) {
                appendOutput(`Network error: ${error.message}`, 'error');
            } finally {
                btn.disabled = false;
                btn.innerHTML = 'Execute';
                input.value = '';
                input.focus();
            }
        }
        
        // Helper functions
        function appendOutput(text, className = '') {
            const output = document.getElementById('output');
            const line = document.createElement('div');
            if (className) line.className = className;
            line.textContent = text;
            output.appendChild(line);
            output.scrollTop = output.scrollHeight;
        }
        
        function clearTerminal() {
            document.getElementById('output').innerHTML = 'Terminal cleared.\\n';
        }
        
        function runCommand(cmd) {
            document.getElementById('commandInput').value = cmd;
            executeCommand();
        }
        
        function showHelp() {
            appendOutput(`
Available commands:
  help     - Show this help message
  clear    - Clear the terminal
  [cmd]    - Execute any allowed shell command

Keyboard shortcuts:
  Enter    - Execute command
  ↑/↓      - Navigate command history
  Ctrl+L   - Clear terminal

Click on any command tag to run it directly.
            `, 'success');
        }
        
        async function updateHistory() {
            try {
                const response = await fetch(`/api/history?session_id=${sessionId}`);
                const data = await response.json();
                const container = document.getElementById('history');
                
                container.innerHTML = data.history.slice(-5).reverse().map(item => `
                    <div class="history-item" onclick="runCommand('${item.command}')">
                        <div class="history-command">${item.command}</div>
                        <div class="history-time">${new Date(item.timestamp).toLocaleTimeString()}</div>
                    </div>
                `).join('');
            } catch (error) {
                console.error('Failed to update history:', error);
            }
        }
        
        function updateStats() {
            const count = parseInt(document.getElementById('commandCount').textContent) + 1;
            document.getElementById('commandCount').textContent = count;
        }
        
        function updateUptime() {
            const elapsed = Math.floor((Date.now() - startTime) / 1000);
            const hours = Math.floor(elapsed / 3600);
            const minutes = Math.floor((elapsed % 3600) / 60);
            const seconds = elapsed % 60;
            
            let uptime = '';
            if (hours > 0) uptime += `${hours}h `;
            if (minutes > 0) uptime += `${minutes}m `;
            uptime += `${seconds}s`;
            
            document.getElementById('uptime').textContent = uptime;
        }
        
        // Event listeners
        document.getElementById('commandInput').addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                executeCommand();
            } else if (e.key === 'ArrowUp') {
                e.preventDefault();
                if (historyIndex > 0) {
                    historyIndex--;
                    e.target.value = commandHistory[historyIndex];
                }
            } else if (e.key === 'ArrowDown') {
                e.preventDefault();
                if (historyIndex < commandHistory.length - 1) {
                    historyIndex++;
                    e.target.value = commandHistory[historyIndex];
                } else {
                    historyIndex = commandHistory.length;
                    e.target.value = '';
                }
            } else if (e.ctrlKey && e.key === 'l') {
                e.preventDefault();
                clearTerminal();
            }
        });
        
        // Initialize
        window.onload = async () => {
            await initSession();
            await loadConfig();
            setInterval(updateUptime, 1000);
        };
    </script>
</body>
</html>
        '''
        
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(html_content.encode())
    
    def serve_health(self):
        """Serve health check endpoint"""
        health_data = {
            'status': 'healthy',
            'timestamp': datetime.now().isoformat(),
            'version': '2.0.0',
            'uptime': int(time.time() - self.server.start_time),
            'active_sessions': len(session_manager.sessions)
        }
        
        self.send_json_response(health_data)
    
    def serve_config(self):
        """Serve configuration information"""
        config_data = {
            'allowed_commands': CONFIG.get('ALLOWED_COMMANDS', ''),
            'command_timeout': int(CONFIG.get('COMMAND_TIMEOUT', '30')),
            'max_output_size': int(CONFIG.get('MAX_OUTPUT_SIZE', '1048576')),
            'rate_limit': int(CONFIG.get('RATE_LIMIT', '60'))
        }
        
        self.send_json_response(config_data)
    
    def serve_history(self):
        """Serve command history for a session"""
        params = parse_qs(urlparse(self.path).query)
        session_id = params.get('session_id', [''])[0]
        
        if not session_manager.validate_session(session_id):
            self.send_error(401, "Invalid or expired session")
            return
        
        history = session_manager.command_history.get(session_id, [])
        self.send_json_response({'history': history[-10:]})  # Last 10 commands
    
    def serve_stats(self):
        """Serve server statistics"""
        stats_data = {
            'total_sessions': len(session_manager.sessions),
            'total_commands': sum(s['commands_run'] for s in session_manager.sessions.values()),
            'server_uptime': int(time.time() - self.server.start_time),
            'active_sessions': len([s for s in session_manager.sessions.values() 
                                  if time.time() - s['last_access'] < 300])  # Active in last 5 min
        }
        
        self.send_json_response(stats_data)
    
    def handle_session(self):
        """Handle session creation"""
        session_id = session_manager.create_session()
        self.send_json_response({'session_id': session_id})
    
    def handle_execute(self):
        """Handle command execution with enhanced security"""
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length).decode('utf-8')
        params = parse_qs(post_data)
        
        command = params.get('command', [''])[0]
        session_id = params.get('session_id', [''])[0]
        
        # Validate session
        if not session_manager.validate_session(session_id):
            self.send_error(401, "Invalid or expired session")
            return
        
        # Validate command
        if not command:
            self.send_json_response({'success': False, 'error': 'No command provided'})
            return
        
        # Check if command is allowed
        allowed_commands = CONFIG.get('ALLOWED_COMMANDS', '').split(',')
        command_base = command.split()[0] if command.split() else ''
        
        if command_base not in allowed_commands:
            error_msg = f"Command '{command_base}' is not allowed. "
            error_msg += f"Allowed commands: {', '.join(allowed_commands[:10])}"
            if len(allowed_commands) > 10:
                error_msg += f" and {len(allowed_commands) - 10} more"
            
            result = {'success': False, 'error': error_msg}
            session_manager.add_command(session_id, command, result)
            self.send_json_response(result)
            return
        
        # Additional security checks
        dangerous_patterns = ['..', '~/', '/etc/', '/root/', '$(', '${', '`', ';rm', ';sudo']
        for pattern in dangerous_patterns:
            if pattern in command:
                result = {'success': False, 'error': f'Security violation: dangerous pattern "{pattern}" detected'}
                session_manager.add_command(session_id, command, result)
                self.send_json_response(result)
                return
        
        # Execute command with timeout and size limits
        try:
            timeout = int(CONFIG.get('COMMAND_TIMEOUT', '30'))
            max_output = int(CONFIG.get('MAX_OUTPUT_SIZE', '1048576'))
            
            process = subprocess.Popen(
                command,
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                cwd=os.path.expanduser('~'),
                env={**os.environ, 'PATH': '/usr/local/bin:/usr/bin:/bin'}
            )
            
            stdout, stderr = process.communicate(timeout=timeout)
            
            # Truncate output if too large
            if len(stdout) > max_output:
                stdout = stdout[:max_output] + f"\\n... (output truncated at {max_output} bytes)"
            if len(stderr) > max_output:
                stderr = stderr[:max_output] + f"\\n... (error output truncated at {max_output} bytes)"
            
            result = {
                'success': True,
                'output': stdout,
                'error': stderr,
                'exit_code': process.returncode
            }
            
        except subprocess.TimeoutExpired:
            result = {'success': False, 'error': f'Command timed out after {timeout} seconds'}
        except Exception as e:
            result = {'success': False, 'error': f'Execution error: {str(e)}'}
        
        # Log command and result
        session_manager.add_command(session_id, command, result)
        
        self.send_json_response(result)
    
    def send_json_response(self, data):
        """Send JSON response"""
        response = json.dumps(data)
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(response.encode())
    
    def log_message(self, format, *args):
        """Custom log format"""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        client_ip = self.client_address[0]
        print(f"[{timestamp}] {client_ip} - {format % args}")

# Main server class
class MCPHTTPServer(HTTPServer):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.start_time = time.time()

def main():
    """Main entry point"""
    host = os.getenv('MCP_HOST', DEFAULT_HOST)
    port = int(os.getenv('MCP_PORT', DEFAULT_PORT))
    
    print(f"""
╔══════════════════════════════════════════════════════════════════╗
║           🚀 MCP Noble Enhanced HTTP Server v2.0 🚀             ║
╚══════════════════════════════════════════════════════════════════╝

📍 Server Configuration:
   • Host: {host}
   • Port: {port}
   • Allowed Commands: {len(CONFIG.get('ALLOWED_COMMANDS', '').split(','))} commands
   • Command Timeout: {CONFIG.get('COMMAND_TIMEOUT', '30')}s
   • Rate Limit: {CONFIG.get('RATE_LIMIT', '60')} req/min

🌐 Access URLs:
   • Web Interface: http://{host if host != '0.0.0.0' else 'localhost'}:{port}/
   • Health Check:  http://{host if host != '0.0.0.0' else 'localhost'}:{port}/health
   • API Config:    http://{host if host != '0.0.0.0' else 'localhost'}:{port}/api/config

🛡️  Security Features:
   • Session-based authentication
   • Command whitelisting
   • Rate limiting
   • Output size limits
   • Dangerous pattern detection

Press Ctrl+C to stop the server.
""")
    
    try:
        server = MCPHTTPServer((host, port), MCPHTTPHandler)
        print(f"✅ Server started successfully on {host}:{port}")
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n🛑 Server stopped by user")
    except PermissionError:
        print(f"❌ Error: Permission denied to bind to port {port}")
        print(f"   Try a port number above 1024 or run with sudo")
    except OSError as e:
        if e.errno == 98:  # Address already in use
            print(f"❌ Error: Port {port} is already in use")
            print(f"   Try a different port or stop the existing service")
        else:
            print(f"❌ Error: {e}")
    except Exception as e:
        print(f"❌ Fatal error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
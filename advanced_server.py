#!/usr/bin/env python3
"""
Enhanced MCP HTTP Server with Web UI
An improved version of the MCP Noble HTTP server with better features and security
"""

import json
import os
import subprocess
import sys
import time
import secrets
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse

# --- Configuration ---
# Note: The 'config' dictionary provides default values.
# The installer script creates a .env file that will override these.
CONFIG_FILE = os.path.expanduser('~/.config/mcp/.env')
SESSION_TIMEOUT = 3600  # 1 hour

def load_config():
    """Loads configuration from a .env file, falling back to defaults."""
    config = {
        'ALLOWED_COMMANDS': 'ls,cat,pwd,grep,find,git,python3,node,npm,pip,curl,wget,wc,head,tail,ps,df,free,uname,whoami,date,echo,which',
        'COMMAND_TIMEOUT': '30',
        'MAX_OUTPUT_SIZE': '1048576',  # 1MB
        'RATE_LIMIT': '60',
        'AUTH_TOKEN': '',
        'MCP_PORT': '8080'
    }
    
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r') as f:
            for line in f:
                if '=' in line and not line.strip().startswith('#'):
                    key, value = line.strip().split('=', 1)
                    config[key.strip()] = value.strip().strip('"\'')
    return config

CONFIG = load_config()
IS_UNRESTRICTED = CONFIG.get('ALLOWED_COMMANDS') == '*'

# --- Session Management ---
class SessionManager:
    """Manages user sessions and their command history."""
    def __init__(self):
        self.sessions = {}
    
    def create_session(self) -> str:
        session_id = secrets.token_urlsafe(16)
        self.sessions[session_id] = {
            'created': time.time(),
            'last_access': time.time(),
            'history': []
        }
        return session_id
    
    def validate_session(self, session_id: str):
        session = self.sessions.get(session_id)
        if not session: return None
        if time.time() - session['last_access'] > SESSION_TIMEOUT:
            del self.sessions[session_id]
            return None
        session['last_access'] = time.time()
        return session
        
    def add_command(self, session_id: str, command: str, result: dict):
        session = self.validate_session(session_id)
        if session:
            session['history'].append({
                'timestamp': datetime.now().isoformat(),
                'command': command,
                'result': result
            })
            session['history'] = session['history'][-50:] # Keep last 50 commands

session_manager = SessionManager()

# --- Core HTTP Handler ---
class MCPHTTPHandler(BaseHTTPRequestHandler):
    """Handles all incoming HTTP requests."""
    
    # --- Request Routing ---
    def do_GET(self):
        routes = {
            '/': self.serve_web_ui,
            '/api/config': self.serve_api_config,
            '/api/history': self.serve_api_history
        }
        handler = routes.get(urlparse(self.path).path)
        if handler: handler()
        else: self.send_error(404, "Not Found")
    
    def do_POST(self):
        routes = {
            '/api/execute': self.serve_api_execute,
            '/api/session': self.serve_api_session
        }
        handler = routes.get(urlparse(self.path).path)
        if handler: handler()
        else: self.send_error(404, "Not Found")

    # --- API Endpoints ---
    def serve_api_session(self):
        self.send_json({'session_id': session_manager.create_session()})

    def serve_api_config(self):
        self.send_json({'allowed_commands': CONFIG.get('ALLOWED_COMMANDS')})
    
    def serve_api_history(self):
        session_id = parse_qs(urlparse(self.path).query).get('session_id', [None])[0]
        session = session_manager.validate_session(session_id)
        if not session: return self.send_error(403, "Invalid session")
        self.send_json(session['history'])

    def serve_api_execute(self):
        try:
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            params = parse_qs(post_data.decode('utf-8'))
            command = params.get('command', [''])[0]
            session_id = params.get('session_id', [''])[0]

            if not session_manager.validate_session(session_id):
                return self.send_json({'error': 'Invalid or expired session'}, status=403)
            
            if not command:
                return self.send_json({'error': 'Command cannot be empty'}, status=400)
            
            # Security Check
            command_base = command.split()[0]
            if not IS_UNRESTRICTED and command_base not in CONFIG.get('ALLOWED_COMMANDS').split(','):
                err_msg = f"Command '{command_base}' is not allowed."
                result = {'success': False, 'error': err_msg, 'output': '', 'exit_code': -1, 'command': command}
                session_manager.add_command(session_id, command, result)
                return self.send_json(result, status=403)

            # Execute Command
            timeout = int(CONFIG.get('COMMAND_TIMEOUT'))
            proc = subprocess.run(
                command, shell=True, capture_output=True, 
                text=True, timeout=timeout, cwd=os.path.expanduser('~')
            )
            
            result = {'success': True, 'command': command, 'output': proc.stdout, 'error': proc.stderr, 'exit_code': proc.returncode}
            session_manager.add_command(session_id, command, result)
            self.send_json(result)

        except Exception as e:
            self.send_json({'error': f'Server Execution Error: {str(e)}'}, status=500)

    # --- Web UI ---
    def serve_web_ui(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        html_content = """
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>MCP Shell</title><style>
body{font-family:monospace;background-color:#1e1e1e;color:#d4d4d4;display:flex;flex-direction:column;height:100vh;margin:0}
#header{padding:1rem;background-color:#252526;border-bottom:1px solid #333;display:flex;justify-content:space-between;align-items:center}
#main{display:flex;flex:1;overflow:hidden}
#sidebar{width:300px;background-color:#252526;padding:1rem;overflow-y:auto;border-right:1px solid #333}
#content{flex:1;padding:1rem;display:flex;flex-direction:column}
#output{flex:1;background-color:#1e1e1e;padding:1rem;overflow-y:auto;white-space:pre-wrap;margin-bottom:1rem;border-radius:4px;border:1px solid #333}
#input-form{display:flex;gap:0.5rem}#command-input{flex:1;background-color:#3c3c3c;color:#d4d4d4;border:1px solid #3c3c3c;padding:0.5rem;border-radius:4px}
#history-list{list-style:none;padding:0}#history-list li{padding:0.5rem;cursor:pointer;border-radius:4px;margin-bottom:5px;word-break:break-all}#history-list li:hover{background-color:#3c3c3c}
.prompt{color:#608b4e}.error{color:#f44747}.command-echo{color:#569cd6;font-weight:bold}
.exit-code-success{color:#4ec9b0}.exit-code-fail{color:#f44747}
</style></head><body><div id="header"><h1>MCP Shell Server</h1><div id="session-info"></div></div>
<div id="main"><div id="sidebar"><h2>History</h2><ul id="history-list"></ul></div>
<div id="content"><div id="output"></div><form id="input-form" onsubmit="sendCommand(event)">
<span class="prompt">$&nbsp;</span><input id="command-input" type="text" autocomplete="off" autofocus/>
</form></div></div><script>
let sessionId;
const outputEl=document.getElementById('output');const historyEl=document.getElementById('history-list');const inputEl=document.getElementById('command-input');
async function initSession(){const r=await fetch('/api/session',{method:'POST'});const d=await r.json();sessionId=d.session_id;document.getElementById('session-info').innerText=`Session: ${sessionId.substring(0,8)}`}
async function sendCommand(e){e.preventDefault();const c=inputEl.value.trim();if(!c)return;
appendOutput('$ '+c, 'command-echo');inputEl.value='';
const f=new URLSearchParams();f.append('command',c);f.append('session_id',sessionId);
try{const r=await fetch('/api/execute',{method:'POST',body:f});const d=await r.json();
if(d.output)appendOutput(d.output);if(d.error)appendOutput(d.error,'error');
appendOutput(`Exit Code: ${d.exit_code}`, d.exit_code===0 ? 'exit-code-success' : 'exit-code-fail');
updateHistory();}catch(e){appendOutput('Network Error: '+e,'error')}finally{outputEl.scrollTop=outputEl.scrollHeight;}}
function appendOutput(text,className=''){const d=document.createElement('div');if(className)d.className=className;d.textContent=text;outputEl.appendChild(d);}
async function updateHistory(){const r=await fetch(`/api/history?session_id=${sessionId}`);const h=await r.json();
historyEl.innerHTML='';h.reverse().forEach(item=>{const l=document.createElement('li');l.textContent=item.command;l.onclick=()=>{inputEl.value=item.command;inputEl.focus()};historyEl.appendChild(l)});};
window.onload=initSession;
</script></body></html>"""
        self.wfile.write(html_content.encode('utf-8'))

    # --- Helper Methods ---
    def send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode('utf-8'))

    def log_message(self, format, *args):
        # Override to suppress default logging to stderr for a cleaner console
        return

# --- Main Execution ---
def main():
    host = CONFIG.get('MCP_HOST', '0.0.0.0')
    port = int(CONFIG.get('MCP_PORT', '8080'))
    server_address = (host, port)
    
    mode = "UNRESTRICTED" if IS_UNRESTRICTED else "RESTRICTED"
    print(f"Starting MCP Server ({mode} MODE) on port {port}...")
    
    try:
        httpd = HTTPServer(server_address, MCPHTTPHandler)
        httpd.serve_forever()
    except Exception as e:
        print(f"❌ Fatal error starting server: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()

# 1. Instalar aiohttp correctamente
python3 -m pip install --user aiohttp --break-system-packages

# 2. Crear servidor HTTP simple (sin aiohttp)
cat > ~/.config/mcp/simple_http_server.py << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import subprocess
import urllib.parse
from urllib.parse import parse_qs

class MCPHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            html = '''
            <html><body>
            <h1>🚀 MCP Shell Server - VM Ubuntu</h1>
            <p>Execute commands remotely:</p>
            <form onsubmit="executeCommand(event)">
                <input type="text" id="cmd" placeholder="ls -la" style="width:400px; padding:10px">
                <button type="submit">Execute</button>
            </form>
            <div id="result"></div>
            <script>
            async function executeCommand(e) {
                e.preventDefault();
                const cmd = document.getElementById('cmd').value;
                const response = await fetch('/execute', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
                    body: 'command=' + encodeURIComponent(cmd)
                });
                const result = await response.text();
                document.getElementById('result').innerHTML = '<h3>Result:</h3><pre>' + result + '</pre>';
            }
            </script>
            </body></html>
            '''
            self.wfile.write(html.encode())
        elif self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status": "healthy", "server": "mcp-vm"}')

    def do_POST(self):
        if self.path == '/execute':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            
            try:
                data = parse_qs(post_data.decode())
                command = data.get('command', [''])[0].strip()
                
                # Lista de comandos permitidos
                allowed = ['ls', 'pwd', 'cat', 'grep', 'find', 'git', 'python3', 'node', 'uname', 'whoami', 'df', 'free', 'ps']
                first_word = command.split()[0] if command.split() else ""
                
                if first_word not in allowed:
                    result = f"❌ Command '{first_word}' not allowed.\n✅ Allowed: {', '.join(allowed)}"
                else:
                    try:
                        proc_result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=30)
                        result = f"🚀 Command: {command}\n📊 Exit code: {proc_result.returncode}\n\n"
                        if proc_result.stdout:
                            result += f"📤 Output:\n{proc_result.stdout}\n"
                        if proc_result.stderr:
                            result += f"❌ Error:\n{proc_result.stderr}\n"
                    except subprocess.TimeoutExpired:
                        result = "⏰ Command timed out"
                    except Exception as e:
                        result = f"❌ Error: {str(e)}"
                
                self.send_response(200)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                self.wfile.write(result.encode())
                
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                self.wfile.write(f"Server error: {str(e)}".encode())

PORT = 8080
with socketserver.TCPServer(("0.0.0.0", PORT), MCPHandler) as httpd:
    print(f"🚀 MCP HTTP Server running on http://0.0.0.0:{PORT}")
    print(f"📍 Access from host: http://10.252.48.172:{PORT}")
    print("Press Ctrl+C to stop")
    httpd.serve_forever()
EOF

chmod +x ~/.config/mcp/simple_http_server.py

# 3. Ejecutar servidor simple
python3 ~/.config/mcp/simple_http_server.py
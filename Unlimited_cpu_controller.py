import socket
import threading
import json
import time
from datetime import datetime
import sys

class RenderFarmController:
    def __init__(self):
        self.connected_nodes = {}
        self.server_socket = None
        self.running = True
        self.config = {
            'listen_port': 8888,
            'secret_key': 'render-farm-secret-2024'
        }
    
    def start_server(self):
        """Start server to accept worker connections"""
        try:
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.server_socket.bind(('0.0.0.0', self.config['listen_port']))
            self.server_socket.listen(10)
            self.server_socket.settimeout(1.0)
            
            print(f"✅ Controller listening on port {self.config['listen_port']}")
            print("   Workers will automatically connect to this machine")
            print("   Make sure port 8888 is forwarded on your router!")
            
            while self.running:
                try:
                    client_socket, addr = self.server_socket.accept()
                    thread = threading.Thread(target=self.handle_worker_connection, 
                                           args=(client_socket, addr), daemon=True)
                    thread.start()
                except socket.timeout:
                    continue
                except Exception as e:
                    if self.running:
                        print(f"Server error: {e}")
        except Exception as e:
            print(f"❌ Failed to start server: {e}")
            print("   Check if port 8888 is available or another instance is running")
    
    def handle_worker_connection(self, sock, addr):
        """Handle incoming worker connection"""
        node_name = None
        try:
            data = sock.recv(4096).decode('utf-8')
            hello_data = json.loads(data)
            
            if hello_data.get('secret_key') != self.config['secret_key']:
                sock.close()
                return
            
            node_name = hello_data['node_name']
            self.connected_nodes[node_name] = {
                'socket': sock,
                'address': addr,
                'last_seen': datetime.now(),
                'status': 'connected'
            }
            
            print(f"✅ Worker connected: {node_name} from {addr[0]}")
            
            while self.running and node_name in self.connected_nodes:
                try:
                    sock.settimeout(1.0)
                    data = sock.recv(1024)
                    if not data:
                        break
                        
                    response = json.loads(data.decode('utf-8'))
                    if response.get('type') == 'alive':
                        self.connected_nodes[node_name]['last_seen'] = datetime.now()
                        
                except socket.timeout:
                    keepalive = {'type': 'keepalive', 'secret_key': self.config['secret_key']}
                    try:
                        sock.send(json.dumps(keepalive).encode('utf-8'))
                    except:
                        break
                except:
                    break
                    
        except Exception as e:
            pass
        finally:
            if node_name and node_name in self.connected_nodes:
                del self.connected_nodes[node_name]
                print(f"❌ Worker disconnected: {node_name}")
            try:
                sock.close()
            except:
                pass
    
    def send_command(self, node_name, command):
        """Send command to specific worker"""
        if node_name not in self.connected_nodes:
            return f"Error: Node {node_name} not connected"
        
        node = self.connected_nodes[node_name]
        try:
            command_data = {
                'type': 'command',
                'command': command,
                'secret_key': self.config['secret_key']
            }
            
            node['socket'].send(json.dumps(command_data).encode('utf-8'))
            node['socket'].settimeout(30.0)
            response_data = node['socket'].recv(65536).decode('utf-8')
            response = json.loads(response_data)
            
            if 'error' in response:
                return f"Error: {response['error']}"
            else:
                result = response.get('stdout', '')
                if response.get('stderr'):
                    result += f"\nErrors: {response['stderr']}"
                return result
                
        except Exception as e:
            return f"Command error: {str(e)}"
    
    def run_command_all(self, command):
        """Run command on all connected workers"""
        results = {}
        threads = []
        lock = threading.Lock()
        
        def worker(node_name):
            result = self.send_command(node_name, command)
            with lock:
                results[node_name] = result
        
        for node_name in list(self.connected_nodes.keys()):
            thread = threading.Thread(target=worker, args=(node_name,))
            threads.append(thread)
            thread.start()
        
        for thread in threads:
            thread.join()
        
        return results
    
    def cleanup_dead_connections(self):
        """Remove dead connections"""
        dead_nodes = []
        for node_name, info in self.connected_nodes.items():
            if (datetime.now() - info['last_seen']).total_seconds() > 60:
                dead_nodes.append(node_name)
        
        for node_name in dead_nodes:
            del self.connected_nodes[node_name]
            print(f"Removed dead connection: {node_name}")
    
    def menu(self):
        """Controller menu"""
        server_thread = threading.Thread(target=self.start_server, daemon=True)
        server_thread.start()
        
        time.sleep(1)  # Give server time to start
        
        while True:
            print(f"\n{'='*50}")
            print(f"🎮 RENDER FARM CONTROLLER")
            print(f"{'='*50}")
            print(f"📊 Connected workers: {len(self.connected_nodes)}")
            
            if self.connected_nodes:
                for i, node in enumerate(self.connected_nodes.keys(), 1):
                    print(f"   {i}. {node}")
            else:
                print("   No workers connected")
            
            print(f"\n1. Run command on specific node")
            print(f"2. Run command on ALL nodes")
            print(f"3. Refresh connections")
            print(f"4. Exit")
            print(f"{'='*50}")
            
            choice = input("\nEnter choice: ").strip()
            
            if choice == '1':
                if not self.connected_nodes:
                    print("❌ No workers connected!")
                    continue
                    
                node_name = input("Enter node name: ").strip()
                if node_name in self.connected_nodes:
                    command = input("Enter PowerShell command: ").strip()
                    print(f"\n🚀 Executing on {node_name}...")
                    result = self.send_command(node_name, command)
                    print(f"\n📝 Result from {node_name}:\n{'-'*40}\n{result}\n{'-'*40}")
                else:
                    print("❌ Node not found!")
            
            elif choice == '2':
                if not self.connected_nodes:
                    print("❌ No workers connected!")
                    continue
                    
                command = input("Enter PowerShell command for ALL nodes: ").strip()
                print(f"\n🚀 Executing on {len(self.connected_nodes)} nodes...")
                results = self.run_command_all(command)
                
                for node, result in results.items():
                    print(f"\n📝 {node}:\n{'-'*40}\n{result}\n{'-'*40}")
            
            elif choice == '3':
                self.cleanup_dead_connections()
                print("✅ Connections refreshed")
            
            elif choice == '4':
                self.running = False
                print("👋 Goodbye!")
                break
            else:
                print("❌ Invalid choice!")

if __name__ == "__main__":
    controller = RenderFarmController()
    controller.menu()
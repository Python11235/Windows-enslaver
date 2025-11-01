REMOTE SHELL SETUP GUIDE
==========================

CONTROLLER SETUP (Your Machine)
--------------------------------

1. SET STATIC IP FOR YOUR LAPTOP:
   Open Command Prompt as Administrator and run:
   netsh interface ip set address "WLAN" static 192.168.0.100 255.255.255.0 192.168.0.1
   netsh interface ip set dns "WLAN" static 8.8.8.8

2. OPEN FIREWALL PORT:
   netsh advfirewall firewall add rule name="RenderFarm" dir=in action=allow protocol=TCP localport=8888

3. PORT FORWARDING ON ROUTER:
   - Access router: http://192.168.0.1
   - Login (admin/admin or admin/password)
   - Find Port Forwarding section
   - Add rule:
     Service: [you decide]
     External Port: 8888
     Internal Port: 8888
     Protocol: TCP
     Internal IP: 192.168.0.100
     Status: Enabled

4. START CONTROLLER:
   python Unlimited_cpu_controller.py (im sorry for the name it was 10pm)

WORKER SETUP (Render Nodes)
---------------------------

1. RUN INSTALLER:
   Double-click worker.bat on each render node
   - No admin rights required
   - Completely silent installation
   - Auto-starts on boot

2. VERIFY WORKER RUNNING:
   tasklist | findstr python

USING THE CONTROLLER
--------------------

Start controller: python controller.py

Menu Options:
1. Connect to specific node - Interactive PowerShell
2. Run command on single node - One command, one node
3. Run command on ALL nodes - Parallel execution
4. Refresh connections - Update status
5. Exit

Example Commands:
Get-Process | Where-Object {$_.ProcessName -like "*blender*"}
Get-WmiObject Win32_Processor | Measure-Object -Property LoadPercentage -Average
hostname
systeminfo | findstr /C:"Total Physical Memory"

MANAGEMENT COMMANDS
-------------------

Check worker status: tasklist | findstr python
Stop worker: taskkill /f /im python.exe
Restart worker: taskkill /f /im python.exe && timeout 2 && start worker_agent.py

TROUBLESHOOTING
---------------

Test port: telnet 84.115.217.201 8888
Online port test: www.yougetsignal.com/tools/open-ports/

Worker config location: %LOCALAPPDATA%\RenderFarmWorker\worker_config.json

If workers won't connect:
1. Verify controller is running
2. Check port 8888 shows as OPEN
3. Confirm firewall allows the port
4. Workers retry every 30 seconds automatically

SECURITY
--------

Change default secret key in controller and worker config
Use unique keys for different farms

NOTES
-----

- Workers auto-reconnect every 30 seconds if controller offline
- No windows or popups on worker machines
- Works across different networks
- No admin rights required on worker machines

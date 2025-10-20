#!/bin/bash
# Full deployment script for Pritunl VPN server with protected web application

set -e  # Stop on error

echo "=== Setting up Pritunl VPN server with protected web application ==="

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Run script as root: sudo $0"
    exit 1
fi

# Update system
echo "Updating system..."
apt update && apt upgrade -y

# Install required packages
echo "Installing required packages..."
apt install -y wget curl gnupg2 software-properties-common apt-transport-https ca-certificates nginx

# === INSTALL MONGODB ===
echo "Installing MongoDB..."
wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
apt update
apt install -y mongodb-org
systemctl start mongod
systemctl enable mongod

# === INSTALL PRITUNL ===
echo "Installing Pritunl..."
apt-key adv --keyserver hkp://keyserver.ubuntu.com --recv-keys 7568D9BB55FF9E5287D586017AE645C0CF8E292A
echo "deb http://repo.pritunl.com/stable/apt jammy main" | tee /etc/apt/sources.list.d/pritunl.list
apt update
apt install -y pritunl
systemctl start pritunl
systemctl enable pritunl

# === CONFIGURE NGINX ===
echo "Configuring Nginx..."

# Create directory for demo application
mkdir -p /var/www/demo-app

# Create demo HTML application
cat > /var/www/demo-app/index.html << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Demo App - VPN Protected</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: white;
            padding: 2rem;
            border-radius: 10px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            text-align: center;
            max-width: 500px;
            width: 90%;
        }
        h1 {
            color: #333;
            margin-bottom: 1rem;
        }
        .status {
            background: #4CAF50;
            color: white;
            padding: 1rem;
            border-radius: 5px;
            margin: 1rem 0;
        }
        .info {
            background: #f0f0f0;
            padding: 1rem;
            border-radius: 5px;
            margin: 1rem 0;
        }
        .vpn-icon {
            font-size: 3rem;
            margin-bottom: 1rem;
        }
        .features {
            text-align: left;
            margin: 1rem 0;
        }
        .feature {
            padding: 0.5rem 0;
            border-bottom: 1px solid #eee;
        }
        .feature:last-child {
            border-bottom: none;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="vpn-icon">🔒</div>
        <h1>Demo Application</h1>
        <div class="status">
            ✅ Access granted through VPN
        </div>
        <div class="info">
            <p><strong>Status:</strong> Connected to VPN</p>
            <p><strong>IP Address:</strong> <span id="client-ip">Loading...</span></p>
            <p><strong>Time:</strong> <span id="current-time"></span></p>
        </div>
        
        <div class="features">
            <h3>Application Features:</h3>
            <div class="feature">🔐 Secure access only through VPN</div>
            <div class="feature">📊 Connection monitoring</div>
            <div class="feature">🌐 Protected environment</div>
            <div class="feature">⚡ Fast response</div>
        </div>
        
        <p>This application is available only for users connected to VPN.</p>
    </div>

    <script>
        // Get client IP address
        fetch('https://api.ipify.org?format=json')
            .then(response => response.json())
            .then(data => {
                document.getElementById('client-ip').textContent = data.ip;
            })
            .catch(() => {
                document.getElementById('client-ip').textContent = 'Unable to determine';
            });

        // Update time
        function updateTime() {
            const now = new Date();
            document.getElementById('current-time').textContent = now.toLocaleString();
        }
        updateTime();
        setInterval(updateTime, 1000);
    </script>
</body>
</html>
HTML_EOF

# Create Nginx configuration
cat > /etc/nginx/sites-available/demo-app << 'NGINX_EOF'
server {
    listen 80;
    server_name _;
    
    # Restrict access only for VPN clients
    allow 127.0.0.1;
    allow 192.168.241.0/24;
    allow 172.16.0.0/12;
    allow 192.168.0.0/16;
    deny all;
    
    root /var/www/demo-app;
    index index.html;
    
    location / {
        try_files $uri $uri/ =404;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
    }
    
    # Special block for root path (avoids redirect loops)
    location = / {
        try_files /index.html =404;
    }
    
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    access_log /var/log/nginx/demo-app.access.log;
    error_log /var/log/nginx/demo-app.error.log;
}
NGINX_EOF

# Activate site
ln -sf /etc/nginx/sites-available/demo-app /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Check Nginx configuration
nginx -t

# Restart Nginx
systemctl restart nginx
systemctl enable nginx

# === CONFIGURE FIREWALL ===
echo "Configuring firewall..."

# Install UFW
apt install -y ufw

# Configure firewall rules
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# Allow SSH
ufw allow ssh

# Allow HTTPS for Pritunl
ufw allow 443

# Allow OpenVPN ports
ufw allow 1194

# Allow HTTP only for VPN subnet
ufw allow from 192.168.241.0/24 to any port 80
ufw allow from 127.0.0.1 to any port 80

# Block HTTP for external access
ufw deny 80

# Enable firewall
ufw --force enable

# === GET PRITUNL SETUP KEY ===
echo ""
echo "=== SETUP COMPLETED ==="
echo ""
echo "Pritunl setup key:"
pritunl setup-key
echo ""
echo "Open browser and go to: https://188.225.11.192/setup"
echo "Enter the setup key above to complete Pritunl configuration"
echo ""image.png
echo "After VPN setup:"
echo "1. Create organization and server in Pritunl"
echo "2. IMPORTANT: Set server port to 1194 (not 13517!)"
echo "3. Create users"
echo "4. Download .ovpn files"
echo "5. Connect to VPN"
echo "6. Open http://188.225.11.192 to access demo application"
echo ""
echo "⚠️  CRITICAL: Server port MUST be 1194 for clients to connect!"
echo ""
echo "Service status:"
systemctl status pritunl --no-pager -l
systemctl status nginx --no-pager -l
systemctl status mongod --no-pager -l

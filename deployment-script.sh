#!/bin/bash
# Полный скрипт развертывания Pritunl VPN сервера с защищенным веб-приложением

set -e  # Остановка при ошибке

echo "=== Настройка Pritunl VPN сервера с защищенным веб-приложением ==="

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo "Запустите скрипт с правами root: sudo $0"
    exit 1
fi

# Обновление системы
echo "Обновление системы..."
apt update && apt upgrade -y

# Установка необходимых пакетов
echo "Установка необходимых пакетов..."
apt install -y wget curl gnupg2 software-properties-common apt-transport-https ca-certificates nginx

# === УСТАНОВКА MONGODB ===
echo "Установка MongoDB..."
wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add -
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
apt update
apt install -y mongodb-org
systemctl start mongod
systemctl enable mongod

# === УСТАНОВКА PRITUNL ===
echo "Установка Pritunl..."
apt-key adv --keyserver hkp://keyserver.ubuntu.com --recv-keys 7568D9BB55FF9E5287D586017AE645C0CF8E292A
echo "deb http://repo.pritunl.com/stable/apt jammy main" | tee /etc/apt/sources.list.d/pritunl.list
apt update
apt install -y pritunl
systemctl start pritunl
systemctl enable pritunl

# === НАСТРОЙКА NGINX ===
echo "Настройка Nginx..."

# Создание директории для демо приложения
mkdir -p /var/www/demo-app

# Создание демо HTML приложения
cat > /var/www/demo-app/index.html << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Демо приложение - Защищено VPN</title>
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
        <h1>Демо приложение</h1>
        <div class="status">
            ✅ Доступ разрешен через VPN
        </div>
        <div class="info">
            <p><strong>Статус:</strong> Подключено к VPN</p>
            <p><strong>IP адрес:</strong> <span id="client-ip">Загрузка...</span></p>
            <p><strong>Время:</strong> <span id="current-time"></span></p>
        </div>
        
        <div class="features">
            <h3>Возможности приложения:</h3>
            <div class="feature">🔐 Безопасный доступ только через VPN</div>
            <div class="feature">📊 Мониторинг подключения</div>
            <div class="feature">🌐 Защищенная среда</div>
            <div class="feature">⚡ Быстрый отклик</div>
        </div>
        
        <p>Это приложение доступно только для пользователей, подключенных к VPN.</p>
    </div>

    <script>
        // Получение IP адреса клиента
        fetch('https://api.ipify.org?format=json')
            .then(response => response.json())
            .then(data => {
                document.getElementById('client-ip').textContent = data.ip;
            })
            .catch(() => {
                document.getElementById('client-ip').textContent = 'Не удалось определить';
            });

        // Обновление времени
        function updateTime() {
            const now = new Date();
            document.getElementById('current-time').textContent = now.toLocaleString('ru-RU');
        }
        updateTime();
        setInterval(updateTime, 1000);
    </script>
</body>
</html>
EOF

# Создание конфигурации Nginx
cat > /etc/nginx/sites-available/demo-app << 'EOF'
server {
    listen 80;
    server_name _;
    
    # Ограничение доступа только для VPN клиентов
    allow 10.0.0.0/8;
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
    
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    access_log /var/log/nginx/demo-app.access.log;
    error_log /var/log/nginx/demo-app.error.log;
}
EOF

# Активация сайта
ln -sf /etc/nginx/sites-available/demo-app /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Проверка конфигурации Nginx
nginx -t

# Перезапуск Nginx
systemctl restart nginx
systemctl enable nginx

# === НАСТРОЙКА ФАЙРВОЛА ===
echo "Настройка файрвола..."

# Установка UFW
apt install -y ufw

# Настройка правил файрвола
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# Разрешение SSH
ufw allow ssh

# Разрешение HTTPS для Pritunl
ufw allow 443

# Разрешение OpenVPN портов
ufw allow 1194

# Блокировка HTTP для внешнего доступа
ufw deny 80

# Включение файрвола
ufw --force enable

# === ПОЛУЧЕНИЕ КЛЮЧА НАСТРОЙКИ PRITUNL ===
echo ""
echo "=== НАСТРОЙКА ЗАВЕРШЕНА ==="
echo ""
echo "Ключ настройки Pritunl:"
pritunl setup-key
echo ""
echo "Откройте браузер и перейдите по адресу: https://188.225.11.192"
echo "Введите ключ настройки выше для завершения настройки Pritunl"
echo ""
echo "После настройки VPN:"
echo "1. Создайте организацию и сервер в Pritunl"
echo "2. Создайте пользователей"
echo "3. Скачайте .ovpn файлы"
echo "4. Подключитесь к VPN"
echo "5. Откройте http://188.225.11.192 для доступа к демо приложению"
echo ""
echo "Статус сервисов:"
systemctl status pritunl --no-pager -l
systemctl status nginx --no-pager -l
systemctl status mongod --no-pager -l

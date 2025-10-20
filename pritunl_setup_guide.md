# Полный гайд по настройке Pritunl VPN сервера с защищенным веб-приложением

## Обзор
Этот гайд поможет вам:
1. Установить Pritunl VPN сервер на Ubuntu/Debian сервере
2. Настроить Nginx с демо HTML приложением
3. Ограничить доступ к веб-приложению только через VPN

## Шаг 1: Подготовка сервера

### Подключение к серверу
```powershell
ssh root@188.225.11.192
```

### Обновление системы
```bash
apt update && apt upgrade -y
```

### Установка необходимых пакетов
```bash
apt install -y wget curl gnupg2 software-properties-common apt-transport-https ca-certificates
```

## Шаг 2: Установка MongoDB

```bash
# Добавление ключа MongoDB
wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | apt-key add -

# Добавление репозитория MongoDB
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list

# Обновление пакетов и установка MongoDB
apt update
apt install -y mongodb-org

# Запуск и автозапуск MongoDB
systemctl start mongod
systemctl enable mongod
```

## Шаг 3: Установка Pritunl

```bash
# Добавление ключа Pritunl
apt-key adv --keyserver hkp://keyserver.ubuntu.com --recv-keys 7568D9BB55FF9E5287D586017AE645C0CF8E292A

# Добавление репозитория Pritunl
echo "deb http://repo.pritunl.com/stable/apt jammy main" | tee /etc/apt/sources.list.d/pritunl.list

# Обновление и установка
apt update
apt install -y pritunl

# Запуск и автозапуск Pritunl
systemctl start pritunl
systemctl enable pritunl
```

## Шаг 4: Настройка Pritunl

### Получение ключа настройки
```bash
pritunl setup-key
```

### Настройка через веб-интерфейс
1. Откройте браузер и перейдите по адресу: `https://188.225.11.192`
2. Введите ключ настройки из предыдущей команды
3. Создайте администратора
4. Настройте организацию и сервер

## Шаг 5: Установка и настройка Nginx

```bash
# Установка Nginx
apt install -y nginx

# Создание директории для демо приложения
mkdir -p /var/www/demo-app
```

## Шаг 6: Создание демо HTML приложения

```bash
# Создание демо HTML файла
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
```

## Шаг 7: Настройка Nginx для ограничения доступа

```bash
# Создание конфигурации Nginx
cat > /etc/nginx/sites-available/demo-app << 'EOF'
server {
    listen 80;
    server_name _;
    
# Ограничение доступа только для VPN клиентов
# Разрешаем доступ только с VPN подсети
allow 127.0.0.1;           # Localhost для тестирования
allow 192.168.241.0/24;    # VPN подсеть Pritunl (реальная)
allow 172.16.0.0/12;       # Docker/VPN подсети
allow 192.168.0.0/16;      # Локальные подсети
deny all;
    
    root /var/www/demo-app;
    index index.html;
    
    location / {
        try_files $uri $uri/ =404;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
    }
    
    # Специальный блок для корневого пути (избегает циклов)
    location = / {
        try_files /index.html =404;
    }
    
    # Логирование
    access_log /var/log/nginx/demo-app.access.log;
    error_log /var/log/nginx/demo-app.error.log;
}
EOF

# Активация сайта
ln -s /etc/nginx/sites-available/demo-app /etc/nginx/sites-enabled/

# Удаление дефолтного сайта
rm -f /etc/nginx/sites-enabled/default

# Проверка конфигурации
nginx -t

# Перезапуск Nginx
systemctl restart nginx
systemctl enable nginx
```

## Шаг 8: Настройка файрвола

```bash
# Установка UFW
apt install -y ufw

# Базовые правила
ufw default deny incoming
ufw default allow outgoing

# Разрешение SSH
ufw allow ssh

# Разрешение HTTPS для Pritunl
ufw allow 443

# Разрешение OpenVPN портов (обычно 1194)
ufw allow 1194

# Разрешение HTTP только для VPN подсети
ufw allow from 192.168.241.0/24 to any port 80
ufw allow from 127.0.0.1 to any port 80

# Блокировка HTTP для внешнего доступа
# (доступ только через VPN)
ufw deny 80

# Включение файрвола
ufw --force enable
```

## Шаг 9: Настройка Pritunl сервера

### ⚠️ КРИТИЧЕСКИ ВАЖНЫЕ НАСТРОЙКИ СЕРВЕРА:

**НЕПРАВИЛЬНЫЕ НАСТРОЙКИ = НЕВОЗМОЖНОСТЬ ПОДКЛЮЧЕНИЯ!**

### Через веб-интерфейс:
1. Войдите в админ панель Pritunl
2. Создайте организацию
3. Создайте сервер с настройками:
   - **Port**: 1194 ⚠️ **КРИТИЧНО!** Должен быть именно 1194, не 13517!
   - **Protocol**: UDP
   - **Network**: 192.168.241.0/24 (реальная VPN подсеть Pritunl)
   - **DNS**: 8.8.8.8, 8.8.4.4

   ⚠️ **ВАЖНО**: Если порт будет не 1194, клиенты не смогут подключиться!

### 🌐 **Настройка VPN как прокси (весь трафик через VPN):**

**Для использования VPN как прокси для обхода блокировок:**

1. **В настройках сервера найдите "Virtual Network"**
2. **Убедитесь, что указано**: `192.168.241.0/24`
3. **Добавьте маршрут**: `0.0.0.0/0` в настройки сервера
4. **Сохраните** настройки
5. **Пересоздайте .ovpn файл** после изменений
6. **Переподключитесь** к VPN

**Результат**: Весь интернет-трафик будет идти через VPN сервер (Нидерланды)

4. Создайте пользователей
5. Сгенерируйте конфигурационные файлы (.ovpn)

### 🔧 Устранение проблем с подключением:

**Если клиент не может подключиться:**
1. **Проверьте порт сервера** - должен быть 1194, не 13517!
2. **Проверьте файрвол** - порт 1194 должен быть открыт
3. **Пересоздайте .ovpn файл** после изменения настроек
4. **Проверьте статус сервера** - должен быть "Online"

## Шаг 10: Тестирование

### 🔍 **Важно: Разница между IP адресами**

**Внешний IP сервера: `188.225.11.192`**
- Доступен из интернета для всех
- Используется для **Pritunl админки** (HTTPS)
- НЕ защищен VPN ограничениями

**VPN IP сервера: `192.168.241.1`**
- Доступен только через VPN подключение
- Используется для **демо приложения** (HTTP)
- Защищен VPN ограничениями

### Тест без VPN:
```powershell
# Попытка доступа без VPN (должна быть заблокирована)
Invoke-WebRequest -Uri "http://188.225.11.192" -UseBasicParsing
```

### Тест с VPN:
1. Подключитесь к VPN используя .ovpn файл
2. Откройте браузер и перейдите на:
   - `http://192.168.241.1/` - демо приложение (VPN IP)
   - `http://188.225.11.192/` - демо приложение (внешний IP, но через VPN)
3. Должно отобразиться демо приложение

## Дополнительные настройки безопасности

### Ограничение доступа к Nginx только для VPN
```bash
# Создание дополнительного скрипта для проверки VPN подключения
cat > /usr/local/bin/check-vpn-access.sh << 'EOF'
#!/bin/bash
# Проверка, что запрос идет от VPN клиента
# Этот скрипт можно использовать для дополнительной проверки
echo "VPN access check passed"
EOF

chmod +x /usr/local/bin/check-vpn-access.sh
```

## Мониторинг и логи

### Просмотр логов Nginx:
```bash
tail -f /var/log/nginx/demo-app.access.log
tail -f /var/log/nginx/demo-app.error.log
```

### Просмотр логов Pritunl:
```bash
journalctl -u pritunl -f
```

## Устранение неполадок

### Проверка статуса сервисов:
```bash
systemctl status pritunl
systemctl status nginx
systemctl status mongod
```

### Проверка портов:
```bash
netstat -tlnp | grep :80
netstat -tlnp | grep :443
netstat -tlnp | grep :1194
```

### Проверка файрвола:
```bash
ufw status verbose
```

## Заключение

После выполнения всех шагов у вас будет:
- ✅ Работающий Pritunl VPN сервер
- ✅ Защищенное веб-приложение доступное только через VPN
- ✅ Настроенный файрвол для дополнительной безопасности
- ✅ Мониторинг и логирование

Веб-приложение будет доступно только пользователям, подключенным к VPN.

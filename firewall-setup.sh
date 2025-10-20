#!/bin/bash
# Скрипт настройки файрвола для защиты веб-приложения

echo "Настройка файрвола для защиты веб-приложения..."

# Установка UFW если не установлен
if ! command -v ufw &> /dev/null; then
    echo "Установка UFW..."
    apt update
    apt install -y ufw
fi

# Сброс всех правил
ufw --force reset

# Базовые правила
echo "Настройка базовых правил..."
ufw default deny incoming
ufw default allow outgoing

# Разрешение SSH (важно сделать это первым!)
echo "Разрешение SSH доступа..."
ufw allow ssh
ufw allow 22/tcp

# Разрешение HTTPS для Pritunl админ панели
echo "Разрешение HTTPS для Pritunl..."
ufw allow 443/tcp

# Разрешение OpenVPN портов
echo "Разрешение OpenVPN портов..."
ufw allow 1194/udp
ufw allow 1194/tcp

# Дополнительные порты для Pritunl (если используются)
ufw allow 970/tcp
ufw allow 971/tcp

# Разрешение HTTP только для VPN подсети
echo "Настройка доступа к HTTP..."
ufw allow from 192.168.241.0/24 to any port 80
ufw allow from 127.0.0.1 to any port 80

# Блокировка HTTP для внешнего доступа
# (доступ только через VPN)
echo "Блокировка HTTP для внешнего доступа..."
ufw deny 80/tcp

# Включение файрвола
echo "Включение файрвола..."
ufw --force enable

# Показ статуса
echo "Статус файрвола:"
ufw status verbose

echo "Файрвол настроен успешно!"
echo "HTTP (порт 80) заблокирован для внешнего доступа"
echo "Доступ к веб-приложению возможен только через VPN"

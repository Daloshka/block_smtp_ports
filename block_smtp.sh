#!/bin/bash


# список портов
PORTS="25 465 587 110 995 143 993 2525 2465 2587 10025 8025 25025 24"

echo "[*] Проверка наличия iptables и ip6tables..."
if ! command -v iptables >/dev/null 2>&1; then
    echo "[*] iptables не найден, устанавливаю..."
    sudo apt update && sudo apt install -y iptables
else
    echo "[*] iptables уже установлен."
fi

if ! command -v ip6tables >/dev/null 2>&1; then
    echo "[*] ip6tables не найден, устанавливаю..."
    sudo apt update && sudo apt install -y iptables
else
    echo "[*] ip6tables уже установлен."
fi

echo "[*] Проверка и блокировка портов (IPv4 + IPv6)..."
for port in $PORTS; do
    # IPv4
    if sudo iptables -C OUTPUT -p tcp --dport $port -j DROP 2>/dev/null; then
        echo "  - IPv4: Порт $port уже блокирован (OUTPUT)"
    else
        echo "  - IPv4: Блокирую порт $port (OUTPUT)"
        sudo iptables -A OUTPUT -p tcp --dport $port -j DROP
    fi
    if sudo iptables -C INPUT -p tcp --dport $port -j DROP 2>/dev/null; then
        echo "  - IPv4: Порт $port уже блокирован (INPUT)"
    else
        echo "  - IPv4: Блокирую порт $port (INPUT)"
        sudo iptables -A INPUT -p tcp --dport $port -j DROP
    fi

    # IPv6
    if sudo ip6tables -C OUTPUT -p tcp --dport $port -j DROP 2>/dev/null; then
        echo "  - IPv6: Порт $port уже блокирован (OUTPUT)"
    else
        echo "  - IPv6: Блокирую порт $port (OUTPUT)"
        sudo ip6tables -A OUTPUT -p tcp --dport $port -j DROP
    fi
    if sudo ip6tables -C INPUT -p tcp --dport $port -j DROP 2>/dev/null; then
        echo "  - IPv6: Порт $port уже блокирован (INPUT)"
    else
        echo "  - IPv6: Блокирую порт $port (INPUT)"
        sudo ip6tables -A INPUT -p tcp --dport $port -j DROP
    fi
done

echo "[*] Установка iptables-persistent для сохранения правил..."
if ! dpkg -l | grep -q iptables-persistent; then
    echo "[*] Устанавливаю iptables-persistent..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent
else
    echo "[*] iptables-persistent уже установлен."
fi

echo "[*] Сохранение правил..."
sudo netfilter-persistent save

echo "[*] Готово! Правила IPv4 и IPv6 заблокированы и сохранятся после перезагрузки."

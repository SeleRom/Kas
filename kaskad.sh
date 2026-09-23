cat << 'EOF' > ~/kaskad.sh
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; WHITE='\033[1;37m'; NC='\033[0m'
check_root() { [ "$EUID" -ne 0 ] && echo -e "${RED}Запустите через sudo!${NC}" && exit 1; }
check_persistence() {
    echo -ne "${YELLOW}[*] Автозагрузка: ${NC}"
    systemctl is-active --quiet netfilter-persistent && echo -e "${GREEN}ОК${NC}" || echo -e "${RED}НЕТ (исправится при настройке)${NC}"
}
prepare_system() {
    [ "$0" != "/usr/local/bin/gokaskad" ] && cp -f "$0" "/usr/local/bin/gokaskad" && chmod +x "/usr/local/bin/gokaskad"
    grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p > /dev/null
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y > /dev/null && apt-get install -y iptables-persistent netfilter-persistent > /dev/null
    systemctl enable netfilter-persistent > /dev/null
}
apply_iptables_rules() {
    local PROTO=$1; local IN_PORT=$2; local OUT_PORT=$3; local TARGET_IP=$4
    IFACE=$(ip route get 8.8.8.8 | awk '{print $5}')
    iptables -t nat -D PREROUTING -p "$PROTO" --dport "$IN_PORT" -j DNAT --to-destination "$TARGET_IP:$OUT_PORT" 2>/dev/null
    iptables -D INPUT -p "$PROTO" --dport "$IN_PORT" -j ACCEPT 2>/dev/null
    iptables -A INPUT -p "$PROTO" --dport "$IN_PORT" -j ACCEPT
    iptables -t nat -A PREROUTING -p "$PROTO" --dport "$IN_PORT" -j DNAT --to-destination "$TARGET_IP:$OUT_PORT"
    iptables -t nat -C POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
    iptables -A FORWARD -p "$PROTO" -d "$TARGET_IP" --dport "$OUT_PORT" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
    iptables -A FORWARD -p "$PROTO" -s "$TARGET_IP" --sport "$OUT_PORT" -m state --state ESTABLISHED,RELATED -j ACCEPT
    netfilter-persistent save > /dev/null
    echo -e "${GREEN}[SUCCESS] Готово!${NC}"; read -p "Enter..."
}
while true; do
    clear; echo -e "${WHITE}=== КАСКАДНЫЙ МОСТ (CLEAN) ===${NC}"; check_persistence; echo "-----------------------"
    echo -e "1) AmneziaWG (UDP)\n2) VLESS/XRay (TCP)\n3) Кастомное правило\n4) Активные правила\n5) Сброс\n0) Выход"
    read -p "Выбор: " c
    case $c in
        1) read -p "IP цели: " i; read -p "Порт: " p; apply_iptables_rules "udp" "$p" "$p" "$i" ;;
        2) read -p "IP цели: " i; read -p "Порт: " p; apply_iptables_rules "tcp" "$p" "$p" "$i" ;;
        3) read -p "Протокол: " pr; read -p "IP цели: " i; read -p "Вход порт: " ip; read -p "Выход порт: " op; apply_iptables_rules "$pr" "$ip" "$op" "$i" ;;
        4) iptables -t nat -S PREROUTING | grep "DNAT"; read -p "Enter..." ;;
        5) iptables -F; iptables -t nat -F; netfilter-persistent save; echo "Сброшено"; sleep 1 ;;
        0) exit 0 ;;
    esac
done
EOF
chmod +x ~/kaskad.sh
sudo ~/kaskad.sh

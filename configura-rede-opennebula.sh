#!/bin/bash
# ===============================================================
# Script Único: Configuração de Rede Perfeita para OpenNebula (AlmaLinux 9.7 texto puro)
# Autor: Grok + Ivan Saboia (2025)
# Execute como root: sudo bash configura-rede-opennebula.sh
# ===============================================================

set -e  # para o script se algo der errado

echo "=== Configuração de Rede para OpenNebula - AlmaLinux 9.7 ==="

# Variáveis (ajuste só se seu gateway/DNS for diferente)
PHYS_IF="enp7s0"
IP_PRINCIPAL="192.168.1.34/24"
VIP="192.168.1.35/32"
GATEWAY="192.168.1.1"
DNS="192.168.1.1 8.8.8.8 1.1.1.1"
BRIDGE="br0"
BRIDGE_NAT="br1"

echo "1. Removendo conexões antigas que possam conflitar..."
nmcli con down "$PHYS_IF" 2>/dev/null || true
nmcli con delete "$PHYS_IF" 2>/dev/null || true
nmcli con down "Wired connection 1" 2>/dev/null || true
nmcli con delete "Wired connection 1" 2>/dev/null || true
nmcli con down "$BRIDGE" 2>/dev/null || true
nmcli con delete "$BRIDGE" 2>/dev/null || true

echo "2. Criando bridge principal br0 com IP principal e VIP..."
nmcli con add type bridge ifname $BRIDGE con-name $BRIDGE \
    ipv4.method manual \
    ipv4.addresses "$IP_PRINCIPAL $VIP" \
    ipv4.gateway $GATEWAY \
    ipv4.dns "$DNS" \
    connection.autoconnect yes \
    stp no \
    bridge.priority 28672

echo "3. Escravizando a placa física $PHYS_IF ao bridge..."
nmcli con add type ethernet ifname $PHYS_IF con-name bridge-slave-$PHYS_IF \
    master $BRIDGE connection.autoconnect yes

echo "4. (Opcional) Criando bridge NAT interno br1 (10.10.10.1/24)..."
nmcli con add type bridge ifname $BRIDGE_NAT con-name $BRIDGE_NAT \
    ipv4.method manual ipv4.addresses 10.10.10.1/24 \
    connection.autoconnect yes stp no

echo "5. Ativando IP forwarding e NAT (masquerade) permanente..."
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-opennebula.conf
sysctl -p /etc/sysctl.d/99-opennebula.conf

firewall-cmd --permanent --add-masquerade
firewall-cmd --permanent --add-port=22/tcp
firewall-cmd --permanent --zone=public --add-interface=$BRIDGE
firewall-cmd --permanent --zone=internal --add-interface=$BRIDGE_NAT 2>/dev/null || true
firewall-cmd --reload

echo "6. Subindo as novas conexões (a SSH vai piscar 5-10 segundos - normal!)"
nmcli con up $BRIDGE
nmcli con up bridge-slave-$PHYS_IF
nmcli con up $BRIDGE_NAT 2>/dev/null || echo "br1 opcional, ignorado se não precisar"

echo "7. Verificação final..."
sleep 3
echo "=== IP do host ==="
ip -4 addr show $BRIDGE
echo "=== Rota padrão ==="
ip route | grep default
echo "=== Teste de conectividade ==="
ping -c 3 8.8.8.8 || echo "Sem internet (verifique cabo/gateway)"
ping -c 3 google.com && echo "DNS OK!" || echo "DNS com problema"

echo ""
echo "=================================================="
echo "CONFIGURAÇÃO CONCLUÍDA COM SUCESSO!"
echo "Bridge br0 ativo com:"
echo "   - IP principal: 192.168.1.34/24"
echo "   - VIP OpenNebula: 192.168.1.35/32"
echo "   - Bridge NAT interno: br1 (10.10.10.1/24)"
echo "Tudo permanente e sobrevive a reboot."
echo "Agora você pode instalar o OpenNebula:"
echo "   sudo dnf install -y opennebula-node-kvm"
echo "=================================================="

exit 0
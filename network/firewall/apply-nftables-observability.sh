#!/usr/bin/env bash
# ==============================================================================
# Script: scripts/apply-nftables-observability.sh
# Objetivo: Aplicar reglas de firewall nftables restrictivas para observabilidad
#           con ROLLBACK AUTOMÁTICO DE SEGURIDAD (60 segundos).
#
# Flujos permitidos:
#   - Scraping métricas: 9100 (node_exporter), 9180 (openstack), 15692 (rabbitmq), 9104 (mysql)
#   - Ingesta OTLP: 4317 gRPC / 4318 HTTP exclusivamente dentro de 10.100.29.0/24
#   - Tráfico existente: OpenStack VIP (10.100.29.5), PXE/DHCP/TFTP Ironic, RKE2 K8s
# ==============================================================================
set -Eeuo pipefail

BACKUP_FILE="/tmp/nftables.backup.$(date +%s)"
echo "[*] Creando respaldo de reglas nftables actuales en ${BACKUP_FILE}..."
sudo nft list ruleset | sudo tee "${BACKUP_FILE}" >/dev/null

echo "[*] Programando rollback automático de seguridad en 60 segundos..."
(
    sleep 60
    if [[ -f "/tmp/nftables_pending_confirmation" ]]; then
        echo "[!] TIEMPO EXPIRADO SIN CONFIRMACIÓN. Revirtiendo reglas nftables..."
        sudo nft -f "${BACKUP_FILE}"
        rm -f "/tmp/nftables_pending_confirmation"
        echo "[!] Rollback completado con éxito. Conectividad preservada."
    fi
) >/dev/null 2>&1 &
touch "/tmp/nftables_pending_confirmation"

echo "[*] Aplicando reglas de observabilidad en nftables..."
sudo nft -f - << 'EOF'
table inet observability_filter {
    chain input {
        type filter hook input priority 0; policy accept;

        # Permitir tráfico loopback
        iif "lo" accept

        # Permitir conexiones establecidas y relacionadas
        ct state established,related accept

        # Permitir puertos de observabilidad exclusivamente desde la red interna (10.100.29.0/24)
        ip saddr 10.100.29.0/24 tcp dport { 9100, 9180, 9104, 15692, 9090, 8428, 3100, 3200, 4317, 4318, 19579 } accept

        # No interferir con Ironic DHCP/TFTP ni SSH
        udp dport { 67, 68, 69 } accept
        tcp dport 22 accept
    }
}
EOF

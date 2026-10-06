#!/usr/bin/env bash
# ==============================================================================
# ROLLBACK 04: REVERSIÓN DE CLIENTES NEXUS (rollback-04-clientes-nexus.sh)
# Objetivo: Restaurar fuentes APT originales de Debian y remover proxy y mirrors
# Nodo de Ejecución: [CLIENTES 3 AL 8]
# Uso: sudo ./rollback-04-clientes-nexus.sh [-y]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

parse_common_flags "$@"
require_root

echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"
echo -e "${COLOR_YELLOW}   ROLLBACK: REVIRTIENDO FASE 4 (CLIENTES APT Y REGISTROS)        ${COLOR_NC}"
echo -e "${COLOR_YELLOW}==================================================================${COLOR_NC}"

confirm_action "¿Está seguro de restablecer las fuentes APT a los repositorios oficiales de Debian?"

# 1. Restaurar /etc/apt/sources.list
LATEST_SOURCES_BAK=$(ls -t /etc/apt/sources.list.bak.* 2>/dev/null | head -n1 || true)
if [[ -n "${LATEST_SOURCES_BAK}" ]]; then
    log_info "Restaurando sources.list desde: ${LATEST_SOURCES_BAK}"
    cp -a "${LATEST_SOURCES_BAK}" /etc/apt/sources.list
else
    log_info "Configurando sources.list predeterminado de Debian Trixie..."
    cat > /etc/apt/sources.list << 'EOF'
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
EOF
fi

# 2. Remover registros de RKE2
rm -f /etc/rancher/rke2/registries.yaml

# 3. Limpiar variables de proxy en /etc/environment
sed -i '/_proxy=/d' /etc/environment 2>/dev/null || true

log_success "Reversión de Fase 4 completada."

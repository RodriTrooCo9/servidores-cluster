#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE REVERSIÓN: RESTAURAR BINARIOS iPXE ORIGINALES
# (rollback/rollback-compilar-ipxe-custom.sh)
# Objetivo: Revertir /tftpboot/ipxe.efi y undionly.kpxe a sus versiones previas
# Uso: sudo ./rollback/rollback-compilar-ipxe-custom.sh [--dry-run] [-y]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Cargar biblioteca común
if [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
    source "${SCRIPT_DIR}/lib/common.sh"
elif [[ -f "${REPO_DIR}/lib/common.sh" ]]; then
    source "${REPO_DIR}/lib/common.sh"
else
    echo "ERROR: No se encontró lib/common.sh" >&2
    exit 1
fi

parse_common_flags "$@"
require_root

echo -e "${COLOR_RED}==================================================================${COLOR_NC}"
echo -e "${COLOR_RED}   REVERSIÓN DE BINARIOS iPXE EN PRODUCCIÓN (/tftpboot)           ${COLOR_NC}"
echo -e "${COLOR_RED}==================================================================${COLOR_NC}"

confirm_action "¿Está seguro de que desea restaurar los binarios originales de APT en /tftpboot?"

TFTP_DIR="/tftpboot"
BACKUPS_DIR="/opt/ipxe-staging/backups"

RESTORED=false

# 1. Intentar restaurar desde respaldo original de staging
if [[ -f "${BACKUPS_DIR}/ipxe.efi.original.bak" ]]; then
    log_info "Restaurando desde respaldo en ${BACKUPS_DIR}/ipxe.efi.original.bak..."
    run_cmd cp -f "${BACKUPS_DIR}/ipxe.efi.original.bak" "${TFTP_DIR}/ipxe.efi"
    RESTORED=true
fi

if [[ -f "${BACKUPS_DIR}/undionly.kpxe.original.bak" ]]; then
    log_info "Restaurando desde respaldo en ${BACKUPS_DIR}/undionly.kpxe.original.bak..."
    run_cmd cp -f "${BACKUPS_DIR}/undionly.kpxe.original.bak" "${TFTP_DIR}/undionly.kpxe"
    RESTORED=true
fi

# 2. Si no había respaldo en staging, restaurar desde paquete del sistema operativo
if [[ "${RESTORED}" = false ]]; then
    log_warn "No se encontraron respaldos en ${BACKUPS_DIR}. Restaurando desde paquete oficial /usr/lib/ipxe/..."
    if [[ -f /usr/lib/ipxe/ipxe.efi ]]; then
        run_cmd cp -f /usr/lib/ipxe/ipxe.efi "${TFTP_DIR}/ipxe.efi"
    elif [[ -f /usr/lib/ipxe/ipxe-x86_64.efi ]]; then
        run_cmd cp -f /usr/lib/ipxe/ipxe-x86_64.efi "${TFTP_DIR}/ipxe.efi"
    fi

    if [[ -f /usr/lib/ipxe/undionly.kpxe ]]; then
        run_cmd cp -f /usr/lib/ipxe/undionly.kpxe "${TFTP_DIR}/undionly.kpxe"
    fi
fi

# 3. Ajuste de permisos
if [[ "${DRY_RUN}" = false ]]; then
    chown tftp:tftp "${TFTP_DIR}/ipxe.efi" "${TFTP_DIR}/undionly.kpxe" 2>/dev/null || chown nobody:nogroup "${TFTP_DIR}/ipxe.efi" "${TFTP_DIR}/undionly.kpxe" 2>/dev/null || true
    chmod 0644 "${TFTP_DIR}/ipxe.efi" "${TFTP_DIR}/undionly.kpxe" 2>/dev/null || true
fi

log_success "Reversión completada. Binarios originales restablecidos en ${TFTP_DIR}."
ls -lh "${TFTP_DIR}/ipxe.efi" "${TFTP_DIR}/undionly.kpxe" 2>/dev/null || true

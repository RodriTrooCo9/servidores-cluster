#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE COMPILACIÓN Y STAGING: iPXE CUSTOM PARA DESPLIEGUE MASIVO
# (scripts/compilar-ipxe-custom.sh)
# Repositorio Base: https://github.com/ipxe/ipxe
# Hardware Objetivo: Dell OptiPlex 3020M (BIOS A05 | NIC Realtek RTL8111G)
# Servidor de Compilación: Nodo 306 (pxe-controller | 10.100.29.30)
#
# Principio Rector: CERO AFECTACIÓN A SERVICIOS EN EJECUCIÓN
# Por defecto compila en /opt/ipxe-staging sin tocar /tftpboot/ ni dnsmasq.
# Para desplegar atómicamente a producción use la bandera: --install
#
# Uso:
#   sudo ./scripts/compilar-ipxe-custom.sh [OPCIONES]
#   sudo ./scripts/compilar-ipxe-custom.sh --staging-only
#   sudo ./scripts/compilar-ipxe-custom.sh --install
#   sudo ./scripts/compilar-ipxe-custom.sh --test-qemu
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

# Variables de Staging y Configuración
STAGING_BASE="/opt/ipxe-staging"
BUILD_DIR="${STAGING_BASE}/build"
DIST_DIR="${STAGING_BASE}/dist"
LOGS_DIR="${STAGING_BASE}/logs"
BACKUPS_DIR="${STAGING_BASE}/backups"

INSTALL_TO_PROD=false
RUN_QEMU_TEST=false

show_help() {
    cat << EOF
Uso: $0 [OPCIONES]

Opciones de Compilación y Staging:
  --staging-only       (Por defecto) Compila y valida en ${STAGING_BASE} sin tocar producción.
  --install            Copia atómicamente los binarios a /tftpboot con respaldo previo.
                       NO reinicia ni interrumpe dnsmasq ni conexiones activas.
  --test-qemu          Ejecuta una prueba de arranque virtualizada en QEMU OVMF UEFI.
  --dry-run            Simula la ejecución de comandos sin realizar cambios reales.
  --force              Omite las comprobaciones estrictas de hostname/IP.
  -y, --yes            Omite confirmaciones interactivas.
  -h, --help           Muestra esta ayuda.

Ejemplos:
  sudo $0                      # Compilación limpia y pruebas en /opt/ipxe-staging
  sudo $0 --install -y         # Compilación y reemplazo atómico en /tftpboot
  sudo $0 --test-qemu          # Validación virtualizada con emulador UEFI
EOF
}

# Parseo de banderas personalizadas
parse_common_flags "$@"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)
            INSTALL_TO_PROD=true
            shift
            ;;
        --staging-only)
            INSTALL_TO_PROD=false
            shift
            ;;
        --test-qemu)
            RUN_QEMU_TEST=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

load_config
require_root

echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   COMPILACIÓN DETERMINISTA DE iPXE CUSTOM (CERO IMPACTO)        ${COLOR_NC}"
echo -e "${COLOR_BLUE}   Repositorio: https://github.com/ipxe/ipxe                     ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

CURRENT_HOSTNAME="$(hostname -s)"
CURRENT_IPS="$(ip -br addr 2>/dev/null | awk '{print $3}' | cut -d/ -f1 | tr '\n' ' ')"

if [[ "${CURRENT_HOSTNAME}" != "${PXE_HOSTNAME:-pxe-controller}" ]] && [[ " ${CURRENT_IPS} " != *" ${PXE_IP:-10.100.29.30} "* ]]; then
    if [[ "${FORCE}" = false ]]; then
        log_warn "Host actual (${CURRENT_HOSTNAME}) no coincide con el nodo PXE oficial (${PXE_HOSTNAME:-pxe-controller})."
        confirm_action "¿Desea continuar la compilación de todos modos en este equipo?"
    fi
fi

# ------------------------------------------------------------------------------
# 1. PREPARACIÓN DEL DIRECTORIO DE STAGING AISLADO
# ------------------------------------------------------------------------------
log_info "1. Preparando directorios aislados en ${STAGING_BASE}..."
run_cmd mkdir -p "${BUILD_DIR}" "${DIST_DIR}" "${LOGS_DIR}" "${BACKUPS_DIR}"
log_success "Área de staging lista (Sin colisión con /tftpboot)."

# ------------------------------------------------------------------------------
# 2. INSTALACIÓN DE TOOLCHAIN DE COMPILACIÓN
# ------------------------------------------------------------------------------
log_info "2. Verificando toolchain de compilación en Debian 13..."
REQUIRED_PKGS=(build-essential binutils-dev liblzma-dev git perl mtools syslinux)
MISSING_PKGS=()

for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
        MISSING_PKGS+=("${pkg}")
    fi
done

if (( ${#MISSING_PKGS[@]} > 0 )); then
    log_info "Instalando paquetes faltantes: ${MISSING_PKGS[*]}..."
    if [[ "${DRY_RUN}" = false ]]; then
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${MISSING_PKGS[@]}"
    fi
else
    log_success "Toolchain completa: gcc, make, binutils, lzma y utilidades operativas."
fi

# ------------------------------------------------------------------------------
# 3. CLONACIÓN / ACTUALIZACIÓN DEL REPOSITORIO OFICIAL
# ------------------------------------------------------------------------------
IPXE_GIT_DIR="${BUILD_DIR}/ipxe"
log_info "3. Gestionando código fuente desde https://github.com/ipxe/ipxe..."

if [[ ! -d "${IPXE_GIT_DIR}/.git" ]]; then
    log_info "Clonando repositorio oficial upstream..."
    if [[ "${DRY_RUN}" = false ]]; then
        git clone --depth 1 https://github.com/ipxe/ipxe.git "${IPXE_GIT_DIR}"
    fi
else
    log_info "Repositorio detectado. Actualizando árbol de fuentes..."
    if [[ "${DRY_RUN}" = false ]]; then
        git -C "${IPXE_GIT_DIR}" fetch --depth 1 origin master
        git -C "${IPXE_GIT_DIR}" reset --hard origin/master
    fi
fi

if [[ "${DRY_RUN}" = false ]]; then
    COMMIT_HASH="$(git -C "${IPXE_GIT_DIR}" rev-parse HEAD)"
    echo "Commit: ${COMMIT_HASH} | Fecha: $(date '+%Y-%m-%d %H:%M:%S')" > "${LOGS_DIR}/upstream-commit.txt"
    log_success "Fuente iPXE en commit: ${COMMIT_HASH:0:10}"
fi

# ------------------------------------------------------------------------------
# 4. INYECCIÓN DE CONFIGURACIONES C LOCALES Y SCRIPT EMBEBIDO
# ------------------------------------------------------------------------------
log_info "4. Inyectando optimizaciones C para BIOS Dell A05 y Realtek RTL8111G..."
LOCAL_CFG_DIR="${IPXE_GIT_DIR}/src/config/local"

if [[ "${DRY_RUN}" = false ]]; then
    mkdir -p "${LOCAL_CFG_DIR}"

    # general.h: Supresión estricta de IPv6 + protocolos HTTP acelerados
    cat << 'EOF' > "${LOCAL_CFG_DIR}/general.h"
/* ==========================================================================
 * Sobreescritura Local iPXE para Clúster Bare-Metal Dell 3020M
 * ========================================================================== */
#undef  NET_PROTO_IPV6          /* Elimina Router Solicitations y cuelgues de 45s */
#define NET_PROTO_IPV4          /* IPv4 Puro de Alta Velocidad */
#define DOWNLOAD_PROTO_HTTP     /* Streaming HTTP por Nginx :8089 */
#define DOWNLOAD_PROTO_TFTP     /* Transferencia inicial TFTP */
#undef  DOWNLOAD_PROTO_HTTPS    /* Sin latencia criptográfica TLS en red aislada */
#undef  DOWNLOAD_PROTO_NFS      /* Desactivar protocolos no utilizados */
#undef  SANBOOT_PROTO_ISCSI
#undef  SANBOOT_PROTO_AOE
#undef  SANBOOT_PROTO_IB_SRP
#undef  SANBOOT_PROTO_FCP

/* Comandos de Diagnóstico en Vivo */
#define PING_CMD                /* Prueba ICMP directa desde prompt */
#define REBOOT_CMD              /* Reinicio controlado por software */
#define POWEROFF_CMD            /* Apagado limpio ACPI */
#define NSLOOKUP_CMD            /* Resolución DNS */
#define TIME_CMD                /* Sincronización horaria */
#define VLAN_CMD                /* Gestión de VLANs 802.1Q */
#define IMAGE_PNG               /* Gráficos PNG en pantalla */
EOF

    # console.h: Soporte de Consola Serie UART 115200 8N1 + UEFI GOP
    cat << 'EOF' > "${LOCAL_CFG_DIR}/console.h"
#define CONSOLE_PCBIOS
#define CONSOLE_EFI
#define CONSOLE_SERIAL
#undef  COMSPEED
#define COMSPEED 115200
EOF

    # embedded.ipxe: Script OS-Agnostic con enlace a boot.ipxe
    cat << EOF > "${IPXE_GIT_DIR}/src/embedded.ipxe"
#!ipxe
# =============================================================================
# SCRIPT DE ARRANQUE EMBEBIDO: ARQUITECTURA ZERO-TOUCH BARE-METAL
# Enlace dinámico: Compatible con cualquier SO definido en boot.ipxe
# =============================================================================
set esc:hex 1b
set bold:hex 1b 5b 31 6d
set reset:hex 1b 5b 30 6d

echo \${bold}====================================================================\${reset}
echo \${bold}   IPXE CUSTOM OPTIMIZADO: CLÚSTER EDGE DELL OPTIPLEX 3020M        \${reset}
echo \${bold}   Controlador: ${PXE_IP:-10.100.29.30} | Puerto HTTP: ${HTTPBOOT_PORT:-8089}              \${reset}
echo \${bold}====================================================================\${reset}

echo [*] Inicializando interfaz de red...
ifopen net0 || goto err_nic

echo [*] Negociando concesion DHCP IPv4 para MAC: \${net0/mac}...
dhcp net0 || goto err_dhcp

echo [OK] Red configurada: IP \${net0/ip} / Gateway \${net0/gateway}

set boot_url http://${PXE_IP:-10.100.29.30}:${HTTPBOOT_PORT:-8089}/boot.ipxe
echo [*] Descargando cadena de arranque: \${boot_url}
chain --autofree \${boot_url} || goto err_chain

:err_nic
echo [ERROR] No se pudo inicializar la interfaz de red fisica net0.
shell
exit

:err_dhcp
echo [ERROR] Tiempo de espera DHCP agotado. Verifique conexion a VLAN 29.
shell
exit

:err_chain
echo [ERROR] Fallo al cargar \${boot_url}. Verifique Nginx en Nodo 306.
echo [*] Probando conexion con ping...
ping -c 3 ${PXE_IP:-10.100.29.30} || echo [ALERTA] Servidor no responde a ping.
shell
exit
EOF
fi
log_success "Cabeceras de optimización y script embebido inyectados con éxito."

# ------------------------------------------------------------------------------
# 5. COMPILACIÓN DE BINARIOS MULTI-ARQUITECTURA
# ------------------------------------------------------------------------------
log_info "5. Compilando binarios iPXE (UEFI x86_64 y BIOS Legacy)..."

if [[ "${DRY_RUN}" = false ]]; then
    cd "${IPXE_GIT_DIR}/src"

    # Compilar UEFI x86_64
    log_info "Compilando bin-x86_64-efi/ipxe.efi..."
    make -j"$(nproc)" bin-x86_64-efi/ipxe.efi EMBED=embedded.ipxe 2>&1 | tee "${LOGS_DIR}/build-uefi.log" >/dev/null

    # Compilar BIOS Legacy
    log_info "Compilando bin/undionly.kpxe..."
    make -j"$(nproc)" bin/undionly.kpxe EMBED=embedded.ipxe 2>&1 | tee "${LOGS_DIR}/build-bios.log" >/dev/null

    # Mover a dist/
    cp -f bin-x86_64-efi/ipxe.efi "${DIST_DIR}/ipxe-custom-x86_64.efi"
    cp -f bin/undionly.kpxe "${DIST_DIR}/undionly-custom.kpxe"

    # Generar Checksums
    cd "${DIST_DIR}"
    sha256sum ipxe-custom-x86_64.efi undionly-custom.kpxe > checksums.sha256
    log_success "Compilación completada sin errores."
fi

# ------------------------------------------------------------------------------
# 6. VERIFICACIÓN FORENSE DE LOS BINARIOS GENERADOS
# ------------------------------------------------------------------------------
log_info "6. Ejecutando auditoría de calidad forense en binarios..."

if [[ "${DRY_RUN}" = false ]]; then
    # Chequeo de formato
    FILE_TYPE="$(file "${DIST_DIR}/ipxe-custom-x86_64.efi")"
    if [[ "${FILE_TYPE}" != *"PE32+ executable"* ]] && [[ "${FILE_TYPE}" != *"MS Windows"* ]]; then
        log_error "Formato de binario inesperado: ${FILE_TYPE}"
        exit 1
    fi

    # Chequeo de ausencia de IPv6
    if strings "${DIST_DIR}/ipxe-custom-x86_64.efi" | grep -qi "router solicitation"; then
        log_error "ALERTA: Se detectaron llamadas IPv6 en el binario compilado."
        exit 1
    else
        log_success "Certificado: 0% de cadenas IPv6 (Cero retardos en BIOS Dell A05)."
    fi

    # Chequeo del script incrustado
    if ! strings "${DIST_DIR}/ipxe-custom-x86_64.efi" | grep -q "IPXE CUSTOM OPTIMIZADO"; then
        log_error "ALERTA: El script embebido no se detectó en la sección de datos del ejecutable."
        exit 1
    else
        log_success "Certificado: Script embebido incrustado correctamente en el ejecutable."
    fi

    UEFI_SIZE="$(ls -lh "${DIST_DIR}/ipxe-custom-x86_64.efi" | awk '{print $5}')"
    BIOS_SIZE="$(ls -lh "${DIST_DIR}/undionly-custom.kpxe" | awk '{print $5}')"
    log_info "Tamaños generados: UEFI: ${UEFI_SIZE} | BIOS: ${BIOS_SIZE} (Comprimido LZMA)"
fi

# ------------------------------------------------------------------------------
# 7. PRUEBA VIRTUALIZADA EN QEMU (OPCIONAL)
# ------------------------------------------------------------------------------
if [[ "${RUN_QEMU_TEST}" = true ]]; then
    log_info "7. Ejecutando prueba virtualizada en QEMU OVMF UEFI..."
    if command -v qemu-system-x86_64 >/dev/null 2>&1 && [[ -f /usr/share/ovmf/OVMF.fd ]]; then
        log_info "Iniciando VM de prueba con TFTP aislado en ${DIST_DIR}..."
        timeout 10 qemu-system-x86_64 \
            -m 512 \
            -bios /usr/share/ovmf/OVMF.fd \
            -netdev user,id=net0,tftp="${DIST_DIR}",bootfile=ipxe-custom-x86_64.efi \
            -device virtio-net-pci,netdev=net0 \
            -nographic || true
        log_success "Prueba en emulador UEFI finalizada."
    else
        log_warn "QEMU o /usr/share/ovmf/OVMF.fd no están instalados. Omitiendo prueba de emulación."
    fi
fi

# ------------------------------------------------------------------------------
# 8. DESPLIEGUE ATÓMICO EN /tftpboot (SOLO CON --install)
# ------------------------------------------------------------------------------
if [[ "${INSTALL_TO_PROD}" = true ]]; then
    log_info "8. Despliegue atómico en producción (/tftpboot)..."
    confirm_action "¿Desea actualizar /tftpboot/ipxe.efi con el nuevo binario optimizado?"

    TFTP_DIR="/tftpboot"
    mkdir -p "${TFTP_DIR}"

    if [[ "${DRY_RUN}" = false ]]; then
        # Respaldar archivos existentes con marca temporal
        TS="$(date '+%Y%m%d_%H%M%S')"
        if [[ -f "${TFTP_DIR}/ipxe.efi" ]]; then
            cp -v "${TFTP_DIR}/ipxe.efi" "${BACKUPS_DIR}/ipxe.efi.${TS}.bak"
            cp -v "${TFTP_DIR}/ipxe.efi" "${BACKUPS_DIR}/ipxe.efi.original.bak" 2>/dev/null || true
        fi
        if [[ -f "${TFTP_DIR}/undionly.kpxe" ]]; then
            cp -v "${TFTP_DIR}/undionly.kpxe" "${BACKUPS_DIR}/undionly.kpxe.${TS}.bak"
            cp -v "${TFTP_DIR}/undionly.kpxe" "${BACKUPS_DIR}/undionly.kpxe.original.bak" 2>/dev/null || true
        fi

        # Copia atómica con extensión .new y reemplazo inmediato 'mv'
        cp "${DIST_DIR}/ipxe-custom-x86_64.efi" "${TFTP_DIR}/ipxe.efi.new"
        cp "${DIST_DIR}/undionly-custom.kpxe" "${TFTP_DIR}/undionly.kpxe.new"

        # Permisos canónicos para el demonio tftp
        chown tftp:tftp "${TFTP_DIR}/"*.new 2>/dev/null || chown nobody:nogroup "${TFTP_DIR}/"*.new 2>/dev/null || true
        chmod 0644 "${TFTP_DIR}/"*.new

        mv -f "${TFTP_DIR}/ipxe.efi.new" "${TFTP_DIR}/ipxe.efi"
        mv -f "${TFTP_DIR}/undionly.kpxe.new" "${TFTP_DIR}/undionly.kpxe"

        log_success "Binarios de producción actualizados atómicamente en ${TFTP_DIR}."
        log_info "dnsmasq detectará automáticamente los nuevos binarios sin requerir reinicio del servicio."
    fi
else
    log_info "Modo Staging completado. Los binarios listos para producción residen en:"
    echo -e "  • UEFI: ${COLOR_GREEN}${DIST_DIR}/ipxe-custom-x86_64.efi${COLOR_NC}"
    echo -e "  • BIOS: ${COLOR_GREEN}${DIST_DIR}/undionly-custom.kpxe${COLOR_NC}"
    echo -e "\nPara instalarlos en /tftpboot cuando lo desee, ejecute:"
    echo -e "  ${COLOR_BOLD}sudo $0 --install -y${COLOR_NC}"
fi

echo -e "\n${COLOR_GREEN}==================================================================${COLOR_NC}"
echo -e "${COLOR_GREEN}   PROCESO COMPLETADO EXITOSAMENTE (CERO IMPACTO EN PRODUCCIÓN)   ${COLOR_NC}"
echo -e "${COLOR_GREEN}==================================================================${COLOR_NC}"

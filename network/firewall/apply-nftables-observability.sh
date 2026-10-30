#!/usr/bin/env bash
# Restringe puertos de observabilidad; conserva el resto del ruleset.
# Ejecutar localmente con sudo. Requiere confirmación en 60 segundos.
set -Eeuo pipefail
[[ ${EUID} -eq 0 ]] || { echo "Ejecute con sudo" >&2; exit 1; }
command -v flock >/dev/null
exec 9>/run/lock/infra-observability.lock
flock -n 9 || { echo "Ya hay otra aplicación de reglas en curso" >&2; exit 1; }
umask 077
WORK_DIR=$(mktemp -d /tmp/infra-observability.XXXXXX)
APPLIED=false
CONFIRMED=false
restore() {
    local code=$?
    trap - EXIT
    if [[ "${APPLIED}" == true && "${CONFIRMED}" == false ]]; then
        echo "Sin confirmación: restaurando la tabla anterior..." >&2
        if ! nft -f "${WORK_DIR}/restore.nft"; then
            echo "ERROR: rollback fallido. Respaldo: ${WORK_DIR}" >&2
            exit 1
        fi
    fi
    # Se conserva el respaldo privado para diagnóstico.
    echo "Archivos de reglas: ${WORK_DIR}"
    exit "${code}"
}
trap restore EXIT
trap 'exit 1' HUP INT TERM

if nft list table inet observability_filter > "${WORK_DIR}/previous.nft" 2>/dev/null; then
    echo 'delete table inet observability_filter' > "${WORK_DIR}/apply.nft"
else
    : > "${WORK_DIR}/previous.nft"
    : > "${WORK_DIR}/apply.nft"
fi
{
    echo 'delete table inet observability_filter'
    cat "${WORK_DIR}/previous.nft"
} > "${WORK_DIR}/restore.nft"
cat >> "${WORK_DIR}/apply.nft" <<'RULES'
table inet observability_filter {
    chain input {
        type filter hook input priority 0; policy accept;
        iifname "lo" accept
        ip saddr 10.100.29.0/24 tcp dport { 9100, 9180, 9104, 15692, 9090, 8428, 3100, 3200, 4317, 4318, 19579 } accept
        tcp dport { 9100, 9180, 9104, 15692, 9090, 8428, 3100, 3200, 4317, 4318, 19579 } drop
    }
}
RULES
nft -c -f "${WORK_DIR}/apply.nft"
nft -f "${WORK_DIR}/apply.nft"
APPLIED=true
printf 'Compruebe conectividad. Escriba CONFIRMAR antes de 60 segundos: '
if read -r -t 60 answer && [[ "${answer}" == CONFIRMAR ]]; then
    CONFIRMED=true
    echo "Reglas confirmadas (solo en memoria; no se modificó la configuración persistente)."
else
    exit 1
fi

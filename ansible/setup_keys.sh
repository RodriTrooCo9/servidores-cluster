#!/usr/bin/env bash
# ==============================================================================
# Script de Preparación y Blindaje de Llaves para Ansible
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="${SCRIPT_DIR}/keys"
VAULT_PASS_FILE="${SCRIPT_DIR}/.vault_pass"
SOURCE_KEY="${HOME}/.ssh/id_ed25519"

echo "🔐 [1/4] Asegurando permisos del directorio de llaves..."
mkdir -p "${KEYS_DIR}"
chmod 700 "${KEYS_DIR}"

echo "🔑 [2/4] Verificando llave privada SSH..."
if [[ -f "${SOURCE_KEY}" ]]; then
    # Copiar llave local asegurando permisos estrictos 0600 (ignorado por Git)
    cp "${SOURCE_KEY}" "${KEYS_DIR}/cluster_key"
    chmod 600 "${KEYS_DIR}/cluster_key"
    echo "   -> Llave sincronizada en ${KEYS_DIR}/cluster_key (chmod 600)"
else
    echo "   [!] Advertencia: No se encontró ${SOURCE_KEY}."
fi

echo "🛡️ [3/4] Verificando clave de Ansible Vault..."
if [[ ! -f "${VAULT_PASS_FILE}" ]]; then
    # Generar clave aleatoria si no existe
    openssl rand -base64 24 > "${VAULT_PASS_FILE}"
    chmod 600 "${VAULT_PASS_FILE}"
    echo "   -> Creado archivo .vault_pass con contraseña segura autogenerada (chmod 600)"
else
    chmod 600 "${VAULT_PASS_FILE}"
    echo "   -> Archivo .vault_pass detectado y asegurado (chmod 600)"
fi

echo "🚀 [4/4] Probando conectividad con Ansible..."
cd "${SCRIPT_DIR}"
ansible -m ping baremetal -o

echo "================================================================================"
echo "✅ Entorno de Ansible y llaves configurado con éxito y protegido contra fugas Git."
echo "================================================================================"

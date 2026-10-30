#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${SCRIPT_DIR}/openstack"
mkdir -p "${TARGET_DIR}"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

IPA_KERNEL_URL="https://tarballs.opendev.org/openstack/ironic-python-agent/dib/files/ipa-centos9-stable-2024.1.kernel"
IPA_INITRAMFS_URL="https://tarballs.opendev.org/openstack/ironic-python-agent/dib/files/ipa-centos9-stable-2024.1.initramfs"

KERNEL_FILE="${TARGET_DIR}/ironic-agent.kernel"
INITRAMFS_FILE="${TARGET_DIR}/ironic-agent.initramfs"

echo "==> Verificando artefactos de Ironic Python Agent en ${TARGET_DIR}..."

if [[ ! -f "${KERNEL_FILE}" ]] || [[ "${FORCE}" = true ]]; then
    echo "Descargando ironic-agent.kernel..."
    curl -fL --progress-bar -o "${KERNEL_FILE}" "${IPA_KERNEL_URL}"
else
    echo "  [OK] ironic-agent.kernel ya presente."
fi

if [[ ! -f "${INITRAMFS_FILE}" ]] || [[ "${FORCE}" = true ]]; then
    echo "Descargando ironic-agent.initramfs..."
    curl -fL --progress-bar -o "${INITRAMFS_FILE}" "${IPA_INITRAMFS_URL}"
else
    echo "  [OK] ironic-agent.initramfs ya presente."
fi

chmod 644 "${KERNEL_FILE}" "${INITRAMFS_FILE}"
echo "==> Generando firmas SHA256..."
(cd "${TARGET_DIR}" && sha256sum ironic-agent.kernel ironic-agent.initramfs > SHA256SUMS)
echo "==> Artefactos listos en ${TARGET_DIR}."

#!/usr/bin/env bash
# ==============================================================================
# Script: setup_nexus_kolla_registry.sh
# Objetivo: Configurar en Sonatype Nexus 3 los repositorios Docker (proxy y hosted)
#           para almacenar y cachear las imágenes de Kolla-Ansible (OpenStack 2025.1)
# ==============================================================================
set -euo pipefail

NEXUS_HOST="${NEXUS_HOST:-10.100.29.20}"
NEXUS_PORT="${NEXUS_PORT:-8081}"
NEXUS_USER="${NEXUS_USER:-admin}"
NEXUS_PASS="${NEXUS_PASS:-admin123}"

BASE_URL="http://${NEXUS_HOST}:${NEXUS_PORT}/service/rest/v1"

echo "=== 1. Verificando conectividad con Sonatype Nexus (${BASE_URL}) ==="
if ! curl -s -f -u "${NEXUS_USER}:${NEXUS_PASS}" "${BASE_URL}/status" >/dev/null; then
    echo "[ERROR] No se pudo conectar a Nexus en ${BASE_URL} con las credenciales indicadas."
    echo "Verifica que el servicio esté arriba y que las credenciales sean válidas."
    exit 1
fi
echo "[OK] Nexus responde correctamente."

echo "=== 2. Creando Blob Store dedicado 'kolla-docker' ==="
curl -s -X POST -u "${NEXUS_USER}:${NEXUS_PASS}" \
    -H "Content-Type: application/json" \
    "${BASE_URL}/blobstores/file" \
    -d '{
        "name": "kolla-docker",
        "path": "/opt/sonatype/data/blobs/kolla-docker"
    }' || echo "Blob store kolla-docker ya existe o fue omitido."

echo "=== 3. Creando Repositorio Docker Hosted (puerto 8083) para push local ==="
curl -s -X POST -u "${NEXUS_USER}:${NEXUS_PASS}" \
    -H "Content-Type: application/json" \
    "${BASE_URL}/repositories/docker/hosted" \
    -d '{
        "name": "kolla-docker-hosted",
        "online": true,
        "storage": {
            "blobStoreName": "kolla-docker",
            "strictContentTypeValidation": true,
            "writePolicy": "ALLOW"
        },
        "docker": {
            "v1Enabled": false,
            "forceBasicAuth": false,
            "httpPort": 8083
        }
    }' || echo "Repositorio kolla-docker-hosted ya existe o fue omitido."

echo "=== 4. Creando Repositorio Docker Proxy a Quay.io (puerto 8082) ==="
curl -s -X POST -u "${NEXUS_USER}:${NEXUS_PASS}" \
    -H "Content-Type: application/json" \
    "${BASE_URL}/repositories/docker/proxy" \
    -d '{
        "name": "kolla-docker-quay-proxy",
        "online": true,
        "storage": {
            "blobStoreName": "kolla-docker",
            "strictContentTypeValidation": true
        },
        "proxy": {
            "remoteUrl": "https://quay.io",
            "contentMaxAge": 1440,
            "metadataMaxAge": 1440
        },
        "docker": {
            "v1Enabled": false,
            "forceBasicAuth": false,
            "httpPort": 8082
        },
        "dockerProxy": {
            "indexType": "REGISTRY"
        },
        "negativeCache": {
            "enabled": true,
            "timeToLive": 1440
        },
        "httpClient": {
            "blocked": false,
            "autoBlock": true
        }
    }' || echo "Repositorio kolla-docker-quay-proxy ya existe o fue omitido."

echo "=== Configuración de Nexus finalizada con éxito ==="
echo "Docker Proxy activo en: http://${NEXUS_HOST}:8082"
echo "Docker Hosted activo en: http://${NEXUS_HOST}:8083"

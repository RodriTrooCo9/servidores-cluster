#!/usr/bin/env bash
# ==============================================================================
# SCRIPT 03: INSTALACIÓN DE SONATYPE NEXUS 3 CON POSTGRESQL 16 (03-nexus.sh)
# Objetivo: PostgreSQL 16, Java 17, Nexus 3 OSS, JVM tuning 4 GB y mitigación 128 GB
# Nodo de Ejecución: [NEXUS] (Nodo 315 | IP: 10.100.29.20 | MAC: 64:00:6a:2a:5f:99)
# Fase README: FASE 3: Sonatype Nexus 3 con Backend PostgreSQL 16 y Tuning de Disco
# Uso: sudo ./03-nexus.sh [--dry-run] [--force] [-y]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/common.sh
if [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
    source "${SCRIPT_DIR}/lib/common.sh"
elif [[ -f "${REPO_DIR}/lib/common.sh" ]]; then
    source "${REPO_DIR}/lib/common.sh"
else
    echo "ERROR: No se encontró lib/common.sh" >&2
    exit 1
fi

parse_common_flags "$@"
load_config
require_root
validate_current_node "nexus"

echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"
echo -e "${COLOR_BLUE}   FASE 3: DESPLIEGUE DE SONATYPE NEXUS 3 Y POSTGRESQL 16        ${COLOR_NC}"
echo -e "${COLOR_BLUE}==================================================================${COLOR_NC}"

confirm_action "¿Desea instalar PostgreSQL 16 y Sonatype Nexus 3 en este servidor?"

# ------------------------------------------------------------------------------
# 3.1 INSTALACIÓN Y CONFIGURACIÓN DE POSTGRESQL
# ------------------------------------------------------------------------------
log_info "3.1 Instalando base de datos relacional PostgreSQL..."
apt_install postgresql

log_info "Configurando usuario y base de datos 'nexus' en PostgreSQL..."
if [[ "${DRY_RUN}" = false ]]; then
    systemctl enable --now postgresql
    sudo -u postgres psql << EOF
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${POSTGRES_NEXUS_USER}') THEN
        CREATE USER ${POSTGRES_NEXUS_USER} WITH ENCRYPTED PASSWORD '${POSTGRES_NEXUS_PASSWORD}';
    ELSE
        ALTER USER ${POSTGRES_NEXUS_USER} WITH ENCRYPTED PASSWORD '${POSTGRES_NEXUS_PASSWORD}';
    END IF;
END
\$\$;

SELECT 'CREATE DATABASE ${POSTGRES_NEXUS_DB} OWNER ${POSTGRES_NEXUS_USER}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${POSTGRES_NEXUS_DB}')\gexec

GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_NEXUS_DB} TO ${POSTGRES_NEXUS_USER};
\c ${POSTGRES_NEXUS_DB}
CREATE SCHEMA IF NOT EXISTS ${POSTGRES_NEXUS_USER} AUTHORIZATION ${POSTGRES_NEXUS_USER};
GRANT ALL ON SCHEMA public TO ${POSTGRES_NEXUS_USER};
EOF
fi
log_success "Base de datos PostgreSQL configurada para Nexus."

# ------------------------------------------------------------------------------
# 3.2 INSTALACIÓN DE JAVA 17, USUARIO Y LÍMITES DEL SISTEMA
# ------------------------------------------------------------------------------
log_info "3.2 Verificando e instalando Java 17 LTS y configurando límites de descriptores..."
if ! command -v java >/dev/null 2>&1 || ! java -version 2>&1 | grep -q "17\."; then
    if apt-cache show openjdk-17-jdk-headless >/dev/null 2>&1; then
        apt_install openjdk-17-jdk-headless wget tar curl
    else
        log_info "Configurando repositorio oficial Eclipse Temurin Java 17 LTS (Adoptium)..."
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public -o /etc/apt/keyrings/adoptium.asc
        echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb bookworm main" > /etc/apt/sources.list.d/adoptium.list
        apt-get update -qq
        apt_install temurin-17-jdk wget tar curl
    fi
else
    apt_install wget tar curl
fi

if ! id "nexus" >/dev/null 2>&1; then
    run_cmd useradd --system --no-create-home --shell /bin/false nexus
    log_success "Usuario de sistema 'nexus' creado."
fi

LIMITS_CONF="/etc/security/limits.d/99-nexus.conf"
backup_file "${LIMITS_CONF}"
if [[ "${DRY_RUN}" = false ]]; then
    cat > "${LIMITS_CONF}" << EOF
nexus   soft   nofile   65536
nexus   hard   nofile   65536
EOF
fi
log_success "Límites nofile fijados en 65536."

# ------------------------------------------------------------------------------
# 3.3 DESCARGA E INSTALACIÓN DE NEXUS 3 OSS
# ------------------------------------------------------------------------------
log_info "3.3 Descargando y desplegando binarios de Sonatype Nexus 3..."
run_cmd mkdir -p /opt/sonatype /opt/sonatype/sonatype-work/nexus3/etc

if [[ ! -d /opt/sonatype/nexus ]]; then
    if [[ "${DRY_RUN}" = false ]]; then
        cd /opt/sonatype
        if [[ ! -f latest-unix.tar.gz ]]; then
            log_info "Descargando paquete oficial de Nexus 3 (3.76.1)..."
            NEXUS_URL="https://download.sonatype.com/nexus/3/nexus-3.76.1-01-unix.tar.gz"
            if ! wget -q --show-progress -O latest-unix.tar.gz "${NEXUS_URL}"; then
                log_warn "Error descargando versión 3.76.1; intentando versión 3.70.3..."
                wget -q --show-progress -O latest-unix.tar.gz "https://download.sonatype.com/nexus/3/nexus-3.70.3-01-unix.tar.gz"
            fi
        fi
        tar -xzf latest-unix.tar.gz
        ln -sf nexus-3* nexus
    fi
fi

# Tuning JVM para nodo físico de 16 GB RAM y backend PostgreSQL
VMOPTIONS="/opt/sonatype/nexus/bin/nexus.vmoptions"
if [[ "${DRY_RUN}" = false ]]; then
    backup_file "${VMOPTIONS}"
    sed -i "s/^-Xms[0-9]*m/-Xms${NEXUS_JVM_HEAP_MB}m/" "${VMOPTIONS}"
    sed -i "s/^-Xmx[0-9]*m/-Xmx${NEXUS_JVM_HEAP_MB}m/" "${VMOPTIONS}"
    if ! grep -q "MaxDirectMemorySize" "${VMOPTIONS}"; then
        cat >> "${VMOPTIONS}" << EOF
-XX:MaxDirectMemorySize=${NEXUS_JVM_HEAP_MB}m
-Djava.util.prefs.userRoot=/opt/sonatype/sonatype-work/nexus3/javaprefs
-Dnexus.datastore.enabled=true
-Dnexus.datastore.nexus.jdbcUrl=jdbc:postgresql://localhost:${POSTGRES_PORT}/${POSTGRES_NEXUS_DB}
-Dnexus.datastore.nexus.username=${POSTGRES_NEXUS_USER}
-Dnexus.datastore.nexus.password=${POSTGRES_NEXUS_PASSWORD}
EOF
    fi
fi
log_success "Tuning JVM aplicado: 4 GB Heap + 4 GB DirectMemory con G1GC y backend PostgreSQL."

# ------------------------------------------------------------------------------
# 3.4 CONEXIÓN DE NEXUS A POSTGRESQL 16
# ------------------------------------------------------------------------------
log_info "3.4 Conectando Nexus 3 con backend PostgreSQL 16..."
NEXUS_PROPS="/opt/sonatype/sonatype-work/nexus3/etc/nexus.properties"
backup_file "${NEXUS_PROPS}"
if [[ "${DRY_RUN}" = false ]]; then
    cat > "${NEXUS_PROPS}" << EOF
nexus.datastore.enabled=true
nexus.datastore.nexus.jdbcUrl=jdbc:postgresql://localhost:${POSTGRES_PORT}/${POSTGRES_NEXUS_DB}
nexus.datastore.nexus.username=${POSTGRES_NEXUS_USER}
nexus.datastore.nexus.password=${POSTGRES_NEXUS_PASSWORD}
EOF
    chown -R nexus:nexus /opt/sonatype
fi

# ------------------------------------------------------------------------------
# 3.5 UNIDAD SYSTEMD DE NEXUS
# ------------------------------------------------------------------------------
log_info "3.5 Configurando servicio systemd para Nexus..."
NEXUS_SERVICE="/etc/systemd/system/nexus.service"
backup_file "${NEXUS_SERVICE}"
if [[ "${DRY_RUN}" = false ]]; then
    cat > "${NEXUS_SERVICE}" << EOF
[Unit]
Description=Sonatype Nexus 3 Repository Manager
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=forking
LimitNOFILE=65536
ExecStart=/opt/sonatype/nexus/bin/nexus start
ExecStop=/opt/sonatype/nexus/bin/nexus stop
User=nexus
Restart=on-abort
TimeoutSec=300

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now nexus
fi
log_success "Servicio systemd 'nexus' registrado y arrancado."

# ------------------------------------------------------------------------------
# 3.6 MITIGACIÓN DE DISCO DE 128 GB (CRON GUARD)
# ------------------------------------------------------------------------------
log_info "3.6 Configurando guardia preventiva de espacio en disco (128 GB NVMe)..."
GUARD_SCRIPT="/etc/cron.hourly/nexus-disk-guard"
if [[ "${DRY_RUN}" = false ]]; then
    cat > "${GUARD_SCRIPT}" << 'EOF'
#!/usr/bin/env bash
OCCUPIED=$(df /opt/sonatype | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$OCCUPIED" -gt 80 ]; then
    logger -t NEXUS_DISK_GUARD "ALERTA: Espacio en disco crítico (>80%, actual: $OCCUPIED%). Revise blobstore de Nexus."
fi
EOF
    chmod +x "${GUARD_SCRIPT}"
fi
log_success "Script de supervisión preventiva de disco instalado en ${GUARD_SCRIPT}."

# ------------------------------------------------------------------------------
# 3.7 VALIDACIÓN DE FASE 3
# ------------------------------------------------------------------------------
log_info "3.7 Esperando a que Nexus y PostgreSQL inicialicen puertos..."
if [[ "${DRY_RUN}" = true ]]; then
    log_success "[DRY-RUN] Validación simulada exitosa."
    exit 0
fi

check_port "${POSTGRES_PORT}" "tcp"
check_service "postgresql"

log_info "Esperando disponibilidad del socket HTTP de Nexus (:8081)..."
retry 30 10 check_port "${NEXUS_PORT}" "tcp"

check_nexus_status() {
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${NEXUS_PORT}/service/rest/v1/status" 2>/dev/null || echo "000")
    [[ "${code}" == "200" ]]
}

log_info "Validando endpoint REST de estado de Nexus..."
retry 30 10 check_nexus_status
log_success "Endpoint REST /service/rest/v1/status respondió 200 OK."

ADMIN_PASS_FILE="/opt/sonatype/sonatype-work/nexus3/admin.password"
if [[ -f "${ADMIN_PASS_FILE}" ]]; then
    INIT_PASS=$(cat "${ADMIN_PASS_FILE}")
    log_info "Contraseña administrativa inicial (admin): ${INIT_PASS}"
fi

echo -e "\n${COLOR_GREEN}==================================================================${COLOR_NC}"
echo -e "${COLOR_GREEN}   FASE 3 COMPLETADA CON ÉXITO: NEXUS 3 OPERATIVO EN PUERTO 8081  ${COLOR_NC}"
echo -e "${COLOR_GREEN}==================================================================${COLOR_NC}"

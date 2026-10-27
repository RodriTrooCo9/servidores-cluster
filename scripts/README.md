# Scripts Operativos, Diagnóstico y Contingencia

Este directorio almacena utilidades Bash y Python de bajo nivel organizadas por ámbito de operación.

> [!NOTE]
> Ansible es el motor de configuración primario. Los scripts presentes en este directorio están reservados para tareas de inicialización (*bootstrap*), diagnóstico en terminal, contingencia y túneles de cliente.

## Estructura
```text
scripts/
├── lib/
│   └── common.sh                      # Biblioteca compartida (logs, traps, confirmaciones, colores)
├── bootstrap/
│   ├── bootstrap_node.py              # Bootstrap interactivo vía Python/pexpect con ProxyJump
│   └── setup_keys.sh                  # Distribución inicial de claves SSH
├── diagnostics/
│   ├── 00-preflight.sh                # Auditoría de compatibilidad Debian 13 y hardware
│   ├── 09-verificacion.sh             # Pruebas integrales de red y datapath Cilium
│   └── healthcheck.sh                 # Tablero de métricas en terminal y salud de la flota
├── ops/
│   ├── 07-cloud-init.sh               # Generación y validación legacy de ConfigDrive
│   ├── disaster-recovery.sh           # Procedimiento de respaldo y recuperación de etcd/MariaDB
│   └── levantar-todo.sh               # Secuencia de encendido y arranque global
└── client/
    ├── ejecutar-desde-laptop.sh       # Orquestador remoto desde estación de trabajo
    ├── setup-client-workstation.sh    # Configuración de SSH config y dependencias en laptop
    └── tunnels.sh                     # Apertura de túneles SSH para Grafana, Horizon y Nexus
```

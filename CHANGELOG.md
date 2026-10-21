# Changelog

Todos los cambios notables en este proyecto serán documentados en este archivo.
El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/),
y este proyecto se adhiere a [Semantic Versioning](https://semver.org/lang/es/).

## [1.0.0] - 2026-10-21

### Añadido
- Arquitectura empresarial SRE/DevOps con separación por capas y entornos (`inventory/lab`, `inventory/prod`).
- `Makefile` maestro como punto de entrada unificado (`make help`, `make preflight`, `make deploy`, `make lint`).
- Tooling estricto de calidad de código: `.editorconfig`, `.yamllint`, `.ansible-lint`, `.pre-commit-config.yaml`, `.gitlab-ci.yml`.
- Configuración de cifrado con SOPS + age (`.sops.yaml`) y Ansible Vault.
- Manifiestos de Kubernetes estructurados con soporte para Kustomize (`kubernetes/base`, `kubernetes/apps`, `kubernetes/observability`, `kubernetes/overlays`).
- Nueva carpeta `cloud-init/` con plantillas Packer HCL2 y generador dinámico de ConfigDrive (`config-2`).
- Nueva carpeta `nexus/` para repositorios, políticas de depuración y blobstores como código.
- Nueva carpeta `network/` para dnsmasq, iPXE y reglas de firewall nftables.
- Scripts de aprovisionamiento organizados en `scripts/bootstrap`, `scripts/ops`, `scripts/diagnostics` y `scripts/client`.
- Procedimientos estándar de recuperación y operación en `docs/runbooks/` y Architecture Decision Records en `docs/adr/`.

### Cambiado
- Migrada la carpeta `kolla/` a `openstack/` con inventario multinodo y secretos segregados.
- Reorganizados los playbooks de Ansible en fases ordenadas: `00-preflight`, `10-base`, `20-services`, `30-platform`, `40-observability`, `50-validation`, `90-operations`.
- Consolidada la matriz física única en `inventory/nodes.csv`.
- Eliminados hardcodeos de nombres de host específicos en manifiestos de telemetría.

### Seguridad
- Retirados todos los secretos en texto plano del control de versiones (`credenciales.md`, `kolla/passwords.yml`, `config/env`).
- Reemplazados por esquemas de cifrado en Ansible Vault / SOPS y plantillas `*.example`.
- Excluidos estrictamente del repositorio binarios pesados (638 MB de ramdisk IPA) y volcados de backup (1.3 GB).

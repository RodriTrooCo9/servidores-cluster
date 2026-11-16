# ADR 0001: Migración de Scripts Bash Imperativos a Ansible Declarativo

## Estado
Aceptado

## Contexto
Originalmente la suite constaba de 11 scripts Bash secuenciales (`00` a `10`) que debían ejecutarse manualmente conectándose por SSH a cada servidor físico. Esto generaba problemas de falta de idempotencia, dificultad para gestionar estados parciales, dispersión de credenciales y ausencia de ejecución en paralelo.

## Decisión
Adoptar **Ansible Core** como el motor estándar de automatización de infraestructura:
- Organización modular en roles (`common`, `bastion`, `nexus`, `pxe_controller`, `ironic`, `rke2_ha`, `monitoring`).
- Playbooks numerados por fases (`00-preflight`, `10-base`, `20-services`, `30-platform`, `40-observability`, `50-validation`, `90-operations`).
- Centralización de variables en `inventory/lab/group_vars/` y cifrado con `ansible-vault`.
- Los scripts Bash se reservan exclusivamente para tareas de bajo nivel, diagnóstico interactivo en terminal y bootstrap inicial.

## Consecuencias
- **Positivas**: Permite ejecutar sobre varios nodos y revisar cambios con `--check --diff`. La idempotencia y el alcance deben verificarse por tarea.
- **Negativas**: Curva de aprendizaje para desarrolladores no familiarizados con YAML/Jinja2 y necesidad de gestionar el archivo `.vault_pass`.

El orquestador actual importa dos playbooks de preflight que faltan. Hasta
repararlos, selecciona los playbooks individuales descritos en la guía.
[Guía Ansible](../../GUIA_ANSIBLE.md)

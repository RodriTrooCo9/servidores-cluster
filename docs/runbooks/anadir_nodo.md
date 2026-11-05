# Añadir un nodo a la infraestructura Kubernetes

Este procedimiento comienza con el sistema operativo instalado y acceso SSH disponible. La instalación del sistema operativo es [otro proyecto](../../GUIA_OPENSTACK.md).

## 1 Revisar el equipo

Confirma IP, MAC, usuario, disco y rol previsto. Comprueba que el equipo nuevo no contiene datos o servicios que deban conservarse. No conviertas un agente o un control plane activo en otro rol mediante cambios de inventario.

## 2 Actualizar el inventario

**Dónde:** editor de la laptop, `inventory/lab/hosts.yml`. Añade el equipo al grupo `k8s_workers` o `k8s_control_plane` y asigna sus valores reales de `ansible_host`, `ansible_user`, `node_id`, `cluster_hostname`, `mac`, `ram_gb` y `disk_gb`.

Si falta el sistema operativo, termina primero la guía de aprovisionamiento. El playbook Ironic administra el controlador; `--limit` con el nombre del nuevo nodo no ordena su instalación.

## 3 Comprobar el alcance

**Dónde:** laptop, raíz del repositorio, con Ansible y Vault configurados. Este comando muestra qué equipos recibirá la fase de plataforma, sin modificar servicios.

```bash
ansible-playbook -i inventory/lab/hosts.yml ansible/playbooks/30-platform/01_rke2_cluster.yml --list-hosts
```

**Resultado esperado:** el nodo nuevo y los miembros previstos aparecen en el grupo correcto. Revisa también que el líder corresponda al servicio real.

## 4 Aplicar la configuración

Sigue las etapas de sistema base, Nexus y RKE2 de la [guía de infraestructura](../../GUIA_DE_INSTALACION.md). Revisa el alcance de cada playbook antes de aplicarlo: la incorporación requiere acceso al líder existente y no equivale a reinstalar todos los nodos.

## 5 Validar

**Dónde:** laptop con el kubeconfig correcto. Este comando muestra la incorporación del nodo sin modificar el clúster.

```bash
kubectl get nodes -o wide
```

**Resultado esperado:** el nuevo nodo aparece con su IP y estado `Ready`. Si no aparece, consulta los logs de `rke2-agent` o `rke2-server` en ese equipo y revisa su conectividad con el líder.

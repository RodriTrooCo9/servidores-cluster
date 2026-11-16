# Guía de Conexión Rápida al Proyecto y Servidores

Esta guía prepara el acceso compartido al laboratorio. Después elige la [infraestructura Kubernetes](GUIA_DE_INSTALACION.md) o la [instalación de sistemas operativos](GUIA_OPENSTACK.md).

Esta guía explica paso a paso cómo descargar el código completo del repositorio y cómo conectarte a los servidores del proyecto desde tu propia computadora (laptop con Linux, macOS o Windows con WSL2).

Está pensada para ser directa, clara y ordenada, como si fuera tu primer día en el laboratorio.

---

## 1. Lo que necesito

Antes de empezar, asegúrate de contar con los siguientes elementos:

1. **Tu computadora con herramientas básicas:**
   - **Git:** para clonar el proyecto (`git --version`).
   - **Cliente SSH:** para conectarte a las terminales remotas (`ssh -V`).
   - **Make (opcional pero recomendado):** para automatizar la configuración con un solo comando (`make --version`).
2. **Acceso a la red física o Wi-Fi del laboratorio:**
   - Tu laptop debe estar conectada a la red Wi-Fi o por cable Ethernet del laboratorio (`192.168.29.0/24`). Si estás en otra red o en tu casa, los servidores físicos no responderán.
3. **Acceso al repositorio de GitLab:**
   - URL del repositorio: `https://gitlab.agetic.gob.bo/agetic/agcs/automatizacion/pasantia/pasantes-2026/k8s.git`
   - Necesitas tu usuario y contraseña (o Token de Acceso Personal) de GitLab de AGETIC.
4. **La llave privada SSH del clúster (`cluster_key`):**
   - Es un archivo de llave criptográfica tipo **Ed25519**.
   - El administrador del laboratorio debe entregártelo en un medio seguro (por ejemplo, mediante USB o canal cifrado).
5. **Datos de los servidores principales (Respaldo en [inventory/lab/hosts.yml](inventory/lab/hosts.yml#L1-L50)):**
   - **Servidor de entrada / Controlador:** Nodo 306 (`192.168.29.25`, puerto `22`, usuario `n306`).
   - **Servidores internos (Red privada `10.100.29.0/24`):**
     - Bastión de seguridad: `10.100.29.10`, usuario `aget-ic`.
     - Nexus y Base de Datos: `10.100.29.20`, usuario `io`.
     - Nodos de Kubernetes: `10.100.29.101` a `10.100.29.112`, usuario `debian`.

---

## 2. Descargar el proyecto y conectar al servidor

Sigue estos pasos en estricto orden:

### Paso 1. Descargar el repositorio
* **Dónde hacerlo:** En la terminal de tu computadora.
* **Qué hace:** Descarga todos los playbooks, scripts, inventarios y archivos de configuración del proyecto.
* **Comando:**
  ```bash
  git clone https://gitlab.agetic.gob.bo/agetic/agcs/automatizacion/pasantia/pasantes-2026/k8s.git infra-scripts
  ```
  *(Introduce tu usuario y contraseña/token de GitLab cuando el sistema lo solicite).*
* **Resultado esperado:**
  ```text
  Cloning into 'infra-scripts'...
  remote: Enumerating objects: 1250, done.
  Resolving deltas: 100% (680/680), done.
  ```

---

### Paso 2: Entrar a la carpeta del proyecto
* **Dónde hacerlo:** En la terminal de tu computadora.
* **Qué hace:** Te ubica en la raíz del repositorio donde se ejecutan todos los comandos y scripts.
* **Comando:**
  ```bash
  cd infra-scripts
  ```
* **Resultado esperado:**
  Tu terminal se situará dentro del directorio `infra-scripts/`.

---

### Paso 3: Colocar y proteger la llave SSH
* **Dónde hacerlo:** En la terminal de tu computadora.
* **Qué hace:** Copia la llave privada `cluster_key` dentro del proyecto y le da permisos estrictos de solo lectura para tu usuario (obligatorio por seguridad en SSH).
* **Comando:**
  ```bash
  # 1. Copia el archivo cluster_key que te entregaron dentro de ansible/keys/
  cp /ruta/donde/guardaste/cluster_key ansible/keys/cluster_key

  # 2. Asigna permisos estrictos 600 (solo tú puedes leerlo)
  chmod 600 ansible/keys/cluster_key
  ```
  *(Reemplaza `/ruta/donde/guardaste/cluster_key` por la ubicación real donde descargaste el archivo en tu máquina).*
* **Resultado esperado:**
  Al verificar con `ls -l ansible/keys/cluster_key`, los permisos deben mostrar `-rw-------`:
  ```text
  -rw------- 1 tu_usuario tu_usuario 411 cluster_key
  ```

---

### Paso 4. Configurar los accesos SSH

En tu laptop, edita `~/.ssh/config` y sustituye `RUTA_ABSOLUTA_AL_REPOSITORIO`
por la ruta real. Si ya tienes alguno de los alias, revisa su bloque antes de
añadir otro. Verifica las huellas de los equipos con el administrador antes
de aceptarlas.

```ssh-config
Host nodo-306 bastion nexus
    IdentityFile "RUTA_ABSOLUTA_AL_REPOSITORIO/ansible/keys/cluster_key"
    IdentitiesOnly yes

Host nodo-306
    HostName 192.168.29.25
    User n306

Host bastion
    HostName 10.100.29.10
    User aget-ic
    ProxyJump nodo-306

Host nexus
    HostName 10.100.29.20
    User io
    ProxyJump nodo-306
```

---

### Paso 5: Conectarse al servidor principal (Nodo Controlador)
* **Dónde hacerlo:** En la terminal de tu computadora.
* **Qué hace:** Abre una sesión interactiva en el servidor físico principal (`nodo-306`), que actúa como puerta de enlace y controlador de todo el laboratorio.
* **Comando:**
  ```bash
  ssh nodo-306
  ```
  *(O usando el comando directo tradicional sin atajo: `ssh -i ansible/keys/cluster_key n306@192.168.29.25`)*
* **Resultado esperado:**
  El comando `hostname` debe identificar al controlador
  `pxe-controller.lab.local`.
  *(Para salir y volver a tu computadora, escribe `exit`).*

---

### Paso 6: Conectarse a un servidor interno mediante salto (ProxyJump)
* **Dónde hacerlo:** En la terminal de tu computadora.
* **Qué hace:** Se conecta a los servidores de la red privada interna (`10.100.29.0/24`) saltando a través del controlador de forma totalmente transparente.
* **Comando:**
  Para entrar al Bastión:
  ```bash
  ssh bastion
  ```
  O para entrar al servidor de Nexus / Base de Datos:
  ```bash
  ssh nexus
  ```
* **Resultado esperado:**
  Estarás conectado dentro del servidor interno correspondiente sin necesidad de escribir contraseñas ni IPs:
  ```text
  aget-ic@bastion:~$
  ```

---

### Obtener el chart de Helm

Git registra `agetic-base-chart` como un repositorio anidado sin un mapeo en
`.gitmodules`. Si necesitas usarlo y el directorio no contiene el chart,
clona su repositorio por separado y selecciona el commit que muestra
`git ls-tree HEAD agetic-base-chart`.
[Repositorio del chart](https://gitlab.agetic.gob.bo/agetic/agetic/proyectos-base/agetic-base-chart)

---

## 3. Comprobación rápida

Desde tu computadora, comprueba el repositorio, la red y el acceso SSH:

1. **Comprobar la integridad del repositorio:**
   ```bash
   git status
   ```
   *Respuesta esperada:* `On branch main` (o tu rama activa) y `nothing to commit, working tree clean`.

2. **Comprobar la conectividad de red con el laboratorio:**
   ```bash
   ping -c 2 192.168.29.25
   ```
   *Respuesta esperada:* `2 packets transmitted, 2 received, 0% packet loss`.

3. **Comprobar la conexión SSH al controlador:**
   ```bash
   ssh nodo-306 "hostname && uptime"
   ```
   *Respuesta esperada:* El hostname del controlador y su tiempo de actividad.

4. **Comprobar el salto transparente (ProxyJump) al Bastión:**
   ```bash
   ssh bastion "hostname && ip -brief address show"
   ```
   *Respuesta esperada:* Mostrará `bastion` y su interfaz con la IP `10.100.29.10/24`.

5. **Comprobar el clúster de Kubernetes desde el maestro:**
   ```bash
   ssh nodo-306 "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes"
   ```
   *Respuesta esperada:* La lista de los nodos físicos del laboratorio con el estado `Ready`.

---

## 4. Problemas frecuentes

Si encuentras algún error durante la conexión o el uso de Git, consulta esta tabla rápida de soluciones:

| Error en la terminal | ¿Qué significa? | Solución en 1 o 2 pasos |
| :--- | :--- | :--- |
| **`Permission denied (publickey)`** | El servidor rechazó la llave SSH porque tiene permisos demasiado abiertos o el archivo no existe en esa ruta. | 1. Asegura permisos estrictos: `chmod 600 ansible/keys/cluster_key`<br>2. Verifica que el archivo exista: `ls -la ansible/keys/cluster_key` |
| **`No route to host` o ping no responde** | Tu laptop no puede comunicarse físicamente con la dirección `192.168.29.25`. | Conéctate a la red Wi-Fi o al cable de red del laboratorio de servidores (`192.168.29.x`). Verifica tu IP con `ip a` o `ipconfig`. |
| **`Could not resolve hostname nodo-306`** | El alias SSH falta o tiene otra configuración. | Revisa el bloque correspondiente en `~/.ssh/config` o conecta por IP con `ssh -i ansible/keys/cluster_key n306@192.168.29.25`. |
| **`Host key verification failed`** | La huella falta o difiere de la guardada. | Confirma la huella por un canal independiente. Si corresponde a un cambio autorizado, retira la entrada antigua y acepta la nueva. |
| **`fatal: Authentication failed for ...` al hacer git clone** | GitLab rechazó tus credenciales o expiró tu Personal Access Token. | Ingresa a [https://gitlab.agetic.gob.bo](https://gitlab.agetic.gob.bo), genera un nuevo **Personal Access Token** con permisos `read_repository` y úsalo como contraseña al clonar. |

---

## Archivos de referencia en el proyecto

Si deseas ver el código fuente y las configuraciones que respaldan esta guía:
- [Permisos y gestión de llaves](ansible/keys/README.md).
- [Inventario Ansible del laboratorio](inventory/lab/hosts.yml).
- [Roles y direcciones observados](docs/reference/estado-laboratorio.md).

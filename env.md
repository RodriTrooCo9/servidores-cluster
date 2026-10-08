### credenciales de las sonatype
- admin
- 70c7d98a-6561-40c3-b72f-9893b8eedd7d

### Ejecutable para la verificacion de puertos y ip
* ./healthcheck.sh

### listado de mac
id,mac,hostname,ip,role,ram_gb,disk_gb,bmc_ip
* 314,64:00:6a:2a:60:62,bastion,10.0.1.10,bastion,8,128,<BMC_IP_314>
* 315,64:00:6a:2a:5f:99,nexus-repo,10.0.1.20,nexus,16,128,<BMC_IP_315>
* 306,64:00:6a:2a:62:42,pxe-controller,10.0.1.30,pxe,16,128,<BMC_IP_306>
* 269,64:00:6a:2a:5f:f9,k8s-cp-01,10.0.1.101,k8s-control-plane-leader,16,128,<BMC_IP_269>
* 280,64:00:6a:2a:60:63,k8s-cp-02,10.0.1.102,k8s-control-plane,16,128,<BMC_IP_280>
* 320,64:00:6a:2a:2c:75,k8s-cp-03,10.0.1.103,k8s-control-plane,16,128,<BMC_IP_320>
* 321,64:00:6a:2a:62:a4,k8s-worker-01,10.0.1.111,k8s-worker,8,128,<BMC_IP_321>
* 279,64:00:6a:2a:2f:cb,k8s-worker-02,10.0.1.112,k8s-worker,8,128,<BMC_IP_279>


### Nodo 306 (PXE Controller)
ssh n306@192.168.29.25          // Contraseña: 306

### Nodo 314 (K8s Control Plane)
ssh aget-ic@192.168.21.107      // Contraseña: ag70v7

### Nodo 315 (K8s Worker)
ssh io@192.168.21.163           // Contraseña: 59766

### Nodo 321 *()


### Base de datos PostgreSQL:
* Base de datos: nexus
* Usuario: nexus
* Contraseña: NexusPgSecret2026_lab! -> (almacenada en config/env)

### token de verificacion 

`{"token":"DockerToken.ff416530-7b9b-37b1-8cde-f176dbcf197c"}`
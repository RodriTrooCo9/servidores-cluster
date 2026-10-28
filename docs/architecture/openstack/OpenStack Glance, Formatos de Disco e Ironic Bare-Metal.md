 ### Qué es Glance y dónde encaja en la Arquitectura OpenStack
OpenStack no es un programa único, sino un ecosistema modular de microservicios:
* **Keystone**: Servicio de identidad, autenticación (tokens) y catálogo de endpoints.
* **Glance**: Servicio de registro y distribución de imágenes de disco(iso). 
* **Nova**: Planificador (*scheduler*) y controlador del ciclo de vida de **Máquinas Virtuales** (hipervisores KVM/QEMU).
* **Ironic**: Hipervisor de **Metal Desnudo (*Bare-Metal*)**. En lugar de crear una VM, Ironic toma un servidor físico real, lo enciende por IPMI/WoL, escribe la imagen de disco directamente sobre el NVMe/SSD físico mediante un ramdisk auxiliar (**IPA - Ironic Python Agent**) y lo entrega como una instancia nativa.
* **Cinder**: Almacenamiento de bloques persistente (volúmenes tipo SAN/Ceph).

```text
               +----------------------------------+
               |        Keystone (Tokens)         |
               +----------------+-----------------+
                                |
             +------------------+------------------+
             |                                     |
+------------v-----------+              +----------v-------------+
|   Nova (Cómputo VM)    |              |  Ironic (Bare-Metal)   |
|   Lanza instancias KVM |              |  Aprovisiona Físicos   |
+------------+-----------+              +----------+-------------+
             |                                     |
             +------------------+------------------+
                                |
                   +------------v------------+
                   |  Glance (Catálogo de    |
                   |  Imágenes Doradas)      |
                   +-------------------------+
```
#### 3.3 Aclaración Técnica Fundamental: ¿Qué se puede hacer REALMENTE con una ISO en Glance?

> [!CAUTION]
> **Error Conceptual Común**: "Subir una ISO de Debian/Ubuntu a Glance para que Ironic la instale por PXE en los miniPCs".
> **Realidad de Ingeniería**: **Ironic NO instala sistemas operativos ejecutando instaladores interactivos desde una ISO.**

Diferenciemos los cuatro escenarios posibles:

| Escenario | ¿Cómo funciona? | ¿Usa Glance? | ¿Aplica a bare-metal? |
| :--- | :--- | :--- | :--- |
| **A. VM con CD-ROM virtual (Nova)** | Nova monta la ISO como lectora de CD virtual en KVM. Un humano debe abrir la consola VNC y hacer clic en "Siguiente". | **SÍ** | **NO** (Es una VM). |
| **B. Imagen Dorada (Packer + Ironic)** | Packer compila un Debian preinstalado con cloud-init en formato `.qcow2` o `.raw`. Ironic arranca un kernel temporal en RAM (**IPA**), vuelca la imagen directamente a los bloques del disco físico y reinicia. | **SÍ** | **SÍ** (Es el estándar de producción en OpenStack). |
| **C. Despliegue PXE Clásico con Instalador** | dnsmasq entrega kernel + initrd; el instalador de Debian corre en memoria y formatea el disco usando `preseed.cfg`. | **NO** (Usa Nginx/TFTP, no Glance). | **SÍ** (Es lo que configuramos en la Tarea 2). |
| **D. Arranque Live ISO en Bare-Metal** | Se carga una ISO completa en RAM con iPXE (`memdisk` o `sanboot`). Consume gigabytes de RAM y no persiste datos tras reiniciar. | **NO** | **NO** recomendado. |

# Artefactos para instalar sistemas operativos

Las imágenes de disco, ISO, kernels y ramdisks pertenecen al [proyecto de instalación de sistemas operativos](../GUIA_OPENSTACK.md). Los archivos pesados no se almacenan en Git.

El rol Ansible `ironic` prepara `/httpboot/ipa/ipa.kernel` y `/httpboot/ipa/ipa.initramfs` para la alternativa standalone. La configuración Kolla debe comprobarse por separado; ambas alternativas no comparten automáticamente todas sus rutas.

`download_ipa.sh` es una utilidad heredada que descarga artefactos a `artifacts/openstack/` y calcula un archivo `SHA256SUMS` local. Calcular un hash después de descargar no verifica la autenticidad del proveedor. La guía principal no exige ejecutar esta utilidad Bash.

Antes de una instalación por red, valida la versión de IPA, la procedencia de la imagen, sus hashes y el acceso desde el conductor y desde la máquina destino.

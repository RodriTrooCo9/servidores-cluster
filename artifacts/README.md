# Gestión de Artefactos Binarios de Infraestructura

Para mantener el repositorio liviano y ágil, los binarios pesados (imágenes ISO, QCOW2, ramdisks IPA y kernels) **no se almacenan en Git**.


## Descarga de Artefactos de OpenStack Ironic
Para descargar o actualizar los binarios necesarios para el aprovisionamiento bare-metal:
```bash
./artifacts/download_ipa.sh
```
El script descargará las imágenes oficiales estables y generará el archivo `SHA256SUMS`.

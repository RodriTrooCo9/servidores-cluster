# Gestión de Artefactos Binarios de Infraestructura

Para mantener el repositorio liviano y ágil, los binarios pesados (imágenes ISO, QCOW2, ramdisks IPA y kernels) **no se almacenan en Git**.

## Estructura
```text
artifacts/
├── .gitkeep
├── download_ipa.sh            # Script de descarga y validación de hash de IPA
├── openstack/                 # [GITIGNORED] Binarios ironic-agent.kernel e initramfs
└── README.md
```

## Descarga de Artefactos de OpenStack Ironic
Para descargar o actualizar los binarios necesarios para el aprovisionamiento bare-metal:
```bash
./artifacts/download_ipa.sh
```
El script descargará las imágenes oficiales estables y generará el archivo `SHA256SUMS`.

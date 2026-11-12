#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 4 ]]; then
    echo 'Uso: bash prepare-artifacts.sh DEBIAN_NETBOOT_DIR IPXE_GIT_DIR [SALIDA] [MANIFIESTO_DEBIAN]' >&2
    exit 2
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
netboot_dir=$(realpath -- "$1")
ipxe_checkout=$(realpath -- "$2")
output_dir=$(realpath -m -- "${3:-$script_dir/../../../artifacts/debian-netboot}")
manifest=$(realpath -- "${4:-$script_dir/debian13.sha256}")
ipxe_commit=582852868c6a68db138cd5c99719b8395ce24686

if [[ $(awk '{print $2}' "$manifest" | sort) != $'initrd.gz\nlinux' ]]; then
    echo 'El manifiesto Debian debe contener exactamente linux e initrd.gz.' >&2
    exit 2
fi

work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT
mkdir -p -- "$work_dir/ipxe" "$work_dir/artifacts/debian13" "$work_dir/artifacts/tftp"

# Verificar la copia que se va a publicar, conservando el par del mismo instalador.
install -m 0644 -- "$netboot_dir/linux" "$netboot_dir/initrd.gz" "$work_dir/artifacts/debian13/"
(
    cd -- "$work_dir/artifacts/debian13"
    sha256sum --check --strict -- "$manifest"
    gzip -t initrd.gz
)

# Compilar en una copia temporal, sin modificar el checkout de origen.
git -C "$ipxe_checkout" archive "$ipxe_commit" | tar -xf - -C "$work_dir/ipxe"
make -C "$work_dir/ipxe/src" -j "$(nproc)" bin/undionly.kpxe bin-x86_64-efi/snponly.efi EMBED="$script_dir/embed.ipxe"
install -m 0644 -- "$work_dir/ipxe/src/bin/undionly.kpxe" \
    "$work_dir/ipxe/src/bin-x86_64-efi/snponly.efi" "$work_dir/artifacts/tftp/"

mkdir -p -- "$output_dir/debian13" "$output_dir/tftp"
install -m 0644 -- "$work_dir/artifacts/debian13/"* "$output_dir/debian13/"
install -m 0644 -- "$work_dir/artifacts/tftp/"* "$output_dir/tftp/"
(
    cd -- "$output_dir"
    sha256sum debian13/linux debian13/initrd.gz tftp/undionly.kpxe tftp/snponly.efi > SHA256SUMS
)
printf 'Artefactos preparados en %s\n' "$output_dir"

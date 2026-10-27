# Capa de Redes, DNSMASQ y Seguridad Perimetral

Este directorio agrupa la configuración de red física y lógica, booteo por red (iPXE), cortafuegos perimetral y diagramas de aislamiento.

## Estructura
```text
network/
├── dnsmasq/
│   └── dnsmasq.conf                   # Configuración DHCP estático por MAC y TFTP
├── ipxe/
│   └── compilar-ipxe-custom.sh        # Toolchain para compilar iPXE optimizado (Dell 3020M)
├── firewall/
│   └── apply-nftables-observability.sh # Reglas nftables para puertos de telemetría
├── topology/
│   └── network_diagram.mmd            # Diagrama Mermaid de la topología L2/L3
└── README.md
```

## Aislamiento de Red
- **Subred Privada Bare-Metal**: `10.100.29.0/24`.
- **Gateway Interno**: `10.100.29.10` (Bastion Nodo 314).
- **Puerta de Enlace Egress**: Todo el tráfico saliente hacia Internet debe cursarse a través del proxy Squid (`10.100.29.10:3128`).
- **Seguridad DHCP**: `dnsmasq` está amarrado exclusivamente a las MACs registradas en `inventory/nodes.csv` mediante la directiva `dhcp-ignore=tag:!known`.

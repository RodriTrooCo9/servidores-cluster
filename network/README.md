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

## Red del laboratorio

- La LAN privada usa `10.100.29.0/24`. El nodo 306 conecta esa LAN en
  `10.100.29.30` y recibe el acceso de administración en `192.168.29.25`.
- El plano de control de RKE2 está en el 306. Confirma los roles efectivos y
  las direcciones antes de tocar la red del controlador. [Estado del laboratorio](../docs/reference/estado-laboratorio.md)
- La IP `10.100.29.10` corresponde al bastión y su proxy Squid. Antes de
  modificar el encaminamiento, comprueba las rutas y los filtros efectivos.
  [Matriz de servicios](../docs/reference/puertos_y_servicios.md)

## Aislamiento del arranque por red

Mantén un solo servicio DHCP de aprovisionamiento por segmento. Verifica el
aislamiento del switch o VLAN antes de conectar equipos. Un rango de IP distinto
puede seguir generando respuestas DHCP competidoras en el mismo segmento.
Restringe la publicación de NoCloud a la red que usarán los equipos destino.

En el controlador, estas consultas ayudan a identificar la interfaz, las rutas
y los procesos que atienden el arranque. Desde la red de aprovisionamiento,
comprueba también quién responde a las peticiones DHCP y si HTTPBoot es accesible.

```bash
ip -br addr
ip route
sudo ss -lunp '( sport = :67 or sport = :69 )'
sudo ss -ltnp '( sport = :8088 or sport = :8089 )'
```

Para cambiar interfaces o filtros del 306, prepara primero el acceso por consola
y un procedimiento de reversión. Perder su red LAN afecta tanto al
aprovisionamiento como al plano de control de RKE2.

- [Instalación con Ironic](../GUIA_OPENSTACK.md)
- [Piloto Debian con iPXE y preseed](ipxe/debian-netboot/README.md)

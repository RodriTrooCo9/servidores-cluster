#!/usr/bin/env python3
"""Publish Debian Installer and issue one iPXE install script per approved attempt."""

import argparse
import ipaddress
import json
import os
import re
import shutil
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


IMAGE_NAMES = {"linux", "initrd.gz"}
LOCAL_BOOT = (
    "#!ipxe\n"
    "iseq ${platform} efi && exit 0 || sanboot --no-describe --drive 0x80 || exit 0\n"
)


def read_settings(path):
    with path.open(encoding="utf-8") as stream:
        settings = json.load(stream)

    controller = ipaddress.IPv4Interface(settings["address"])
    network = controller.network
    gateway = ipaddress.IPv4Address(settings["gateway"])
    if gateway not in network or gateway in (network.network_address, network.broadcast_address):
        raise ValueError("La puerta de enlace debe ser una IP utilizable en la subred PXE")
    ipaddress.IPv4Address(settings["dns"])
    settings["ip"] = str(controller.ip)
    if not 1024 <= settings["port"] <= 65535:
        raise ValueError("El puerto HTTP debe estar entre 1024 y 65535")

    addresses = {controller.ip, gateway, network.network_address, network.broadcast_address}
    for mac, profile in settings["nodes"].items():
        address = ipaddress.IPv4Address(profile["address"])
        if address not in network or address in addresses:
            raise ValueError(f"IP de destino fuera de la subred, reservada o repetida: {address}")
        addresses.add(address)
        if not re.fullmatch(r"[0-9a-f]{2}(?::[0-9a-f]{2}){5}", mac):
            raise ValueError(f"MAC inválida: {mac}")
        if profile["attempt"] and not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", profile["attempt"]):
            raise ValueError(f"Identificador de intento inválido para {mac}")

    settings["images"] = Path(settings["images"])
    for name in IMAGE_NAMES:
        if not (settings["images"] / name).is_file():
            raise ValueError(f"Falta el artefacto {name}")
    return settings


def claim_attempt(marker):
    try:
        with marker.open("x", encoding="utf-8") as stream:
            stream.write("issued\n")
            stream.flush()
            os.fsync(stream.fileno())
    except FileExistsError:
        return False

    directory_fd = os.open(marker.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)
    return True


class NetbootHandler(BaseHTTPRequestHandler):
    def setup(self):
        self.request.settimeout(30)
        super().setup()

    def respond(self, data, content_type="text/plain; charset=utf-8"):
        data = data.encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command == "GET":
            self.wfile.write(data)

    def serve_image(self, name):
        with (self.server.settings["images"] / name).open("rb") as stream:
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(os.fstat(stream.fileno()).st_size))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            if self.command == "GET":
                shutil.copyfileobj(stream, self.wfile)

    def serve_node(self, action, mac, attempt):
        profile = self.server.settings["nodes"].get(mac)
        if profile and profile["attempt"] and profile["address"] == self.client_address[0]:
            marker = self.server.state_dir / f"{mac.replace(':', '')}-{profile['attempt']}"
            if action == "install" and self.command == "GET" and claim_attempt(marker):
                self.log_message("Instalación habilitada para %s, intento %s", mac, profile["attempt"])
                return self.respond(profile["installer"])
            if action == "preseed" and attempt == profile["attempt"] and marker.is_file():
                return self.respond(profile["preseed"])

        if action == "install":
            return self.respond(LOCAL_BOOT)
        self.send_error(HTTPStatus.NOT_FOUND)

    def do_GET(self):
        route = self.path.partition('?')[0]
        if route == "/healthz":
            return self.respond("ok\n")
        if route == "/boot.ipxe":
            return self.respond(self.server.settings["boot"])

        parts = route.split("/")
        if len(parts) == 3 and parts[1] == "debian13" and parts[2] in IMAGE_NAMES:
            return self.serve_image(parts[2])
        if len(parts) == 3 and parts[1] == "install":
            return self.serve_node(parts[1], parts[2].lower(), None)
        if len(parts) == 4 and parts[1] == "preseed":
            return self.serve_node(parts[1], parts[2].lower(), parts[3])
        self.send_error(HTTPStatus.NOT_FOUND)

    do_HEAD = do_GET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("settings", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        settings = read_settings(args.settings)
    except (OSError, KeyError, ValueError) as error:
        parser.error(str(error))
    if args.check:
        return

    with ThreadingHTTPServer((settings["ip"], settings["port"]), NetbootHandler) as server:
        server.settings = settings
        server.state_dir = Path(os.environ["STATE_DIRECTORY"])
        server.serve_forever()


if __name__ == "__main__":
    main()

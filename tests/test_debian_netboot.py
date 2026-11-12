import importlib.util
import json
import unittest
from concurrent.futures import ThreadPoolExecutor
from http.client import HTTPConnection
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Thread


SERVER_FILE = Path(__file__).resolve().parents[1] / 'ansible/roles/debian_netboot/files/server.py'
SPEC = importlib.util.spec_from_file_location('debian_netboot', SERVER_FILE)
NETBOOT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NETBOOT)


class NetbootTest(unittest.TestCase):
    def setUp(self):
        scratch = TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.state_dir = Path(scratch.name)
        self.mac = '64:00:6a:2a:2f:cb'
        self.settings = {
            'boot': '#!ipxe\n',
            'nodes': {
                self.mac: {'address': '127.0.0.1', 'attempt': 'piloto-01',
                           'installer': '#!ipxe\nboot installer\n', 'preseed': 'test preseed\n'},
            },
        }

    def start_server(self):
        server = NETBOOT.ThreadingHTTPServer(('127.0.0.1', 0), NETBOOT.NetbootHandler)
        server.settings = self.settings
        server.state_dir = self.state_dir
        thread = Thread(target=server.serve_forever)
        thread.start()
        self.addCleanup(thread.join)
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return server.server_port

    def request(self, port, route, method='GET'):
        connection = HTTPConnection('127.0.0.1', port, timeout=3)
        try:
            connection.request(method, route)
            response = connection.getresponse()
            return response.status, response.read().decode()
        finally:
            connection.close()

    def test_concurrent_boot_only_issues_one_script_and_survives_restart(self):
        install = f'/install/{self.mac}'
        preseed = f'/preseed/{self.mac}/piloto-01'
        port = self.start_server()
        self.assertEqual(self.request(port, preseed)[0], 404)
        self.assertEqual(self.request(port, install, method='HEAD')[0], 200)
        with ThreadPoolExecutor(max_workers=4) as clients:
            responses = list(clients.map(lambda _: self.request(port, install)[1], range(4)))
        self.assertEqual(responses.count('#!ipxe\nboot installer\n'), 1)
        self.assertEqual(responses.count(NETBOOT.LOCAL_BOOT), 3)
        self.assertEqual(self.request(port, preseed), (200, 'test preseed\n'))
        self.assertEqual(self.request(self.start_server(), install), (200, NETBOOT.LOCAL_BOOT))

    def test_unknown_wrong_address_and_disarmed_nodes_boot_locally(self):
        profile = self.settings['nodes'][self.mac]
        profile['address'] = '127.0.0.2'
        port = self.start_server()
        self.assertEqual(self.request(port, f'/install/{self.mac}'), (200, NETBOOT.LOCAL_BOOT))
        self.assertEqual(self.request(port, '/install/64:00:6a:2a:00:00'), (200, NETBOOT.LOCAL_BOOT))
        profile.update(address='127.0.0.1', attempt='')
        self.assertEqual(self.request(port, f'/install/{self.mac}'), (200, NETBOOT.LOCAL_BOOT))
        self.assertEqual(list(self.state_dir.iterdir()), [])

    def test_duplicate_destination_ip_is_rejected(self):
        self.settings.update(address='10.100.29.30/24', gateway='10.100.29.30',
                             dns='192.168.26.120', port=8088, images=str(self.state_dir))
        profile = self.settings['nodes'][self.mac]
        profile['address'] = '10.100.29.112'
        self.settings['nodes']['64:00:6a:2a:60:63'] = profile.copy()
        path = self.state_dir / 'settings.json'
        path.write_text(json.dumps(self.settings), encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'repetida'):
            NETBOOT.read_settings(path)

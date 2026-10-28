"""Ejecuta el pipeline real de respaldo con un docker simulado."""
import gzip
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("gzip"), "gzip no disponible")
class BackupPipelineTests(unittest.TestCase):
    def run_dump(self, exit_code, contents):
        with tempfile.TemporaryDirectory(prefix="infra-dump-test-") as directory:
            folder = Path(directory)
            docker = folder / "docker"
            docker.write_text('#!/bin/bash\nprintf "%s" "$INFRA_TEST_SQL"\nexit "$INFRA_TEST_DOCKER_EXIT"\n')
            docker.chmod(0o700)
            source = (ROOT / "ansible/playbooks/90-operations/01_disaster_recovery.yml").read_text()
            body = source.split('cmd: |\n          set -euo pipefail\n', 1)[1].split('      environment:', 1)[0]
            command = 'set -euo pipefail\n' + textwrap.dedent(body)
            command = command.replace('/var/backups/openstack', str(folder))
            command = command.replace('{{ ansible_date_time.iso8601_basic_short }}', 'test')
            env = dict(os.environ, PATH=str(folder) + ':' + os.environ['PATH'],
                       INFRA_TEST_SQL=contents, INFRA_TEST_DOCKER_EXIT=str(exit_code))
            result = subprocess.run(['bash', '-c', command], env=env,
                                    capture_output=True, text=True, timeout=10)
            published = folder / 'mariadb_dump_test.sql.gz'
            data = gzip.decompress(published.read_bytes()) if published.exists() else None
            self.assertEqual(list(folder.glob('.dump.*')), [], 'No debe quedar un respaldo parcial')
            return result, data

    def test_partial_dump_failure_is_not_published(self):
        result, data = self.run_dump(7, 'partial SQL')
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(data)

    def test_empty_dump_is_not_published(self):
        result, data = self.run_dump(0, '')
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(data)

    def test_successful_dump_is_readable(self):
        result, data = self.run_dump(0, '-- SQL backup\nCREATE DATABASE example;\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(b'CREATE DATABASE example;', data)

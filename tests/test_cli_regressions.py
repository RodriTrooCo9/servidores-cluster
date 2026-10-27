"""Pruebas de CLI sin SSH, despliegues ni credenciales reales."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class CommandLineTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="infra-cli-test-")
        self.addCleanup(self.directory.cleanup)
        self.bin = Path(self.directory.name)
        self.calls = self.bin / "calls.jsonl"
        stub = '''#!/usr/bin/env python3
import json, os, sys
with open(os.environ["INFRA_TEST_CALLS"], "a") as output:
    output.write(json.dumps({"command": os.path.basename(sys.argv[0]),
                            "args": sys.argv[1:], "cwd": os.getcwd(),
                            "config": os.environ.get("ANSIBLE_CONFIG")}) + "\\n")
sys.exit(int(os.environ.get("INFRA_TEST_EXIT", "0")))
'''
        for name in ("ansible", "ansible-playbook", "ssh", "scp"):
            executable = self.bin / name
            executable.write_text(stub)
            executable.chmod(0o700)
        self.env = dict(os.environ, PATH=str(self.bin) + ":" + os.environ["PATH"],
                        INFRA_TEST_CALLS=str(self.calls))

    def invoke(self, script, *args):
        return subprocess.run(["bash", str(ROOT / script), *args], cwd=self.bin,
                              env=self.env, capture_output=True, text=True, timeout=15)

    def recorded(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def test_dry_run_before_and_after_phase(self):
        for args in (("--fase", "8", "--dry-run"), ("--dry-run", "--fase", "8")):
            with self.subTest(args=args):
                result = self.invoke("scripts/client/ejecutar-desde-laptop.sh", *args)
                self.assertEqual(result.returncode, 0, result.stderr)
                call = self.recorded()[-1]
                self.assertIn("--check", call["args"])
                self.assertIn("--diff", call["args"])
                self.assertEqual(call["cwd"], str(ROOT))
                self.assertEqual(call["config"], str(ROOT / "ansible.cfg"))

    def test_all_dry_run_does_not_wait_for_confirmation(self):
        result = self.invoke("scripts/client/ejecutar-desde-laptop.sh", "--all", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--check", self.recorded()[-1]["args"])

    def test_invalid_trailing_argument_runs_nothing(self):
        result = self.invoke("scripts/client/ejecutar-desde-laptop.sh", "--fase", "8", "--invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.recorded(), [])

    def test_missing_phase_runs_nothing(self):
        result = self.invoke("scripts/client/ejecutar-desde-laptop.sh", "--fase")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.recorded(), [])

    def test_backup_uses_inventory_playbook(self):
        result = self.invoke("scripts/ops/disaster-recovery.sh", "--backup-etcd")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.recorded()
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0]["command"], "ansible-playbook")
        self.assertEqual(calls[0]["args"][-2:], ["--tags", "backup_etcd"])

    def test_backup_failure_is_not_success(self):
        self.env["INFRA_TEST_EXIT"] = "7"
        result = self.invoke("scripts/ops/disaster-recovery.sh", "--backup-all")
        self.assertEqual(result.returncode, 7)
        self.assertNotIn("transferencia completados", result.stdout)

    def test_invalid_mac_before_reprovision_runs_nothing(self):
        result = self.invoke("scripts/ops/disaster-recovery.sh", "--reprovision", "nodo-280",
                             "--new-mac", "invalid")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.recorded(), [])

    def test_multiple_recovery_actions_run_nothing(self):
        result = self.invoke("scripts/ops/disaster-recovery.sh", "--backup-etcd", "--audit")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.recorded(), [])


if __name__ == "__main__":
    unittest.main()

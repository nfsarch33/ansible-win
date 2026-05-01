from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class PlaybookTests(unittest.TestCase):
    def test_mem0_outbox_playbook_exists_and_installs_service(self):
        playbook = ROOT / "ansible" / "playbooks" / "mem0-outbox-wsl.yml"
        text = playbook.read_text(encoding="utf-8")

        self.assertIn("cursor-mem0-outbox.service", text)
        self.assertIn("mem0-outbox flush", text)
        self.assertIn("queue.ndjson", text)
        self.assertIn("queue.cursor", text)

    def test_dual_run_parity_playbook_checks_current_and_legacy_paths(self):
        playbook = ROOT / "ansible" / "playbooks" / "devops-sysadmin-dual-run-parity.yml"
        text = playbook.read_text(encoding="utf-8")

        self.assertIn("LEGACY_DEVOPS_SYSADMIN_BUNDLE", text)
        self.assertIn("ansible-win DevOps/SysAdmin bundle", text)
        self.assertIn("legacy DevOps/SysAdmin bundle", text)
        self.assertIn("windows-mcp-config.json", text)
        self.assertIn("CURRENT_WINDOWS_FACTS", text)
        self.assertIn("LEGACY_WINDOWS_FACTS", text)
        self.assertIn("windows_fact_mismatches", text)


if __name__ == "__main__":
    unittest.main()

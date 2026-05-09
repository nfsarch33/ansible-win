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


if __name__ == "__main__":
    unittest.main()

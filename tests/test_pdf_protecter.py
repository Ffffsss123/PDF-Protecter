import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "pdf_protecter.py"


def minimal_pdf(label: str) -> bytes:
    return (
        b"%PDF-1.4\n"
        b"1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n"
        b"2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n"
        b"3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] "
        b"/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >> endobj\n"
        b"4 0 obj << /Length "
        + str(38 + len(label)).encode()
        + b" >> stream\nBT /F1 18 Tf 20 100 Td ("
        + label.encode()
        + b") Tj ET\nendstream endobj\n"
        b"5 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n"
        b"trailer << /Root 1 0 R >>\n%%EOF\n"
    )


def run_cli(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(CLI), *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )


class PdfProtecterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.temp_dir.name)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def write_fixture_pdfs(self) -> tuple[Path, Path, Path, Path]:
        real = self.tmp_path / "real.pdf"
        decoy = self.tmp_path / "decoy.pdf"
        safe = self.tmp_path / "doc.safe"
        out = self.tmp_path / "out.pdf"
        real.write_bytes(minimal_pdf("REAL"))
        decoy.write_bytes(minimal_pdf("DECOY"))
        return real, decoy, safe, out

    def create_container(self, real: Path, decoy: Path, safe: Path, *extra_args: str) -> None:
        created = run_cli(
            "create",
            "--real",
            str(real),
            "--decoy",
            str(decoy),
            "--out",
            str(safe),
            "--password",
            "secret",
            *extra_args,
        )
        self.assertEqual(created.returncode, 0, created.stderr)

    def test_correct_password_writes_real_pdf(self) -> None:
        real, decoy, safe, out = self.write_fixture_pdfs()
        self.create_container(real, decoy, safe)

        opened = run_cli("open", "--in", str(safe), "--out", str(out), "--password", "secret")

        self.assertEqual(opened.returncode, 0, opened.stderr)
        self.assertEqual(out.read_bytes(), real.read_bytes())
        self.assertIn("real PDF", opened.stdout)

    def test_wrong_password_writes_decoy_pdf(self) -> None:
        real, decoy, safe, out = self.write_fixture_pdfs()
        self.create_container(real, decoy, safe)

        opened = run_cli("open", "--in", str(safe), "--out", str(out), "--password", "wrong")

        self.assertEqual(opened.returncode, 0, opened.stderr)
        self.assertEqual(out.read_bytes(), decoy.read_bytes())
        self.assertIn("decoy PDF", opened.stdout)

    def test_inspect_outputs_non_secret_metadata(self) -> None:
        real, decoy, safe, _ = self.write_fixture_pdfs()
        self.create_container(real, decoy, safe)

        inspected = run_cli("inspect", "--in", str(safe))

        self.assertEqual(inspected.returncode, 0, inspected.stderr)
        metadata = json.loads(inspected.stdout)
        self.assertEqual(metadata["format"], "safe-v1")
        self.assertEqual(metadata["real_name"], "real.pdf")
        self.assertEqual(metadata["decoy_name"], "decoy.pdf")

    def test_change_password_updates_container(self) -> None:
        real, decoy, safe, _ = self.write_fixture_pdfs()
        updated = self.tmp_path / "updated.safe"
        old_password_out = self.tmp_path / "old-password.pdf"
        new_password_out = self.tmp_path / "new-password.pdf"
        self.create_container(real, decoy, safe)

        changed = run_cli(
            "change-password",
            "--in",
            str(safe),
            "--out",
            str(updated),
            "--current-password",
            "secret",
            "--new-password",
            "new-secret",
        )
        self.assertEqual(changed.returncode, 0, changed.stderr)

        opened_with_new = run_cli("open", "--in", str(updated), "--out", str(new_password_out), "--password", "new-secret")
        self.assertEqual(opened_with_new.returncode, 0, opened_with_new.stderr)
        self.assertEqual(new_password_out.read_bytes(), real.read_bytes())

        opened_with_old = run_cli("open", "--in", str(updated), "--out", str(old_password_out), "--password", "secret")
        self.assertEqual(opened_with_old.returncode, 0, opened_with_old.stderr)
        self.assertEqual(old_password_out.read_bytes(), decoy.read_bytes())

    def test_change_password_rejects_wrong_current_password(self) -> None:
        real, decoy, safe, _ = self.write_fixture_pdfs()
        updated = self.tmp_path / "updated.safe"
        self.create_container(real, decoy, safe)

        changed = run_cli(
            "change-password",
            "--in",
            str(safe),
            "--out",
            str(updated),
            "--current-password",
            "wrong",
            "--new-password",
            "new-secret",
        )

        self.assertNotEqual(changed.returncode, 0)
        self.assertFalse(updated.exists())

    def test_wrong_password_attempts_destroy_real_payload_at_threshold(self) -> None:
        real, decoy, safe, out = self.write_fixture_pdfs()
        self.create_container(real, decoy, safe, "--self-destruct-after", "3")

        for attempt in range(1, 4):
            opened = run_cli("open", "--in", str(safe), "--out", str(out), "--password", f"wrong-{attempt}")
            self.assertEqual(opened.returncode, 0, opened.stderr)
            self.assertEqual(out.read_bytes(), decoy.read_bytes())

        inspected = run_cli("inspect", "--in", str(safe))
        self.assertEqual(inspected.returncode, 0, inspected.stderr)
        metadata = json.loads(inspected.stdout)
        self.assertTrue(metadata["destroyed"])
        self.assertEqual(metadata["failed_attempts"], 3)

        opened_with_correct_password = run_cli("open", "--in", str(safe), "--out", str(out), "--password", "secret")
        self.assertEqual(opened_with_correct_password.returncode, 0, opened_with_correct_password.stderr)
        self.assertEqual(out.read_bytes(), decoy.read_bytes())
        self.assertIn("destroyed", opened_with_correct_password.stdout)

    def test_correct_password_resets_failed_attempt_counter(self) -> None:
        real, decoy, safe, out = self.write_fixture_pdfs()
        self.create_container(real, decoy, safe, "--self-destruct-after", "3")

        opened_wrong = run_cli("open", "--in", str(safe), "--out", str(out), "--password", "wrong")
        self.assertEqual(opened_wrong.returncode, 0, opened_wrong.stderr)

        opened_right = run_cli("open", "--in", str(safe), "--out", str(out), "--password", "secret")
        self.assertEqual(opened_right.returncode, 0, opened_right.stderr)
        self.assertEqual(out.read_bytes(), real.read_bytes())

        inspected = run_cli("inspect", "--in", str(safe))
        self.assertEqual(inspected.returncode, 0, inspected.stderr)
        metadata = json.loads(inspected.stdout)
        self.assertFalse(metadata["destroyed"])
        self.assertEqual(metadata["failed_attempts"], 0)


if __name__ == "__main__":
    unittest.main()

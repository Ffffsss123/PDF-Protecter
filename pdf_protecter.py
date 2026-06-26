#!/usr/bin/env python3
"""Create and open password-gated PDF containers with a decoy PDF fallback."""

from __future__ import annotations

import argparse
import getpass
import hashlib
import hmac
import json
import os
import struct
import sys
import zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import BinaryIO


MAGIC = b"SAFEv1"
MANIFEST = "manifest.json"
DECOY = "decoy.pdf"
REAL = "real.enc"
PDF_HEADER = b"%PDF-"
SCRYPT_N = 2**14
SCRYPT_R = 8
SCRYPT_P = 1
PBKDF2_ITERATIONS = 600_000
KEY_LEN = 64


class PdfSafeError(Exception):
    """Raised for expected container and crypto errors."""


@dataclass(frozen=True)
class OpenResult:
    """Result of opening a container."""

    real_was_written: bool
    destroyed: bool = False
    failed_attempts: int = 0
    remaining_attempts: int | None = None


def _rotl32(value: int, bits: int) -> int:
    return ((value << bits) & 0xFFFFFFFF) | (value >> (32 - bits))


def _quarter_round(state: list[int], a: int, b: int, c: int, d: int) -> None:
    state[a] = (state[a] + state[b]) & 0xFFFFFFFF
    state[d] ^= state[a]
    state[d] = _rotl32(state[d], 16)
    state[c] = (state[c] + state[d]) & 0xFFFFFFFF
    state[b] ^= state[c]
    state[b] = _rotl32(state[b], 12)
    state[a] = (state[a] + state[b]) & 0xFFFFFFFF
    state[d] ^= state[a]
    state[d] = _rotl32(state[d], 8)
    state[c] = (state[c] + state[d]) & 0xFFFFFFFF
    state[b] ^= state[c]
    state[b] = _rotl32(state[b], 7)


def _chacha20_block(key: bytes, nonce: bytes, counter: int) -> bytes:
    constants = b"expand 32-byte k"
    state = list(struct.unpack("<4I", constants))
    state.extend(struct.unpack("<8I", key))
    state.append(counter & 0xFFFFFFFF)
    state.extend(struct.unpack("<3I", nonce))
    working = state.copy()

    for _ in range(10):
        _quarter_round(working, 0, 4, 8, 12)
        _quarter_round(working, 1, 5, 9, 13)
        _quarter_round(working, 2, 6, 10, 14)
        _quarter_round(working, 3, 7, 11, 15)
        _quarter_round(working, 0, 5, 10, 15)
        _quarter_round(working, 1, 6, 11, 12)
        _quarter_round(working, 2, 7, 8, 13)
        _quarter_round(working, 3, 4, 9, 14)

    return struct.pack("<16I", *[(working[i] + state[i]) & 0xFFFFFFFF for i in range(16)])


def _chacha20_xor(data: bytes, key: bytes, nonce: bytes, counter: int = 1) -> bytes:
    output = bytearray()
    for offset in range(0, len(data), 64):
        block = _chacha20_block(key, nonce, counter)
        chunk = data[offset : offset + 64]
        output.extend(byte ^ block[index] for index, byte in enumerate(chunk))
        counter += 1
    return bytes(output)


def _preferred_kdf() -> dict:
    if hasattr(hashlib, "scrypt"):
        return {"name": "scrypt", "n": SCRYPT_N, "r": SCRYPT_R, "p": SCRYPT_P}
    return {"name": "pbkdf2-sha256", "iterations": PBKDF2_ITERATIONS}


def _derive_keys(password: str, salt: bytes, kdf: dict) -> tuple[bytes, bytes]:
    password_bytes = password.encode("utf-8")
    if kdf.get("name") == "scrypt":
        if not hasattr(hashlib, "scrypt"):
            raise PdfSafeError("This Python build cannot open scrypt-based containers.")
        key_material = hashlib.scrypt(
            password_bytes,
            salt=salt,
            n=int(kdf["n"]),
            r=int(kdf["r"]),
            p=int(kdf["p"]),
            dklen=KEY_LEN,
        )
    elif kdf.get("name") == "pbkdf2-sha256":
        key_material = hashlib.pbkdf2_hmac(
            "sha256",
            password_bytes,
            salt,
            int(kdf["iterations"]),
            dklen=KEY_LEN,
        )
    else:
        raise PdfSafeError("Unsupported key derivation function.")
    return key_material[:32], key_material[32:]


def _mac(mac_key: bytes, salt: bytes, nonce: bytes, ciphertext: bytes) -> bytes:
    return hmac.new(mac_key, MAGIC + salt + nonce + ciphertext, hashlib.sha256).digest()


def _validate_pdf_bytes(data: bytes, label: str) -> None:
    if not data.startswith(PDF_HEADER):
        raise PdfSafeError(f"{label} does not look like a PDF file.")


def _validate_pdf(path: Path) -> None:
    with path.open("rb") as handle:
        _validate_pdf_bytes(handle.read(len(PDF_HEADER)), str(path))


def _read_member(container: zipfile.ZipFile, name: str) -> bytes:
    try:
        return container.read(name)
    except KeyError as exc:
        raise PdfSafeError(f"Container is missing {name}.") from exc


def _read_manifest(container: zipfile.ZipFile) -> dict:
    try:
        manifest = json.loads(_read_member(container, MANIFEST).decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise PdfSafeError("Container manifest is not valid JSON.") from exc
    if manifest.get("format") != "safe-v1":
        raise PdfSafeError("Unsupported container format.")
    return manifest


def _atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_name(f".{path.name}.tmp")
    with temp_path.open("wb") as handle:
        handle.write(data)
    os.replace(temp_path, path)


def _write_container(
    real_pdf_data: bytes,
    decoy_pdf_data: bytes,
    output: Path,
    password: str,
    real_name: str,
    decoy_name: str,
    self_destruct_after: int | None = None,
) -> None:
    _validate_pdf_bytes(real_pdf_data, real_name)
    _validate_pdf_bytes(decoy_pdf_data, decoy_name)
    if not password:
        raise PdfSafeError("Password cannot be empty.")
    if self_destruct_after is not None and self_destruct_after < 1:
        raise PdfSafeError("Self-destruct attempts must be at least 1.")

    salt = os.urandom(16)
    nonce = os.urandom(12)
    kdf = _preferred_kdf()
    enc_key, mac_key = _derive_keys(password, salt, kdf)
    ciphertext = _chacha20_xor(real_pdf_data, enc_key, nonce)
    tag = _mac(mac_key, salt, nonce, ciphertext)

    manifest = {
        "format": "safe-v1",
        "kdf": kdf,
        "cipher": "chacha20",
        "mac": "hmac-sha256",
        "salt": salt.hex(),
        "nonce": nonce.hex(),
        "tag": tag.hex(),
        "real_name": real_name,
        "decoy_name": decoy_name,
        "failed_attempts": 0,
    }
    if self_destruct_after is not None:
        manifest["self_destruct_after"] = self_destruct_after

    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as container:
        container.writestr(MANIFEST, json.dumps(manifest, indent=2, sort_keys=True))
        container.writestr(DECOY, decoy_pdf_data)
        container.writestr(REAL, ciphertext)


def create_container(
    real_pdf: Path,
    decoy_pdf: Path,
    output: Path,
    password: str,
    self_destruct_after: int | None = None,
) -> None:
    _write_container(
        real_pdf.read_bytes(),
        decoy_pdf.read_bytes(),
        output,
        password,
        real_pdf.name,
        decoy_pdf.name,
        self_destruct_after,
    )


def _read_container_payload(container_path: Path, require_real: bool = True) -> tuple[dict, bytes, bytes | None]:
    with zipfile.ZipFile(container_path, "r") as container:
        manifest = _read_manifest(container)
        decoy = _read_member(container, DECOY)
        try:
            ciphertext = container.read(REAL)
        except KeyError as exc:
            if require_real:
                raise PdfSafeError("Container no longer contains the real PDF.") from exc
            ciphertext = None
    return manifest, decoy, ciphertext


def _write_container_payload(container_path: Path, manifest: dict, decoy: bytes, ciphertext: bytes | None) -> None:
    temp_path = container_path.with_name(f".{container_path.name}.tmp")
    with zipfile.ZipFile(temp_path, "w", compression=zipfile.ZIP_DEFLATED) as container:
        container.writestr(MANIFEST, json.dumps(manifest, indent=2, sort_keys=True))
        container.writestr(DECOY, decoy)
        if ciphertext is not None:
            container.writestr(REAL, ciphertext)
    os.replace(temp_path, container_path)


def _self_destruct_limit(manifest: dict) -> int | None:
    value = manifest.get("self_destruct_after")
    if value is None:
        return None
    limit = int(value)
    if limit < 1:
        raise PdfSafeError("Container has an invalid self-destruct threshold.")
    return limit


def _remaining_attempts(limit: int | None, failed_attempts: int) -> int | None:
    if limit is None:
        return None
    return max(limit - failed_attempts, 0)


def _record_failed_attempt(container_path: Path, manifest: dict, decoy: bytes, ciphertext: bytes | None) -> OpenResult:
    limit = _self_destruct_limit(manifest)
    if limit is None:
        return OpenResult(real_was_written=False)

    failed_attempts = int(manifest.get("failed_attempts", 0)) + 1
    destroyed = failed_attempts >= limit
    manifest["failed_attempts"] = failed_attempts
    if destroyed:
        manifest["destroyed"] = True
        manifest["destroyed_at"] = datetime.now(timezone.utc).isoformat()
        ciphertext = None

    _write_container_payload(container_path, manifest, decoy, ciphertext)
    return OpenResult(
        real_was_written=False,
        destroyed=destroyed,
        failed_attempts=failed_attempts,
        remaining_attempts=_remaining_attempts(limit, failed_attempts),
    )


def _record_successful_attempt(container_path: Path, manifest: dict, decoy: bytes, ciphertext: bytes) -> None:
    if manifest.get("failed_attempts", 0) == 0:
        return
    manifest["failed_attempts"] = 0
    _write_container_payload(container_path, manifest, decoy, ciphertext)


def decrypt_real_pdf(container_path: Path, password: str) -> tuple[bytes, dict]:
    manifest, _decoy, ciphertext = _read_container_payload(container_path)
    if ciphertext is None:
        raise PdfSafeError("Container no longer contains the real PDF.")
    salt = bytes.fromhex(manifest["salt"])
    nonce = bytes.fromhex(manifest["nonce"])
    expected_tag = bytes.fromhex(manifest["tag"])

    enc_key, mac_key = _derive_keys(password, salt, manifest["kdf"])
    actual_tag = _mac(mac_key, salt, nonce, ciphertext)

    if not hmac.compare_digest(actual_tag, expected_tag):
        raise PdfSafeError("Current password is incorrect.")

    return _chacha20_xor(ciphertext, enc_key, nonce), manifest


def open_container_status(container_path: Path, output: Path, password: str) -> OpenResult:
    manifest, decoy, ciphertext = _read_container_payload(container_path, require_real=False)
    if manifest.get("destroyed") or ciphertext is None:
        _atomic_write(output, decoy)
        return OpenResult(real_was_written=False, destroyed=True)

    salt = bytes.fromhex(manifest["salt"])
    nonce = bytes.fromhex(manifest["nonce"])
    expected_tag = bytes.fromhex(manifest["tag"])
    enc_key, mac_key = _derive_keys(password, salt, manifest["kdf"])
    actual_tag = _mac(mac_key, salt, nonce, ciphertext)

    if not hmac.compare_digest(actual_tag, expected_tag):
        result = _record_failed_attempt(container_path, manifest, decoy, ciphertext)
        _atomic_write(output, decoy)
        return result

    real_pdf = _chacha20_xor(ciphertext, enc_key, nonce)
    _atomic_write(output, real_pdf)
    _record_successful_attempt(container_path, manifest, decoy, ciphertext)
    return OpenResult(real_was_written=True)


def open_container(container_path: Path, output: Path, password: str) -> bool:
    return open_container_status(container_path, output, password).real_was_written


def change_container_password(
    container_path: Path,
    output: Path,
    current_password: str,
    new_password: str,
    decoy_pdf: Path | None = None,
) -> None:
    if not new_password:
        raise PdfSafeError("New password cannot be empty.")

    real_pdf, manifest = decrypt_real_pdf(container_path, current_password)
    if decoy_pdf is None:
        _old_manifest, decoy_pdf_data, _ciphertext = _read_container_payload(container_path)
        decoy_name = manifest.get("decoy_name") or "decoy.pdf"
    else:
        decoy_pdf_data = decoy_pdf.read_bytes()
        decoy_name = decoy_pdf.name

    _write_container(
        real_pdf,
        decoy_pdf_data,
        output,
        new_password,
        manifest.get("real_name") or "real.pdf",
        decoy_name,
        manifest.get("self_destruct_after"),
    )


def inspect_container(container_path: Path, stream: BinaryIO) -> None:
    with zipfile.ZipFile(container_path, "r") as container:
        manifest = _read_manifest(container)
    details = {
        "format": manifest["format"],
        "real_name": manifest.get("real_name"),
        "decoy_name": manifest.get("decoy_name"),
        "cipher": manifest.get("cipher"),
        "kdf": manifest.get("kdf"),
        "mac": manifest.get("mac"),
        "failed_attempts": manifest.get("failed_attempts", 0),
        "self_destruct_after": manifest.get("self_destruct_after"),
        "destroyed": bool(manifest.get("destroyed")),
    }
    stream.write(json.dumps(details, indent=2, sort_keys=True).encode("utf-8"))
    stream.write(b"\n")


def _password_from_args(args: argparse.Namespace, prompt: str, confirm: bool = False) -> str:
    if args.password is not None:
        return args.password
    password = getpass.getpass(prompt)
    if confirm:
        repeated = getpass.getpass("Confirm password: ")
        if password != repeated:
            raise PdfSafeError("Passwords do not match.")
    return password


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Protect a real PDF behind a password and show a decoy PDF on wrong passwords.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    create = subparsers.add_parser("create", help="Create a .safe container.")
    create.add_argument("--real", required=True, type=Path, help="Real PDF shown for the correct password.")
    create.add_argument("--decoy", required=True, type=Path, help="Decoy PDF shown for an incorrect password.")
    create.add_argument("--out", required=True, type=Path, help="Output .safe path.")
    create.add_argument("--password", help="Password. Omit this option for a hidden prompt.")
    create.add_argument(
        "--self-destruct-after",
        type=int,
        metavar="N",
        help="Remove the real encrypted PDF from the container after N wrong passwords.",
    )

    open_cmd = subparsers.add_parser("open", help="Open a .safe container into a PDF.")
    open_cmd.add_argument("--in", dest="container", required=True, type=Path, help="Input .safe path.")
    open_cmd.add_argument("--out", required=True, type=Path, help="Output PDF path.")
    open_cmd.add_argument("--password", help="Password. Omit this option for a hidden prompt.")
    open_cmd.add_argument(
        "--quiet",
        action="store_true",
        help="Do not print whether the real or decoy PDF was written.",
    )

    change = subparsers.add_parser("change-password", help="Change a container password.")
    change.add_argument("--in", dest="container", required=True, type=Path, help="Input .safe path.")
    change.add_argument("--out", required=True, type=Path, help="Output .safe path.")
    change.add_argument("--current-password", help="Current password. Omit this option for a hidden prompt.")
    change.add_argument("--new-password", help="New password. Omit this option for a hidden prompt.")
    change.add_argument("--decoy", type=Path, help="Optional replacement decoy PDF.")

    inspect = subparsers.add_parser("inspect", help="Show non-secret container metadata.")
    inspect.add_argument("--in", dest="container", required=True, type=Path, help="Input .safe path.")

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        if args.command == "create":
            password = _password_from_args(args, "Password: ", confirm=args.password is None)
            create_container(args.real, args.decoy, args.out, password, args.self_destruct_after)
            print(f"Created {args.out}")
            return 0

        if args.command == "open":
            password = _password_from_args(args, "Password: ")
            result = open_container_status(args.container, args.out, password)
            if not args.quiet:
                written = "real PDF" if result.real_was_written else "decoy PDF"
                print(f"Wrote {written} to {args.out}")
                if result.destroyed:
                    print("The real PDF payload has been destroyed.")
                elif result.remaining_attempts is not None:
                    print(f"Wrong password attempts remaining: {result.remaining_attempts}")
            return 0

        if args.command == "change-password":
            if args.current_password is None:
                args.current_password = getpass.getpass("Current password: ")
            if args.new_password is None:
                args.new_password = getpass.getpass("New password: ")
                repeated = getpass.getpass("Confirm new password: ")
                if args.new_password != repeated:
                    raise PdfSafeError("Passwords do not match.")
            change_container_password(
                args.container,
                args.out,
                args.current_password,
                args.new_password,
                args.decoy,
            )
            print(f"Updated {args.out}")
            return 0

        if args.command == "inspect":
            inspect_container(args.container, sys.stdout.buffer)
            return 0

    except (PdfSafeError, OSError, zipfile.BadZipFile, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    parser.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

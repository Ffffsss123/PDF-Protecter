# PDF-Protecter

A local PDF safety container tool. It packages a real PDF and a decoy PDF into
one `.safe` file. When the correct password is provided, it exports the real
PDF. When an incorrect password is provided, it exports the decoy PDF.

> Note: Standard PDF readers cannot automatically show a different PDF after an
> incorrect password. This project uses a custom `.safe` container and a
> companion opener tool to provide that behavior.

## Features

- Protects the real PDF with a password.
- Exports a configured decoy PDF instead of failing on incorrect passwords.
- Can optionally remove the real encrypted payload after a configured number of
  wrong password attempts.
- Uses only the Python standard library.
- Uses `scrypt` for key derivation when available. If the current Python build
  does not provide `scrypt`, it automatically uses `PBKDF2-HMAC-SHA256`.
  PDF content is encrypted with ChaCha20 and verified with HMAC-SHA256.

## Usage

Launch the desktop GUI from source:

```bash
python3 pdf_protecter_gui.py
```

The GUI provides three workflows:

- `Protect PDF`: choose the real PDF, choose the decoy PDF, set a password, and
  create a `.safe` file. You can optionally enable real-payload destruction
  after repeated wrong passwords.
- `Open PDF`: choose a `.safe` file, enter a password, and export a PDF.
  Correct passwords export the real PDF; incorrect passwords export the decoy.
- `Change Password`: choose an existing `.safe` file, enter the current
  password, set a new password, and optionally replace the decoy PDF.

Create a secure container:

```bash
python3 pdf_protecter.py create \
  --real secret.pdf \
  --decoy fake.pdf \
  --out protected.safe \
  --self-destruct-after 3
```

Open a secure container:

```bash
python3 pdf_protecter.py open \
  --in protected.safe \
  --out readable.pdf
```

You can also pass the password as a command-line argument, which is useful for
tests and scripts:

```bash
python3 pdf_protecter.py create \
  --real secret.pdf \
  --decoy fake.pdf \
  --out protected.safe \
  --password "your-password"

python3 pdf_protecter.py open \
  --in protected.safe \
  --out readable.pdf \
  --password "your-password"
```

Inspect container metadata:

```bash
python3 pdf_protecter.py inspect --in protected.safe
```

Change the password for an existing container:

```bash
python3 pdf_protecter.py change-password \
  --in protected.safe \
  --out protected-updated.safe
```

After installing the macOS package, the same tool is available as
`pdf-protecter`, and the GUI is available as `PDF-Protecter.app`:

```bash
pdf-protecter --help
pdf-protecter-gui
open -a PDF-Protecter
```

## Build a macOS Installer

Build a directly runnable `.app` bundle and zip for quick testing:

```bash
scripts/build_macos_app.sh
```

The output is written to `dist/PDF-Protecter.app` and
`dist/PDF-Protecter-1.0.0-macOS.zip`.

Build a `.pkg` installer on macOS:

```bash
scripts/build_macos_pkg.sh
```

The output is written to `dist/PDF-Protecter-1.0.0.pkg`.

To set a custom version:

```bash
VERSION=1.2.3 scripts/build_macos_pkg.sh
```

Install the package:

```bash
sudo installer -pkg dist/PDF-Protecter-1.0.0.pkg -target /
```

After installation, open the app from `/Applications/PDF-Protecter.app` or run:

```bash
open -a PDF-Protecter
```

## Security Notes

`.safe` files must be opened with this tool. They are not standard PDF files
and cannot be opened directly with a system PDF reader. The exported
`readable.pdf` is a normal PDF file. If the real PDF needs long-term protection,
do not leave exported copies in unsafe locations.

The decoy PDF is packaged as-is inside the container. The real PDF is stored
encrypted, and HMAC is used to determine whether the password is correct. The
container records the actual KDF parameters so it can be opened later.

The self-destruct option removes the encrypted real PDF payload from the
`.safe` container after the configured number of wrong passwords. It does not
silently delete the original source PDF from elsewhere on disk. For strong
protection, store only the `.safe` container and keep backups according to
your own recovery policy.

Wrong-password counters are stored in the local container file. A user who makes
copies of the container before opening it may be able to retry against a copy, so
this feature is a deterrent and local safety control, not an online account-style
rate limit.

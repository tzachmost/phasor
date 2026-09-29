# Phasor Preview

Preview is Phasor's standalone document and image app. It follows the shell's visual tokens and runs as a regular Wayland window, separate from the always-on Phasor surfaces.

## First milestone

- Open a PDF or image from the file picker, by drag and drop, or from the command line with `phasor-preview path/to/file`.
- Browse PDF pages with thumbnails and page controls. Search PDF text, select and copy it, zoom, fit, and rotate the current view.
- Browse embedded PDF bookmarks in the **Contents** sidebar and jump to their destinations.
- Switch between **Single Page**, **Continuous Scroll**, and **Two Pages** from the **Layout** menu. Two-page mode keeps each page's markup visible; continuous scroll is a reading layout and markup appears again when you switch to Single Page or choose a markup tool. Continuous and two-page modes require the original page order and rotation; reset page operations before using them after moving, excluding, or rotating pages.
- Choose **Text** from the PDF toolbar to highlight, underline, strike through, or add a note to selected text. Drag across selectable PDF text; Preview saves the selected quote and its page geometry in the editable sidecar, so the mark stays attached to that passage. Hover a note marker to read it. PDF export draws text marks into the page and keeps notes as standard PDF note annotations.
- Open **More → Document info** to inspect file size and dates, PDF page count and document metadata, or image dimensions, color mode, animation frames, resolution, and available camera metadata.
- Open password-protected PDFs by entering their password. Preview keeps it in memory for the open document and sends it to local PDF helpers over standard input; it is not saved in a sidecar or command argument.
- View Qt-supported image formats with zoom, pan, fit, rotation, and horizontal or vertical flips from **More**. Animated images play in the viewer; pause playback, step through frames, and export or print the selected frame.
- Choose **More → Recognize text** on an image to run local OCR and open selectable results that can be copied. Preview uses the selected animation frame, crop, rotation, and flips.
- Choose **More → Make searchable PDF copy** to embed or refresh an OCR text layer on scanned pages. Preview applies pending page order, rotations, markup, and form values to a new copy; existing visible PDF text stays in place. The operation uses local OCR, leaves the source untouched, and refuses digitally signed PDFs. A PDF password is sent to the helper over standard input, never in a command argument.
- Remove a bitmap image's background from **More → Remove background…** and save a transparent PNG copy. The selected animation frame, crop, rotation, flips, and image markup are applied to the copy; the source remains intact. Preview uses the local CPU model and downloads its U2-Net weights on first use.
- Choose **More → Lasso selection**, trace an area on a bitmap image, then use **More → Extract selected area…** to save that freeform selection as a transparent PNG. The selected animation frame, crop, rotation, and flips are applied; the original image and editable markup stay unchanged. Clear the temporary outline from **More → Clear lasso selection**.
- Choose **More → Redact area**, then drag over any PDF page content to cover it. Redaction boxes store only page geometry in the sidecar, never the selected text. Exporting, printing, or merging creates a new copy and permanently removes the original objects on affected pages by rasterizing those pages at 300 DPI; unaffected pages stay searchable. The source stays unchanged, active digitally signed PDFs are refused, and redacted pages become image-only. Poppler's `pdftoppm` command is installed with Phasor on supported packages.
- Mark up images and PDF pages with pen strokes, highlights, rectangles, and text. Markup is saved automatically in an editable `*.phasor-markup.json` sidecar beside the source document; the original file is left intact.
- Fill single-line and multi-line text fields, fixed or editable choices, checkboxes, radio buttons, and multi-select lists from the **More → Fill PDF forms** panel. Values are saved in the sidecar and applied to the exported PDF, which keeps its form fields editable. Password-marked fields are masked and their new values are kept out of the autosaved sidecar; they are included when you explicitly export, merge, print, or sign a copy.
- Draw a visual signature on an image or PDF with a mouse, touchscreen, or stylus using **More → Draw signature**. Signature strokes remain editable in the sidecar and are included in exports and print copies.
- Digitally sign a PDF with a PKCS#12 (`.p12` or `.pfx`) certificate using **More → Sign with certificate**. Drag to place the visible signature, enter the certificate password, and save a signed copy. The password is passed to the local signing helper over standard input and is not written to a file or command argument.
- Merge the current PDF with other PDFs using **More → Merge PDFs**. Preview applies the current document's page order, form values, and markup, then appends the selected PDFs into a new file. Imported form fields are grouped under their source filename and import order to avoid collisions. Signed PDFs are refused because merging would invalidate their signatures.
- Crop images by dragging a selection. Export flattened PNG, JPEG, WebP, TIFF, or BMP copies; choose a maximum output size and image quality.
- Export PDFs with markup drawn into the page content while the original text stays searchable. Move pages, exclude pages, and rotate individual pages for the exported copy. These PDF page operations are saved in the markup sidecar. From **Page**, insert a blank page or selected pages from another PDF after the current page; Preview prepares and opens a new copy, leaving both input documents untouched. The copy retains editable PDF form fields and namespaces imported fields to avoid collisions. Current markup becomes page content in the new copy. If either input is password protected, set a password for the new copy. The export options can apply lossless stream/object compression and AES-256 password protection to a new copy.
- Print images and PDFs with a selected printer, copy count, and page range. Preview sends a temporary prepared copy with markup and filled form values applied, leaving the source untouched.
- Use `Ctrl+O` to open, `Ctrl+S` to save markup, `Ctrl++`/`Ctrl+-` to zoom, and `Escape` to return to selection mode.

The PDF viewer uses Qt Quick PDF. It is an optional runtime module so the core shell does not pull in the larger Qt WebEngine package. On Arch install `qt6-webengine`; on Fedora install `qt6-qtpdf`. NixOS users can add `pkgs.qt6.qtwebengine` to the system packages. Without the module, image viewing and image export still work and Preview reports that PDF support is unavailable. The Preview package provides Pillow, pypdf 5.7 or newer, ReportLab, cryptography, and DejaVu Sans. Cryptography enables modern AES PDF decryption and AES-256 output protection. Lossless size reduction compresses PDF page streams and duplicate objects; PDFs dominated by already-compressed scans or images may stay the same size or grow slightly. The tested certificate-signing range is pyHanko 0.36.2 through 0.37.x. Nix includes it; Arch users can install the optional AUR package `python-pyhanko`. On Fedora, install pyHanko in Preview's private user environment:

```bash
python3 -m venv "${XDG_DATA_HOME:-$HOME/.local/share}/phasor-preview/signing"
"${XDG_DATA_HOME:-$HOME/.local/share}/phasor-preview/signing/bin/pip" install 'pyHanko>=0.36.2,<0.38'
```

Preview checks that environment automatically. You can set `PHASOR_PREVIEW_SIGNING_VENV` to use a different virtual environment. Permanent PDF redaction uses Poppler's `pdftoppm` renderer and is included in Phasor packages (`poppler` on Arch, `poppler-utils` on Fedora and NixOS). CUPS printing is optional: install and configure `cups` on Arch or `cups-client` on Fedora; NixOS users can add `pkgs.cups` to the host packages. SVG images can be viewed but cannot be exported or printed yet.

Background removal is an optional CPU feature. The standard Preview package does not include its larger inference runtime. On Arch or Fedora, create a private environment with Python 3.13 and install the CPU backend:

```bash
python3.13 -m venv "${XDG_DATA_HOME:-$HOME/.local/share}/phasor-preview/background-removal"
"${XDG_DATA_HOME:-$HOME/.local/share}/phasor-preview/background-removal/bin/python" -m pip install 'Pillow>=10' 'rembg[cpu]>=2.0.85,<3'
```

Preview detects this environment when launched normally. Set `PHASOR_PREVIEW_BG_VENV` to use another virtual environment, or `PHASOR_PREVIEW_BG_PYTHON` to select its Python interpreter directly. The Nix flake provides an optional `preview-background-removal` package output that adds `phasor-preview-bg-python`; add it to `environment.systemPackages` to enable the menu action. The first removal downloads the selected U2-Net weights; subsequent inference runs locally. The selected model avoids rembg's default model. See the [rembg installation and model notes](https://github.com/danielgatis/rembg/blob/main/README.md).

## Local OCR

OCR is optional and runs entirely on the device. Install Tesseract and the language data you need to recognize text in images. Searchable PDF copies also need OCRmyPDF, which uses Tesseract and local PDF processing tools. Preview lists the language packs Tesseract can currently load. On Arch, install `tesseract` and the matching `tesseract-data-*` packages; OCRmyPDF is available from the AUR. On Fedora, install `ocrmypdf` and the desired `tesseract-langpack-*` package. See the [OCRmyPDF installation guide](https://ocrmypdf.readthedocs.io/en/stable/installation.html) for its system-tool requirements.

NixOS users can add the optional OCR bundle to `environment.systemPackages`:

```nix
inputs.phasor.packages.${pkgs.system}.preview-ocr
```

The OCR text layer is added to a new PDF copy. OCR quality depends on scan clarity and installed language data. Password-protected source PDFs are unlocked only in a temporary working copy inside the selected output directory; that private temporary directory is removed after the operation.

## Export behavior

Export always writes a new file. Image markup is painted into the copy, and animated images export the selected frame with crop, rotation, and flip operations applied. PDF form values are applied while fields remain fillable. Password-marked values are excluded from sidecar saves and sent to the document helper over standard input only for explicit output operations. An unlocked source PDF can be compressed losslessly and protected with a new password using AES-256. Preview reports the before and after file sizes because compression gains depend on document contents. PDF markup and visual signatures are added as vector page content; the sidecar retains the editable strokes and text. PDF page order, excluded pages, and rotations are applied only to the exported copy, so the original PDF pages remain recoverable.

Certificate signatures are incremental updates, and Preview refuses to apply unsaved sidecar edits to a PDF that already contains a digital signature. The signing operation creates a visible approval signature; it does not add a trusted timestamp or establish whether a certificate is trusted. PDF readers use their own trust stores and validation policies to assess the certificate.

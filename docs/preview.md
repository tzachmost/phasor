# Phasor Preview

Preview is Phasor's standalone document and image app. It follows the shell's visual tokens and runs as a regular Wayland window, separate from the always-on Phasor surfaces.

## First milestone

- Open a PDF or image from the file picker, by drag and drop, or from the command line with `phasor-preview path/to/file`.
- Browse PDF pages with thumbnails and page controls. Search PDF text, select and copy it, zoom, fit, and rotate the current view.
- Browse embedded PDF bookmarks in the **Contents** sidebar and jump to their destinations.
- Open **More → Document info** to inspect file size and dates, PDF page count and document metadata, or image dimensions, color mode, animation frames, resolution, and available camera metadata.
- View Qt-supported image formats with zoom, pan, fit, rotation, and horizontal or vertical flips from **More**. Animated images play in the viewer; pause playback, step through frames, and export or print the selected frame.
- Mark up images and PDF pages with pen strokes, highlights, rectangles, and text. Markup is saved automatically in an editable `*.phasor-markup.json` sidecar beside the source document; the original file is left intact.
- Fill single-line and multi-line text fields, fixed or editable choices, checkboxes, radio buttons, and multi-select lists from the **More → Fill PDF forms** panel. Values are saved in the sidecar and applied to the exported PDF, which keeps its form fields editable. Password-marked fields are masked and their new values are kept out of the autosaved sidecar; they are included when you explicitly export, merge, print, or sign a copy.
- Draw a visual signature on an image or PDF with a mouse, touchscreen, or stylus using **More → Draw signature**. Signature strokes remain editable in the sidecar and are included in exports and print copies.
- Digitally sign a PDF with a PKCS#12 (`.p12` or `.pfx`) certificate using **More → Sign with certificate**. Drag to place the visible signature, enter the certificate password, and save a signed copy. The password is passed to the local signing helper over standard input and is not written to a file or command argument.
- Merge the current PDF with other PDFs using **More → Merge PDFs**. Preview applies the current document's page order, form values, and markup, then appends the selected PDFs into a new file. Imported form fields are grouped under their source filename and import order to avoid collisions. Signed PDFs are refused because merging would invalidate their signatures.
- Crop images by dragging a selection. Export flattened PNG, JPEG, WebP, TIFF, or BMP copies; choose a maximum output size and image quality.
- Export PDFs with markup drawn into the page content while the original text stays searchable. Move pages, exclude pages, and rotate individual pages for the exported copy. These PDF page operations are saved in the markup sidecar.
- Print images and PDFs with a selected printer, copy count, and page range. Preview sends a temporary prepared copy with markup and filled form values applied, leaving the source untouched.
- Use `Ctrl+O` to open, `Ctrl+S` to save markup, `Ctrl++`/`Ctrl+-` to zoom, and `Escape` to return to selection mode.

The PDF viewer uses Qt Quick PDF. It is an optional runtime module so the core shell does not pull in the larger Qt WebEngine package. On Arch install `qt6-webengine`; on Fedora install `qt6-qtpdf`. NixOS users can add `pkgs.qt6.qtwebengine` to the system packages. Without the module, image viewing and image export still work and Preview reports that PDF support is unavailable. The Preview package provides Pillow, pypdf, ReportLab, and DejaVu Sans for export. The tested certificate-signing range is pyHanko 0.36.2 through 0.37.x. Nix includes it; Arch users can install the optional AUR package `python-pyhanko`. On Fedora, install pyHanko in Preview's private user environment:

```bash
python3 -m venv "${XDG_DATA_HOME:-$HOME/.local/share}/phasor-preview/signing"
"${XDG_DATA_HOME:-$HOME/.local/share}/phasor-preview/signing/bin/pip" install 'pyHanko>=0.36.2,<0.38'
```

Preview checks that environment automatically. You can set `PHASOR_PREVIEW_SIGNING_VENV` to use a different virtual environment. CUPS printing is optional: install and configure `cups` on Arch or `cups-client` on Fedora; NixOS users can add `pkgs.cups` to the host packages. SVG images can be viewed but cannot be exported or printed yet.

## Export behavior

Export always writes a new file. Image markup is painted into the copy, and animated images export the selected frame with crop, rotation, and flip operations applied. PDF form values are applied while fields remain fillable. Password-marked values are excluded from sidecar saves and sent to the document helper over standard input only for explicit output operations. PDF markup and visual signatures are added as vector page content; the sidecar retains the editable strokes and text. PDF page order, excluded pages, and rotations are applied only to the exported copy, so the original PDF pages remain recoverable.

Certificate signatures are incremental updates, and Preview refuses to apply unsaved sidecar edits to a PDF that already contains a digital signature. The signing operation creates a visible approval signature; it does not add a trusted timestamp or establish whether a certificate is trusted. PDF readers use their own trust stores and validation policies to assess the certificate.

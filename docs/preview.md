# Phasor Preview

Preview is Phasor's standalone document and image app. It follows the shell's visual tokens and runs as a regular Wayland window, separate from the always-on Phasor surfaces.

## First milestone

- Open a PDF or image from the file picker, by drag and drop, or from the command line with `phasor-preview path/to/file`.
- Browse PDF pages with thumbnails and page controls. Search PDF text, select and copy it, zoom, fit, and rotate the current view.
- View Qt-supported image formats with zoom, pan, fit, and rotation.
- Mark up images and PDF pages with pen strokes, highlights, rectangles, and text. Markup is saved automatically in an editable `*.phasor-markup.json` sidecar beside the source document; the original file is left intact.
- Crop images by dragging a selection. Export flattened PNG, JPEG, WebP, TIFF, or BMP copies; choose a maximum output size and image quality.
- Export PDFs with markup drawn into the page content while the original text stays searchable. Move pages, exclude pages, and rotate individual pages for the exported copy. These PDF page operations are saved in the markup sidecar.
- Use `Ctrl+O` to open, `Ctrl+S` to save markup, `Ctrl++`/`Ctrl+-` to zoom, and `Escape` to return to selection mode.

The PDF viewer uses Qt Quick PDF. It is an optional runtime module so the core shell does not pull in the larger Qt WebEngine package. On Arch install `qt6-webengine`; on Fedora install `qt6-qtpdf`. NixOS users can add `pkgs.qt6.qtwebengine` to the system packages. Without the module, image viewing and image export still work and Preview reports that PDF support is unavailable. The Preview package provides Pillow, pypdf, ReportLab, and DejaVu Sans for export. SVG images can be viewed but cannot be exported yet.

## Export behavior

Export always writes a new file. Image markup is painted into the copy. PDF markup is added as vector page content, which keeps the existing document text searchable but makes the exported marks non-editable; the sidecar retains the editable version. PDF page order, excluded pages, and rotations are applied only to the exported copy, so the original PDF pages remain recoverable.

Forms, signatures, printing, and PDF merge remain future work.

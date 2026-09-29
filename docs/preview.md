# Phasor Preview

Preview is Phasor's standalone document and image app. It follows the shell's visual tokens and runs as a regular Wayland window, separate from the always-on Phasor surfaces.

## First milestone

- Open a PDF or image from the file picker, by drag and drop, or from the command line with `phasor-preview path/to/file`.
- Browse PDF pages with thumbnails and page controls. Search PDF text, select and copy it, zoom, fit, and rotate the current view.
- View Qt-supported image formats with zoom, pan, fit, and rotation.
- Mark up images and PDF pages with pen strokes, highlights, rectangles, and text. Markup is saved automatically in an editable `*.phasor-markup.json` sidecar beside the source document; the original file is left intact.
- Use `Ctrl+O` to open, `Ctrl+S` to save markup, `Ctrl++`/`Ctrl+-` to zoom, and `Escape` to return to selection mode.

The PDF viewer uses Qt Quick PDF. It is an optional runtime module so the core shell does not pull in the larger Qt WebEngine package. On Arch install `qt6-webengine`; on Fedora install `qt6-qtpdf`. NixOS users can add `pkgs.qt6.qtwebengine` to the system packages. Without the module, image viewing still works and Preview reports that PDF support is unavailable.

## Next editing tools

The first milestone keeps markup editable in the sidecar. Follow-up work can add image crop/resize and export, flattening annotations into exported PDFs and images, PDF page reorder/merge, form fill, signatures, and printing. These operations should write a new output file or use an explicit save action so source documents stay recoverable.

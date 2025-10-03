GraphDigitizer
==============

GraphDigitizer is a small interactive GUI tool (Julia + Gtk) for extracting numeric data points from raster images of graphs (PNG/JPEG). It supports non-blocking calibration, manual point picking and editing, a color-based auto-trace routine, a precision circular zoom for pixel-level placement, and export to JSON and CSV. The application is defensive about platform differences in Gtk.jl and provides fallbacks when native dialogs are unavailable.

Version
-------
See `Project.toml` for the packaged version (1.0.0). The runtime binary identifies itself via constants in `src/graph_digitizer.jl`.

Quick links
-----------
- Source: src/graph_digitizer.jl
- Docs: docs/*.md

Table of contents
-----------------
- Features
- Requirements
- Installation
- Running
- Quickstart (how to use)
- File formats (JSON / CSV)
- Default filename & fallback behavior
- Keyboard shortcuts & UI notes
- Troubleshooting
- Contributing
- License

Features
--------
- Load PNG/JPEG images and display in a scalable canvas.
- Non-blocking calibration: record four clicks (X-left, X-right, Y-bottom, Y-top) then apply numeric axis ranges (linear or log10).
- Manual point picking: left-click to add, drag to move, right-click or Delete to remove.
- Precision placement overlay (Alt+Z): circular magnifier (~1 cm radius) with configurable magnification for pixel-accurate placement.
- Rectangular magnifier preview near the mouse (optional in UI).
- Auto-trace: column-by-column color matching using a dataset's hex color to extract curve points.
- Multiple datasets (color-coded), per-dataset editing and name/color controls.
- Export to JSON (metadata + datasets) and CSV (rows: dataset, x, y).
- Robust file chooser fallbacks: when a native save dialog cannot be created, a sensible fallback filename is written to your Downloads folder (or system temp) and the path is shown in the status label.
- Defensive Gtk usage: helpers attempt multiple Gtk.jl APIs so the app works across Gtk.jl and GTK versions.

Requirements
------------
- Julia 1.6 or newer is recommended.
- Gtk runtime (GTK 3/4) present on the system (Gtk.jl may require a system-provided GTK on some platforms).
- Project dependencies are pinned in `Project.toml` / `Manifest.toml` and installed with the Julia package system.

Installation
------------
1. Clone the repository and change into it:

```Graph_Digitizer/README.md#L1-4
git clone <repo-url>
cd Graph_Digitizer
```

2. Use Julia to instantiate the pinned environment (this will install packages listed in `Project.toml` / `Manifest.toml`):

```Graph_Digitizer/README.md#L6-8
julia --project=@. -e 'using Pkg; Pkg.instantiate()'
```

Note: If Gtk.jl prints warnings about native dependencies while installing, follow the Gtk.jl instructions for your OS (Linux distributions typically need system GTK packages; Windows typically uses prebuilt binaries).

Running
-------
Start the GUI from the project root:

```Graph_Digitizer/README.md#L10-12
julia --project=@. src/graph_digitizer.jl
```

Keep the launching terminal open to view diagnostic messages, warnings, or crash traces — the app prints helpful startup and error information to stdout/stderr.

Quickstart / How to use
-----------------------
A minimal workflow to digitize a plot:

1. Load an image
   - Click the `Load Image` toolbar button and select a PNG or JPEG file.
   - After loading, the image displays in the central canvas.

2. Calibrate (non-blocking)
   - Click `Calibrate Clicks`. The app enters calibration mode and waits for four clicks (do not close the dialog).
   - Click in this order on the image:
     1. X-left pixel — canvas pixel corresponding to the known left-hand x value.
     2. X-right pixel — pixel for the known right-hand x value.
     3. Y-bottom pixel — pixel for the known bottom y value.
     4. Y-top pixel — pixel for the known top y value.
   - The status label updates as clicks are recorded.

3. Enter numeric axis ranges and apply
   - Fill the `X min`, `X max`, `Y min`, `Y max` boxes.
   - Toggle `X log` / `Y log` if the axis is logarithmic (base 10).
   - Click `Apply Calibration`. After applying, data↔canvas transforms become active.

4. Add / move / delete points
   - Add: left-click on the curve to add a point (coordinates mapped from canvas → data using the calibration).
   - Move: left-click near an existing point to select then drag to reposition.
   - Delete: right-click a point, use the `Delete Selected Point` button, or press Delete/Backspace when a point is selected.

5. Precision placement (Alt+Z)
   - With the canvas focused, press Alt+Z to toggle the circular precision overlay centered on the last mouse position.
   - Move the mouse to refine the center; left-click to add a point at the center of the overlay.
   - Press Alt+Z again to exit precision mode.

6. Auto-trace
   - Select the dataset you want to populate via the dataset combo box.
   - Ensure calibration is applied and an image is loaded.
   - Click `Auto Trace Active Dataset`. The algorithm scans columns between the calibrated X pixel bounds and chooses, per column, the pixel row closest in RGB Euclidean distance to the dataset color. Results replace the active dataset's points.

7. Save / Export
   - Use toolbar buttons, `File` menu, or keyboard accelerators:
     - Primary+S (Ctrl+S on Windows and Linux) — Save JSON (metadata + datasets).
     - Primary+Shift+S — Save CSV (rows: dataset, x, y).
   - A Save dialog will be used when available. If a dialog cannot be constructed (some Gtk.jl or environment combinations), the app falls back to writing into your Downloads folder (or system temp) using a generated filename and updates the status label with the full path used.

File formats
------------
JSON export
- Contains metadata and datasets. Example structure:

```Graph_Digitizer/README.md#L30-46
{
  "title": "...",
  "xlabel": "...",
  "ylabel": "...",
  "x_min": 0.0,
  "x_max": 10.0,
  "y_min": 0.0,
  "y_max": 100.0,
  "x_log": false,
  "y_log": false,
  "datasets": [
    {
      "name": "Dataset 1",
      "color": "#0072B2",
      "points": [[x1, y1], [x2, y2], ...]
    }
  ]
}
```

CSV export
- Simple tabular export with columns: `dataset`, `x`, `y`. Each row represents one point.

Default filename and fallback behavior
--------------------------------------
- Default filename base: the `Title` field is used (sanitized — non-alphanumeric characters replaced with underscores and repeated underscores collapsed). If empty, a timestamped name is used.
- Fallback save path: when a native save dialog is unavailable, the app chooses your `Downloads` folder (if present) or the system temporary directory and writes the file there. The status label shows the chosen path so you can retrieve the file.

Keyboard shortcuts and UI notes
-------------------------------
- Save JSON: Primary+S (Ctrl+S on Windows and Linux)
- Save CSV: Primary+Shift+S
- Exit: Primary+Q (Ctrl+Q on Windows and Linux)
- Precision Zoom toggle: Alt+Z (requires canvas focus)
- Delete selected point: Delete / Backspace or the `Delete Selected Point` button
- The app registers accelerators defensively; behavior may vary slightly on some window managers or Gtk.jl builds.

Troubleshooting
---------------
- App window does not appear / Save dialogs do not open:
  - Inspect the terminal where you launched the app for error messages. Gtk.jl prints helpful diagnostic information.
  - If the Save dialog is unavailable the app will still try to save into `~/Downloads` (or temp) and will show the path used in the status label.
- Gtk.jl errors about native GTK on Linux:
  - Install your distribution's GTK development/runtime packages (for example `libgtk-3-dev`, `gtk3` or similar).
- Keyboard accelerators not working:
  - Some window managers intercept key combinations (e.g., global shortcuts). Use toolbar/menu actions as fallback.
- App crashes or shows UndefVarError:
  - Ensure you used `julia --project=@.` and `Pkg.instantiate()` to create the same package environment as the repository's `Project.toml`/`Manifest.toml`. If the problem persists, capture the terminal output and open an issue with steps to reproduce and the stack trace.

Development notes
-----------------
- Main source: `src/graph_digitizer.jl`. Core utilities and helpers are documented in `docs/*.md`.
- Coordinate transforms:
  - `data_to_canvas(state, x, y)` maps data coordinates to canvas pixels (respects log flags).
  - `canvas_to_data(state, cx, cy)` maps canvas pixels back to data coordinates.
  - Calibration anchors are recorded as four canvas pixel positions: `px_xmin`, `px_xmax`, `px_ymin`, `px_ymax`.
- Auto-trace:
  - Uses a per-column nearest-RGB Euclidean match to the dataset color. It samples columns between the calibrated X pixel anchors and converts found pixel rows to data coordinates.
- Safe dialogs:
  - The code has `safe_open_dialog` / `safe_save_dialog` helpers that attempt multiple Gtk APIs and provide fallbacks to ensure the app is usable in constrained environments.

Contributing
------------
Helpful contributions:
- Bug reports with a minimal reproduction, OS, Julia version, and Gtk.jl version.
- Patches for compatibility across Gtk.jl/Gtk versions.
- Unit tests for coordinate transforms (`data_to_canvas` / `canvas_to_data`) and `_sanitize_filename`.
- Documentation improvements and example images for manual testing.

To develop:
1. Open the repository and start a Julia REPL using the project environment:
```Graph_Digitizer/README.md#L48-50
julia --project=@.
```
2. Run scripts or directly evaluate portions of `src/graph_digitizer.jl` from the REPL, or run the app to interactively test.

License
-------
This project is licensed under the Apache License, Version 2.0. See the `LICENSE` file for details.

Contact / Issues
----------------
If you encounter problems or have enhancement ideas, please open an issue on the repository with:
- Repro steps
- Platform (OS), Julia version, Gtk.jl version
- Terminal output (errors/tracebacks)

Thank you for using GraphDigitizer — if you find it useful, contributions and feedback are welcome.
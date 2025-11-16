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
    - Primary+Shift+S — Save CSV (wide format: `x` column followed by one column per dataset containing Y values).
   - A Save dialog will be used when available. If a dialog cannot be constructed (some Gtk.jl or environment combinations), the app falls back to writing into your Downloads folder (or system temp) using a generated filename and updates the status label with the full path used.

File formats
------------
JSON export
- The JSON export is the canonical, full-fidelity project save format. It contains application metadata (title, axis labels), numeric axis ranges, log-axis flags, and the full list of datasets. Each dataset includes its user-visible name, hex color, and the array of points stored in data coordinates.

- Example structure (fields produced by the app's `export_json` routine):

```json
{
  "title": "My Plot Title",
  "xlabel": "Time (s)",
  "ylabel": "Amplitude",
  "x_min": 0.0,
  "x_max": 100.0,
  "y_min": -1.0,
  "y_max": 1.0,
  "x_log": false,
  "y_log": false,
  "datasets": [
    {
      "name": "Dataset 1",
      "color": "#0072B2",
      "points": [[x1, y1], [x2, y2], ...]
    },
    {
      "name": "Dataset 2",
      "color": "#E69F00",
      "points": [[x1, y1], [x2, y2], ...]
    }
  ]
}
```

- Notes about JSON:
  - `x_log` / `y_log` are boolean flags indicating whether the corresponding axis is logarithmic (base 10). The stored `points` are always in data-space values (not pixel coordinates).
  - `color` is a hex string (e.g. `#RRGGBB`) and `name` is the dataset label shown in the UI.
  - The JSON writer uses `JSON.print` to write the file; IO errors will propagate if the file cannot be written.

CSV export
- The CSV export now produces a wide-format table to make re-plotting across datasets straightforward. The first column is `x` (the union of all X values present in any dataset, sorted). Each subsequent column is a dataset named by its user-visible name (sanitized to a filesystem/CSV-friendly header and made unique if necessary). Each row represents a single X value; the cell under a dataset column contains the Y value for that dataset at that X or is empty (`missing`) if the dataset has no point at that X.

- Example structure (columns):

```
x,Dataset_1,Dataset_2
0.0,0.1,-0.05
1.0,0.15,
```

- Matching behavior and tolerance:
  - The exporter builds the X axis as the sorted union of all X values across datasets.
  - For each dataset and X, the exporter finds the nearest dataset X value and, if it is within a small relative tolerance (approximately 1e-8 * max(1, |x|)), treats it as the same X and writes the corresponding Y. This helps avoid missing values caused by tiny floating-point differences introduced by snapping or processing.
  - If no matching X is found within the tolerance, the exporter writes an empty cell (`missing`) for that dataset/X pair.

- Notes about CSV:
  - The CSV writer uses `CSV.write` with a `DataFrame` assembled from the `x` column plus one column per dataset. IO errors will propagate on write failure.
  - CSV does not include axis metadata or log flags; use JSON for full project metadata.

Save / Export options and behavior
---------------------------------
- Export triggers: use toolbar/menu actions or keyboard accelerators:
  - Primary+S — Save JSON (full project metadata + datasets)
  - Primary+Shift+S — Save CSV (tabular: `dataset`, `x`, `y`)

- Save dialog fallbacks:
  - The app uses `safe_save_dialog` which attempts multiple Gtk file chooser APIs. If a native Save dialog cannot be created in the running environment, the app falls back to a sensible path (your `Downloads` folder when available, otherwise the system temporary directory) and writes the selected export there.
  - When the fallback path is used the full destination filename is displayed in the app status label so you can retrieve the file.

- Default filenames and sanitization:
  - When the Save dialog falls back, a default filename is generated using the `Title` field (if provided) sanitized into a filesystem-safe base filename. The sanitizer replaces non-alphanumeric characters with underscores, collapses repeated underscores, and trims leading/trailing underscores/dots.
  - If `Title` is empty, the app uses a timestamped name like `graphdigitizer_export_YYYY-MM-DD_HHMMSS`.
  - The app ensures the chosen filename has the correct extension (appends `.json` or `.csv` if necessary).

Advanced export-related features
--------------------------------
- Auto-trace & dataset replacement:
  - The `Auto Trace Active Dataset` action scans pixel columns between the calibrated X anchors and selects the pixel row with minimal RGB distance to the active dataset's color. The resulting sampled data points replace the active dataset's point list and can then be exported.

- Snap X values (batch modification):
  - The app supports snapping all datasets' X coordinates to a user-provided list of X values (entered as comma/semicolon-separated numbers). Use the `Place Snap Lines` option to visualize vertical guide lines, then run the `Snap Points to Xs` action to modify stored data in-place. After snapping, export the modified datasets as usual (JSON/CSV).

- Dataset limits and colors:
  - The application defines `MAX_DATASETS = 6` and a `DEFAULT_COLORS` palette. Datasets are color-coded and the dataset color hex string is written into the JSON export so color associations are preserved.

Retrieving exported files
------------------------
- If a native Save dialog was used, pick the path you chose in the dialog.
- If the app fell back to writing into `Downloads` or the system temp directory, check the status label in the app for the full path written, or look in `~/Downloads` (or your platform's Downloads folder) for the generated filename.

If you want more compact or custom CSV/JSON formats (for example adding dataset indexes, timestamps, or extra metadata), I can add a toggle or additional export routine — tell me which fields you want included.

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
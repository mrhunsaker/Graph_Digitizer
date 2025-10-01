# GraphDigitizer

GraphDigitizer is a small GUI tool (Julia + Gtk) to digitize (extract) data points from raster images of graphs.  
It provides manual point picking, non-blocking calibration, a simple auto-trace routine, and export to JSON and CSV.

Version: 0.1.0

---

## Table of Contents

- Overview
- Requirements
- Installation
- Running
- Quickstart / How to use
  - Load an image
  - Calibrate (non-blocking)
  - Enter numeric axis ranges and apply
  - Add / move / delete points
  - Auto-trace
  - Save / Export (JSON and CSV)
  - Keyboard shortcuts & accelerators
  - Help & About
- File formats
- Default filenames and fallback behavior
- Troubleshooting
- Contributing
- License

---

## Overview

GraphDigitizer helps convert plotted curves in images (PNG / JPEG) into numeric point lists. The app supports multiple datasets (color-coded), per-dataset editing, auto-tracing for color-matched curves, and export to JSON (metadata + datasets) or CSV (rows: dataset, x, y).

---

## Requirements

- Julia 1.6+ (recommended)
- System GTK libraries (Gtk.jl requires GTK on your OS)
  - On Linux: your distribution's GTK 3/4 packages (e.g., `libgtk-3-dev`) may be required.
  - On macOS/Windows: Gtk.jl usually provides prebuilt binaries, but check Gtk.jl install errors if any native deps are missing.
- The project uses the following Julia packages (Project/Manifest should pin versions):
  - `Gtk`, `FileIO`, `ImageCore`, `ImageIO`, `Colors`, `JSON`, `CSV`, `DataFrames`, `Cairo`, `Graphics`, `GeometryBasics`

---

## Installation

1. Clone the repository:
   ```
   git clone <repo-url>
   cd GraphDigitizer
   ```

2. Install project dependencies:
   ```
   julia --project=@. -e 'using Pkg; Pkg.instantiate()'
   ```
   This will install packages pinned in the repository's `Project.toml`/`Manifest.toml`.

3. Make sure system GTK is installed if Gtk.jl raises an error during `Pkg.instantiate()` or first run.

---

## Running

From the project root:

```
julia --project=@. src/graph_digitizer.jl
```

The GUI window will open. Keep the terminal open to see diagnostic messages and warnings the app may print.

---

## Quickstart / How to use

This is a concise workflow to digitize a graph:

1. Load an image
   - Click the `Load Image` toolbar button and choose a PNG or JPEG image containing the plot.
   - After loading, the image displays in the central canvas.

2. Calibrate (non-blocking)
   - Click `Calibrate Clicks`. The app enters calibration mode and waits for you to click four points on the image in this order:
     1. X-left pixel (image coordinate corresponding to the known left-hand x value)
     2. X-right pixel (image coordinate corresponding to the known right-hand x value)
     3. Y-bottom pixel (image coordinate corresponding to a known bottom y value)
     4. Y-top pixel (image coordinate corresponding to a known top y value)
   - Each click records a pixel coordinate; the status label is updated as you click.

3. Enter numeric axis ranges and apply
   - Enter the numeric `X min`, `X max`, `Y min`, and `Y max` values into the text boxes below the menus.
   - Click `Apply Calibration` to apply the numeric mapping from pixel coordinates -> data coordinates.

4. Add / move / delete points
   - Left-click on the plotted curve to add a digitized point. The point coordinates are converted from canvas to data-space using the calibration settings.
   - To move a point: left-click near an existing point to select it, then drag to reposition.
   - To delete a selected point: click `Delete Selected Point` or press the Delete/Backspace key when a point is selected. Right-clicking a point also deletes it.

5. Auto-trace
   - Select the dataset (combo box) that contains the color you want the auto-trace to follow.
   - Click `Auto Trace Active Dataset`. The algorithm samples columns between the calibrated X pixel bounds and selects best-match rows by color distance to the dataset color.
   - The resulting points are assigned to the active dataset.

6. Save / Export (JSON and CSV)
   - Use the toolbar `Export JSON` / `Export CSV`, the `File` menu, or keyboard shortcuts to save:
     - Primary+S (Ctrl+S on Windows/Linux, Cmd+S on macOS) — Save JSON
     - Primary+Shift+S — Save CSV
   - Normal behavior: a Save dialog is presented where you can choose filename & location.
   - Fallback behavior: when a file dialog cannot be created (some Gtk.jl builds or environments), the app will automatically save to your `Downloads` folder using the `Title` field (if set) as the filename; otherwise a timestamped filename is used. The status label indicates the path used.

7. Keyboard shortcuts & accelerators
   - Save JSON: Ctrl+S (or Cmd+S on macOS)
   - Save CSV: Ctrl+Shift+S (or Cmd+Shift+S on macOS)
   - Exit: Ctrl+Q (or Cmd+Q on macOS)
   - Delete selected point: Delete/Backspace
   - Note: On some platforms or Gtk.jl builds, keyboard handling may vary slightly; accelerators are registered defensively.

8. Help & About
   - The menu bar next to `File` has a `Help` menu with:
     - `How to use` — opens a dialog showing README content (installation & usage).
     - `About` — shows application name, version, and copyright.

---

## File formats

- JSON export
  - Contains metadata and datasets. Typical structure:
    ```json
    {
      "title": "...",
      "xlabel": "...",
      "ylabel": "...",
      "x_min": ...,
      "x_max": ...,
      "y_min": ...,
      "y_max": ...,
      "x_log": true|false,
      "y_log": true|false,
      "datasets": [
        {
          "name": "Dataset 1",
          "color": "#0072B2",
          "points": [[x1, y1], [x2, y2], ...]
        }
      ]
    }
    ```

- CSV export
  - Three columns (no header is guaranteed, but typically): `dataset,x,y`
  - Each row corresponds to one point from a dataset.

---

## Default filenames and fallback behavior

- Preferred filename:
  - If you set the `Title` field in the UI, that text (sanitized) is used as the default filename when the app needs to auto-name a save file.
  - Illegal filename characters are replaced with underscores and repeated underscores are collapsed.
  - Example sanitized filename: `My_Graph_Title.json`

- Fallback path:
  - When the Save dialog is not available, GraphDigitizer will save to your `Downloads` folder (if present) or to the system temporary directory as a last resort.
  - The status label will include the exact fallback path used, so you can locate the file.

---

## Troubleshooting

- Save dialogs do not appear, or Save/Export buttons do nothing:
  - Check the terminal where you launched the app for errors (Gtk.jl often prints helpful messages).
  - The app will fall back to saving into `~/Downloads` (or OS equivalent) and will show the path in the status label.
  - If you see UndefVarError or missing symbol messages from Gtk, update Gtk.jl or install the required GTK runtime on your platform.

- Keyboard shortcuts not working:
  - Some window managers or platforms intercept certain key combos. Try using the File menu or toolbar buttons, and check the terminal for input-related warnings.
  - On macOS the `Primary` modifier maps to the Command (⌘) key.

- App crashes on load or during dialogs:
  - Ensure your GTK runtime is installed and matching Gtk.jl expectations. On Linux install GTK 3 development packages. On Windows/macOS, try updating Gtk.jl or reinstalling package binaries.
  - Report terminal error output if uncertain — copy/paste the stack trace to help diagnose the issue.

---

## Contributing

- Please open issues or PRs on the repository with:
  - Repro steps for bugs
  - Platform details (OS, Julia version, Gtk.jl version)
  - Terminal output (errors/warnings) when running the app

- Development convenience:
  - Use the repository Project/Manifest to reproduce the environment:
    ```
    julia --project=@. -e 'using Pkg; Pkg.instantiate()'
    ```

---

## License

This project is licensed under the Apache License, Version 2.0. See the LICENSE file in the repository for details.

---

If you run into any issues or want a specific change (different default directory, custom filename pattern, or additional menu items), tell me the platform you're testing on (Windows/macOS/Linux) and the Gtk.jl version reported by:

```julia
using Pkg
Pkg.status("Gtk")
```

I can provide a follow-up patch targeted to that environment.
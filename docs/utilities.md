# Graph Digitizer — Utilities Reference

This document describes the utility functions and small helpers used across the Graph Digitizer application. It documents purpose, behavior, signatures, and short usage examples for each helper. These utilities include color parsing, coordinate transforms, file-name helpers, safe dialog helpers, and small canvas drawing helpers used by the GUI.

> Note: Examples in this document are illustrative snippets showing how a function is typically used in the app. They assume `state::AppState` is available.
>
> This documentation and the examples are written with Windows and Linux systems in mind. Platform-specific guidance (for example, file chooser fallbacks and GTK runtime installation) references Windows/Linux behavior; where other platforms behave differently a generic note is given but Windows/Linux instructions are emphasized.

---

## Table of contents

- Color & image helpers
  - `hex_to_rgb`
  - `color_distance_rgb`
  - `parse_color`
  - `image_to_surface`
  - `compute_display_scale`
- Filename & README helpers
  - `_preferred_downloads_dir`
  - `_sanitize_filename`
  - `default_filename_for_save`
  - `default_filename_from_title`
  - `ensure_readme`
- Safe dialogs & focus helpers
  - `_get_focus_safe`
  - `safe_open_dialog`
  - `safe_save_dialog`
- Menu & accelerator helpers
  - `menu_item_with_accel`
  - `_add_accel`
- Drawing & precision helpers
  - `draw_magnifier`
  - `draw_zoom_circle`
- Coordinate transforms
  - `data_to_canvas`
  - `canvas_to_data`
- I/O helpers
  - `export_csv`
  - `export_json`

---

## Color & image helpers

### hex_to_rgb(hex::String) -> RGB{Float64}

Parse a hex color string (examples: `"#RRGGBB"`, `"#RGB"`, or named color) into `RGB{Float64}` with components in `[0,1]`.

- Behavior:
  - Attempts to parse using standard color parsing.
  - If parsing fails, falls back to hex decoding (supports 3- and 6-digit hex).
  - Returns `RGB(0,0,0)` on parse failure.

Example:
```/dev/null/example_hex_to_rgb.jl#L1-4
rgb = hex_to_rgb("#E69F00")
println(rgb)  # RGB{Float64}(0.90196, 0.62353, 0.0)
```

---

### color_distance_rgb(a::RGB{Float64}, b::RGB{Float64}) -> Float64

Compute Euclidean distance between two colors in RGB space. Used for simple color matching (auto-trace).

- Inlined small helper for performance.
- Returns a scalar distance in RGB units.

---

### parse_color(colname::String) -> (Float64, Float64, Float64)

Adapter returning an `(r,g,b)` triple of Float64 components for code that expects a 3-tuple rather than an `RGB` object. Internally uses `hex_to_rgb`.

---

### image_to_surface(img) -> Union{Nothing,Any}

Create a Cairo surface from an in-memory image object.

- Implementation note: writes the image to a temporary PNG and reads it with Cairo; returns `nothing` on failure.
- Typically used right after `load(...)` to produce a `img_surface` suitable for Cairo painting.

Example:
```/dev/null/example_image_surface.jl#L1-6
img = load("plot.png")          # from ImageIO/FileIO
surface = image_to_surface(img)
if surface === nothing
    println("Surface creation failed")
end
```

---

### compute_display_scale(state::AppState) -> Float64

Compute a uniform scale factor so the image fits into the canvas while preserving aspect ratio.

- Uses `state.img_w`, `state.img_h`, and canvas width/height to compute `min(sx, sy)`.
- Returns `1.0` when sizes are unknown.

---

## Filename & README helpers

### _preferred_downloads_dir() -> String

Return the user's Downloads directory when available (on Windows and Linux); otherwise fall back to `tempdir()`.

- Used by safe save fallbacks to choose a reasonable output folder if a file chooser is unavailable. On Windows and Linux this will typically prefer the user's `Downloads` folder; when that is not present or writable the system temporary directory is used.

---

### _sanitize_filename(s::AbstractString) -> String

Return a filesystem-safe base filename:

- Replaces non-alphanumeric characters (except `_.-`) with underscores.
- Collapses multiple underscores and trims leading/trailing underscores/dots.
- Returns an empty string for empty input.

---

### default_filename_for_save(state::AppState, ext::AbstractString) -> String

Create a sensible default filename for export using the Title entry as a base fallback to a timestamped name when empty. Places the resulting filename in the preferred downloads directory.

---

### default_filename_from_title(state::AppState, ext::AbstractString) -> String

Ensure the default filename has the requested extension (appends it if missing).

---

### ensure_readme()

Create a `README.md` in the current working directory if one does not exist. The function writes a short usage document describing the app and usage basics. This is a best-effort helper and ignores write errors.

---

## Safe dialogs & focus helpers

### _get_focus_safe(win)

Return the currently focused widget for `win`, or `nothing` if the focus cannot be queried. Wraps `Gtk.get_focus` in a try/catch to avoid exceptions.

---

### safe_open_dialog(state::AppState, title::String, parent, patterns::Vector{String}) -> String

Robust file-open helper that attempts several Gtk APIs to create a file chooser. If all GUI methods fail returns an empty string. Sets `state.modal_active` while active.

- `patterns` are file-filter patterns (e.g., `["*.png", "*.jpg"]`).
- Returns the selected filename or `""` when cancelled/unavailable.

---

### safe_save_dialog(state::AppState, title::String, parent, patterns::Vector{String}) -> String

Robust save helper. If a native Save dialog cannot be created the function will attempt to return a sensible fallback path (for example, using the image title / timestamp in the user's `Downloads` folder on Windows and Linux) and updates `state.status_label` to inform the user where the file was written.

- Returns the chosen filename or a fallback path (typically in `Downloads` on Windows/Linux or the system temporary directory), or `""` on error/cancel.

---

## Menu & accelerator helpers

### menu_item_with_accel(label_text::String, accel_text::String = "") -> Gtk.MenuItem

Create a menu item widget that displays a label and an accelerator hint aligned to the right.

- Attempts to use `Gtk.AccelLabel` where available and falls back to a plain label when not.

---

### _add_accel(widget, ag, keystr::String, signal::String = "activate")

Attach a keyboard accelerator to `widget` using `ag` (an `AccelGroup`) and key string such as `"<Ctrl>S"` or `"<Primary>S"`. This helper tries several Gtk APIs for compatibility across Gtk.jl versions.

---

## Drawing & precision helpers

### draw_magnifier(state::AppState, cr, x::Float64, y::Float64)

Draw a small magnifier (preview box) near the pointer showing a zoomed region of the image.

- Uses `state.img_surface` and `state.display_scale`.
- Intended for an on-canvas preview (not the precision circular zoom).

---

### draw_zoom_circle(state::AppState, cr, cx::Float64, cy::Float64)

Draw a circular precision zoom overlay centered at canvas coordinates `(cx, cy)`:

- The circle has an approximate physical radius of ~1 cm (in canvas pixels, based on assumed DPI).
- Areas inside the circle show a magnified rendering of the underlying image pixels (pixel-level magnification).
- The overlay is clipped to a circle so non-magnified content does not bleed in.
- Used in the Alt+Z precision placement mode to accurately set points.

Example (conceptual; used internally when `state.zoom_mode` is `true`):
```/dev/null/example_zoom_place.jl#L1-10
# When zoom_mode is active and a click occurs, the app places a point at zoom_center:
if state.zoom_mode && state.zoom_center !== nothing
    cx, cy = state.zoom_center
    x, y = canvas_to_data(state, cx, cy)
    push!(state.datasets[state.active_dataset].points, (x, y))
end
```

---

## Coordinate transforms

### data_to_canvas(state::AppState, dx::Float64, dy::Float64) -> (px::Float64, py::Float64)

Convert a data-space point `(dx, dy)` into canvas pixel coordinates.

- Requires calibration anchors: `px_xmin`, `px_xmax`, `px_ymin`, `px_ymax`.
- Respects `state.x_log` and `state.y_log` for log-scale axes.
- Returns `(0,0)` when calibration information is missing.

Example:
```/dev/null/example_data_to_canvas.jl#L1-4
px, py = data_to_canvas(state, 10.0, 200.0)
Cairo.arc(cr, px, py, 4.0, 0, 2pi)
```

---

### canvas_to_data(state::AppState, cx::Float64, cy::Float64) -> (dx::Float64, dy::Float64)

Inverse of `data_to_canvas`: convert canvas coordinates back to data values.

- Uses the calibration pixel anchors and numeric ranges.
- Respects logarithmic axes.
- Returns `(0,0)` if calibration is missing.

Example:
```/dev/null/example_canvas_to_data.jl#L1-4
x, y = canvas_to_data(state, mouse_x, mouse_y)
push!(state.datasets[state.active_dataset].points, (x, y))
```

---

## I/O helpers

### export_csv(state::AppState, fname::String)

Export all datasets to a CSV file with columns: `dataset`, `x`, `y`.

- Uses a `DataFrame` and `CSV.write`.
- Raises on I/O errors.

---

### export_json(state::AppState, fname::String)

Serialize the current application state to JSON:

- Includes title, axis labels, axis ranges, log flags, and dataset objects (name, color, points).
- Uses `JSON.print` to write the output.

---

## Usage notes and tips

- Precision placement (Alt+Z) uses the circular zoom overlay (1 cm approximate radius) to help pick a pixel-accurate location; clicking while enabled places a point at the zoom center.
- Auto-trace uses `color_distance_rgb` / `hex_to_rgb` to find nearest-colored pixels column-by-column.
- The safe dialog helpers are defensive; they set `state.modal_active` while active so other logic can know a modal action is in-progress and avoid re-entrancy.
- Calibration must be performed and numeric min/max applied before `data_to_canvas` / `canvas_to_data` transforms produce meaningful results.
- The utilities in this file are intentionally small and focused so they can be tested in isolation (for example, unit-tests for `_sanitize_filename`, `data_to_canvas` round-tripping, and `hex_to_rgb` parsing).

---

If you want, I can:
- Split individual utility docs into separate markdown pages under `docs/functions/`.
- Produce short unit-test examples for key transforms (calibration round-trip tests).
- Produce an HTML rendering (single-file) of these docs for local viewing.

Tell me which of those you'd like next.
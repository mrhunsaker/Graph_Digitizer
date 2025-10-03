# Graph_Digitizer API Reference

This document is an extracted API reference for the Graph Digitizer application. It summarizes the public types and primary functions defined in `src/graph_digitizer.jl`. The descriptions are derived from the docstrings present in the source and intended to help consumers of the code understand available primitives and how to use them. The guidance and platform-specific notes in this reference are written with Windows and Linux systems in mind.

Quick links
- Source: `src/graph_digitizer.jl`
- Repository README: `../README.md`
- Docs directory: `docs/`

## Table of contents

- Types
  - `Dataset`
  - `AppState`
- Utilities
  - `hex_to_rgb`
  - `color_distance_rgb`
  - `safe_parse_float`
  - `image_to_surface`
  - `compute_display_scale`
- Filename helpers & README
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
- Drawing, tracing & transforms
  - `draw_magnifier`
  - `parse_color`
  - `data_to_canvas`
  - `canvas_to_data`
  - `auto_trace_scan`
  - `draw_canvas`
- Other helpers
  - `find_nearest_point`
  - `set_label`
  - `export_csv`
  - `export_json`
- Exit helpers
  - `confirm_exit_and_maybe_save`
  - `force_quit`
- App lifecycle
  - `create_app`

---

## Types

### `Dataset`

A container for a single dataset stored by the application.

Fields:
- `name::String` — user-visible name of the dataset.
- `color::String` — color string (hex) associated with the dataset.
- `color_rgb::RGB{Float64}` — parsed RGB color for drawing.
- `points::Vector{Tuple{Float64,Float64}}` — list of (x, y) data points in data coordinates.

Used to keep per-dataset state (mutable).

### `AppState`

Global application state for the Graph Digitizer GUI.

Holds references to widgets, image surfaces, calibration parameters, datasets, and transient UI state (dragging, modal dialogs, etc). Consumers typically use this object to read or modify application state when implementing callbacks or I/O.

Key fields (not exhaustive):
- `win::GtkWindow`, `canvas::GtkCanvas` — main window and drawing canvas.
- `image`, `img_surface`, `img_w`, `img_h` — loaded image and derived surface/size.
- `display_scale`, `offset_x`, `offset_y` — scaling/offset used to display the image.
- `px_xmin`, `px_xmax`, `px_ymin`, `px_ymax` — calibration pixel positions (tuples).
- `x_min`, `x_max`, `y_min`, `y_max`, `x_log`, `y_log` — numeric axis ranges and log flags.
- `datasets::Vector{Dataset}`, `active_dataset::Int` — list of datasets and active index.
- `dragging`, `drag_idx` — dragging state for point editing.
- Widget references for UI inputs: `title_entry`, `xlabel_entry`, `ylabel_entry`, `status_label`.
- `modal_active`, `calibration_mode`, `calib_clicks` — modal flag and calibration click storage.

---

## Utilities

### `hex_to_rgb(hex::String) -> RGB{Float64}`

Convert a hex color string (e.g. `"#RRGGBB"` or `"#RGB"`) to `RGB{Float64}`.

- Attempts to parse using `Colorant` parsing first; falls back to manual hex parsing.
- Returns `RGB(0,0,0)` (black) on parse failure.

Arguments:
- `hex::String` — a hex color string (with or without leading `#`).

Returns:
- `RGB{Float64}` — parsed RGB color with components in `[0,1]`.

---

### `color_distance_rgb(a::RGB{Float64}, b::RGB{Float64}) -> Float64`

Compute Euclidean distance between two `RGB{Float64}` colors.

- Used for simple color matching.
- Inlined for performance.

Arguments:
- `a::RGB{Float64}`, `b::RGB{Float64}` — colors to compare.

Returns:
- `Float64` — Euclidean distance in RGB space.

---

### `safe_parse_float(entry::GtkEntry) -> Union{Float64,Nothing}`

Safely parse the text in a `GtkEntry` to a `Float64`.

- Trims whitespace and returns `nothing` if the entry is empty or not a valid float.

Arguments:
- `entry::GtkEntry` — widget holding the textual numeric input.

Returns:
- `Union{Float64,Nothing}` — parsed float or `nothing`.

---

### `image_to_surface(img) -> Union{Nothing,Any}`

Convert an image object to a Cairo surface suitable for drawing.

- Implementation saves the image to a temporary PNG and reads it with Cairo.
- Returns `nothing` on failure.

Arguments:
- `img` — image object (typ. from `load()`).

Returns:
- Cairo surface or `nothing`.

---

### `compute_display_scale(state::AppState) -> Float64`

Compute a display scaling factor for the current image and canvas size.

- Fits the image inside the canvas while preserving aspect ratio.
- Returns `1.0` when size info is missing.

Arguments:
- `state::AppState`

Returns:
- `Float64` — recommended display scale.

---

## Filename helpers & README

### `_preferred_downloads_dir() -> String`

Return the user's `Downloads` folder when available; otherwise fall back to `tempdir()`.

Used by fallback save routines.

---

### `_sanitize_filename(s::AbstractString) -> String`

Sanitize a string into a filesystem-safe base filename.

- Replaces non-alphanumeric (and non `._-`) characters with underscores.
- Collapses repeated underscores and trims leading/trailing underscores/dots.

Arguments:
- `s::AbstractString`

Returns:
- `String` — sanitized filename (may be empty).

---

### `default_filename_for_save(state::AppState, ext::AbstractString) -> String`

Create a sensible default filename for saving using the title entry or a timestamp.

Arguments:
- `state::AppState` — used to obtain title text.
- `ext::AbstractString` — file extension (without leading dot).

Returns:
- `String` — default file path in the preferred downloads directory.

---

### `default_filename_from_title(state::AppState, ext::AbstractString) -> String`

Ensure the derived filename has the requested extension.

---

### `ensure_readme()`

Ensure a `README.md` exists in the current working directory.

- If missing, writes a basic help file describing the app and usage.
- Best-effort: ignores write errors.

---

## Safe dialogs & focus helpers

### `_get_focus_safe(win)`

Robustly get the currently focused widget, returning `nothing` on error.

- Wraps `Gtk.get_focus` in try/catch to avoid exceptions in some states.

Arguments:
- `win` — window to query focus on.

Returns:
- Focused widget or `nothing`.

---

### `safe_open_dialog(state::AppState, title::AbstractString, parent, patterns::Vector{String}) -> String`

Show a safe file-open dialog and return the selected filename.

- Attempts several Gtk APIs; returns empty string if unavailable or cancelled.
- Sets `state.modal_active` while the helper is active.

Arguments:
- `state::AppState`
- `title::AbstractString` — dialog title.
- `parent` — parent widget (usually `state.win`).
- `patterns::Vector{String}` — file filter patterns (e.g. `["*.png", "*.jpg"]`).

Returns:
- `String` — selected filename or empty string.

---

### `safe_save_dialog(state::AppState, title::AbstractString, parent, patterns::Vector{String}) -> String`

Show a safe file-save dialog and return the selected filename.

- If a native dialog can't be constructed, returns a sensible fallback path (for example, the user's `Downloads` folder on Windows and Linux, or the system temporary directory) and updates the status label to inform the user where the file was written.
- Sets `state.modal_active` during operation.

Arguments:
- `state::AppState`
- `title::AbstractString`
- `parent`
- `patterns::Vector{String}` — used to infer extension for fallback.

Returns:
- `String` — destination filename or empty string.

---

## Menu & accelerator helpers

### `menu_item_with_accel(label_text::AbstractString, accel_text::AbstractString="") -> Gtk.MenuItem`

Construct a menu item widget with an accelerator label aligned on the right.

- Uses `Gtk.AccelLabel` when available and falls back to plain `Gtk.Label`.

Arguments:
- `label_text::AbstractString` — visible menu text.
- `accel_text::AbstractString` — accelerator hint (e.g. `"Ctrl+S"`).

Returns:
- `Gtk.MenuItem` — configured menu item widget.

---

### `_add_accel(widget, ag, keystr::AbstractString, signal::AbstractString="activate")`

Register an accelerator for a widget against an `AccelGroup` using a key string.

- Attempts several Gtk APIs to add the accelerator in a robust manner.

Arguments:
- `widget` — widget to attach accelerator to.
- `ag` — accelerator group (may be `nothing`).
- `keystr::AbstractString` — e.g. `"<Ctrl>S"` or `"<Primary>S"`.
- `signal::AbstractString` — signal to trigger (default `"activate"`).

---

## Drawing, tracing & transforms

### `draw_magnifier(state::AppState, cr, x::Float64, y::Float64)`

Draw an on-canvas magnifier showing a zoomed region centered at `(x, y)`.

Arguments:
- `state::AppState` — contains image, offsets, scale.
- `cr` — Cairo context.
- `x::Float64`, `y::Float64` — canvas coordinates to center magnifier.

---

### `parse_color(colname::String) -> Tuple{Float64,Float64,Float64}`

Parse a color string and return an `(r,g,b)` tuple of `Float64` components.

- Adapter for code that expects an RGB triple instead of an `RGB` object.

Arguments:
- `colname::String`

Returns:
- `(Float64,Float64,Float64)` — RGB components in `[0,1]`.

---

### `data_to_canvas(state::AppState, dx::Float64, dy::Float64) -> (px, py)`

Transform a data-space point `(dx, dy)` into canvas pixel coordinates.

- Uses calibration pixel positions (`px_xmin`, `px_xmax`, `px_ymin`, `px_ymax`) and numeric ranges.
- Honors logarithmic axes when `x_log` or `y_log` flags are set.

Arguments:
- `state::AppState`, `dx::Float64`, `dy::Float64`

Returns:
- `(Float64,Float64)` — canvas coordinates `(px, py)`. Returns `(0,0)` if not calibrated.

---

### `canvas_to_data(state::AppState, cx::Float64, cy::Float64) -> (dx, dy)`

Inverse of `data_to_canvas`: convert canvas coordinates to data values.

Arguments:
- `state::AppState`, `cx::Float64`, `cy::Float64`

Returns:
- `(Float64,Float64)` — `(x,y)` in data coordinates. Returns `(0,0)` if not calibrated.

---

### `auto_trace_scan(state::AppState, target_rgb::RGB{Float64}) -> Vector{Tuple{Float64,Float64}}`

Perform an auto-trace scan across the calibrated X range attempting to find the best color match per column for `target_rgb`.

- Scans pixel columns between calibrated X pixel positions.
- For each column finds the pixel row with minimal color distance to `target_rgb`.
- Converts found canvas coordinates to data coordinates and returns them.

Arguments:
- `state::AppState` — must include image and calibration.
- `target_rgb::RGB{Float64}`

Returns:
- `Vector{Tuple{Float64,Float64}}` — sampled data points.

---

### `draw_canvas(state::AppState, cr)`

Draw the main canvas including the image, calibration markers, calibration click overlays, and dataset points.

- Intended for use as the canvas draw callback; expects a Cairo context `cr`.

Arguments:
- `state::AppState`, `cr` (Cairo context)

---

## Other helpers

### `find_nearest_point(state::AppState, x::Float64, y::Float64, maxdist::Float64) -> Union{Tuple{Int,Int},Nothing}`

Find the nearest dataset point (in canvas coordinates) to the given canvas position `(x,y)`.

- Returns a tuple `(dataset_index, point_index)` if a point is within `maxdist` pixels, otherwise `nothing`.

Arguments:
- `state::AppState`, `x::Float64`, `y::Float64`, `maxdist::Float64`

Returns:
- `(Int,Int)` or `nothing`.

---

### `set_label(lbl::GtkLabel, txt::AbstractString)`

Set the text of a `GtkLabel` in a safe, best-effort manner.

- Wraps `Gtk.set_gtk_property!` and ignores errors on older/newer Gtk implementations.

Arguments:
- `lbl::GtkLabel`, `txt::AbstractString`

---

### `export_csv(state::AppState, fname::String)`

Export all datasets to a CSV file.

- CSV columns: `dataset`, `x`, `y`.
- Uses `CSV.write` and will raise on I/O errors.

Arguments:
- `state::AppState`, `fname::String`

---

### `export_json(state::AppState, fname::String)`

Export the full application data to a JSON file.

- Serializes title, axis labels, numeric ranges, log flags, and each dataset (name, color, points).

Arguments:
- `state::AppState`, `fname::String`

---

## Exit helpers

### `confirm_exit_and_maybe_save(state::AppState) -> Bool`

Prompt the user to save before exiting.

- Shows a dialog with `Save`, `Discard`, and `Cancel`.
- If GUI dialogs are unavailable a fallback save via `safe_save_dialog` is attempted.
- Returns `true` when it is OK to exit (either saved or discard chosen); returns `false` if the user cancels.

Arguments:
- `state::AppState`

Returns:
- `Bool`

---

### `force_quit(state::AppState)`

Forcefully quit the application by attempting several shutdown paths.

- Clears `state.modal_active`, attempts `Gtk.main_quit()`, destroys the main window, and falls back to other destruction APIs as available.

Arguments:
- `state::AppState`

---

## App lifecycle

### `create_app() -> AppState`

Construct and initialize the full Graph Digitizer application UI.

- Creates the main window, widgets, signal handlers, and returns an `AppState`.
- The returned `AppState` is wired with handlers for: loading images, calibration, point editing, auto-trace, saving, and exit.
- The window is created but not necessarily shown by the caller.

Returns:
- `AppState` — initialized app state (window & widgets ready).

---

## Notes & Usage Tips

- Calibration: the app expects four calibration clicks in the order: X-left pixel, X-right pixel, Y-bottom pixel, Y-top pixel. After clicking, numeric axis min/max values must be entered and "Apply Calibration" pressed.
- Auto-trace: use a dataset's `color` value (hex) as the target color for `auto_trace_scan`. The result replaces that dataset's `points`.
- Save/Export: JSON and CSV save helpers exist; `safe_save_dialog` will fallback to the user's Downloads directory when a file chooser dialog cannot be shown (for headless or constrained environments).
- The API documented here is primarily aimed at developers who want to script or extend the GUI or reuse cores of the logic (calibration mapping, image surface bridging, auto-trace algorithm). Platform-specific notes and examples within this reference are oriented toward Windows and Linux environments; where platform behavior differs (file chooser fallbacks, system GTK availability), Windows/Linux guidance is emphasized.

---

If you want this reference rendered differently (e.g., HTML, or split per module/function with examples), I can produce an alternate format or add usage examples for specific functions like `auto_trace_scan` or `canvas_to_data`.
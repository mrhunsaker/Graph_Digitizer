# Graph Digitizer — Types Reference

This document describes the primary types used by Graph Digitizer, their fields, and example usage patterns. It is intended for developers who want to extend the application, script programmatic interactions, or understand the in-memory data model. This documentation and the examples are written with Windows and Linux users in mind; platform-specific guidance in this file emphasizes Windows/Linux behaviors (for example, file chooser fallbacks and GTK runtime installation).

## Dataset

A small mutable container that represents a single dataset visible in the UI.

Fields
- `name::String`  
  Human-readable dataset name shown in UI controls and used in exported files.

- `color::String`  
  Hex color string used for the dataset (e.g. `"#0072B2"`). Stored as text so it can round-trip through JSON and user-editable fields.

- `color_rgb::RGB{Float64}`  
  Parsed `RGB` color with components in the range `[0, 1]`. Used for drawing points and overlays with Cairo.

- `points::Vector{Tuple{Float64,Float64}}`  
  The list of data-space points for the dataset. Each item is a `(x, y)` tuple stored in data coordinates (not pixel/canvas coordinates). These points are what get exported to CSV/JSON and displayed after conversion to canvas coordinates by `data_to_canvas`.

Example
```julia
ds = Dataset("MyCurve", "#E69F00", hex_to_rgb("#E69F00"), [(1.0, 2.5), (2.0, 3.7)])
```

## AppState

Central application state object. An instance of `AppState` is created when the UI is constructed and passed to callbacks so they can inspect and mutate shared state. It contains widget references, image surfaces, calibration information, datasets, UI flags, and other transient values.

Important fields (selected)
- `win::GtkWindow` — main application window.
- `canvas::GtkCanvas` — main drawing surface widget.
- `image` / `img_surface` — the loaded image and a Cairo surface derived from it (used for drawing).
- `img_w::Int`, `img_h::Int` — pixel dimensions of the loaded image.
- `display_scale::Float64` — current uniform scale factor used to draw the image into the canvas.
- `offset_x::Float64`, `offset_y::Float64` — top-left offset (in canvas coordinates) where the image is drawn.
- `px_xmin`, `px_xmax`, `px_ymin`, `px_ymax` — calibration pixel positions recorded during calibration clicks. Each is either `nothing` or a tuple `(x_pixel, y_pixel)` in canvas coordinates.
- `x_min`, `x_max`, `y_min`, `y_max` — numeric axis ranges (data values) entered/applied by the user.
- `x_log`, `y_log` — booleans indicating whether the corresponding axis should be interpreted on a log10 scale.
- `datasets::Vector{Dataset}` — vector of `Dataset` instances (max controlled by `MAX_DATASETS`).
- `active_dataset::Int` — 1-based index of the currently active dataset.
- `dragging::Bool` — whether a point is currently being dragged.
- `drag_idx::Union{Nothing, Tuple{Int,Int}}` — when dragging, `(dataset_index, point_index)` of the point being moved.
- `title_entry::GtkEntry`, `xlabel_entry::GtkEntry`, `ylabel_entry::GtkEntry` — widget references for form fields.
- `status_label::GtkLabel` — UI label used for status messages.
- `magnifier_enabled::Bool` — whether the magnifier overlay is enabled.
- `modal_active::Bool` — flag set while file chooser dialogs or other modal helpers are active.

Precision/zoom helper fields
- `last_mouse::Tuple{Float64,Float64}` — last observed canvas mouse position (used as the initial center for precision zoom).
- `zoom_mode::Bool` — when `true`, the circular precision zoom overlay is displayed and clicks place points at the overlay center.
- `zoom_center::Union{Nothing,Tuple{Float64,Float64}}` — the center of the zoom overlay while zoom mode is active (canvas coordinates).
- `zoom_radius_px::Float64` — requested radius of the zoom circle (in canvas pixels; an approximation of ~1 cm by default).
- `zoom_level::Float64` — magnification applied to the region inside the zoom circle.

Calibration-related notes
- Calibration is performed by recording four canvas pixel positions using the "Calibrate Clicks" workflow:
  1. X-left pixel (leftmost known x)
  2. X-right pixel (rightmost known x)
  3. Y-bottom pixel (bottom known y)
  4. Y-top pixel (top known y)
- After the four clicks are recorded into `px_xmin`, `px_xmax`, `px_ymin`, `px_ymax`, the user enters numeric `x_min`, `x_max`, `y_min`, `y_max` and presses "Apply Calibration". The application then maps data ↔ canvas using those calibration anchors and the log flags.

## Common usage examples

1) Convert a data point to canvas coordinates (useful for drawing):
```julia
px, py = data_to_canvas(state, data_x, data_y)
# px, py can be used with Cairo drawing functions
```

2) Convert a canvas position (mouse click) to data-space:
```julia
xval, yval = canvas_to_data(state, mouse_x, mouse_y)
# store in the active dataset:
push!(state.datasets[state.active_dataset].points, (xval, yval))
```

3) Enable precision zoom programmatically:
```julia
state.zoom_mode = true
state.zoom_center = (400.0, 250.0)     # canvas coordinates
state.zoom_level = 6.0                 # magnification
# trigger a canvas redraw to show the overlay
draw(state.canvas)
```

4) Auto-trace active dataset color (high-level):
```julia
ds = state.datasets[state.active_dataset]
sampled = auto_trace_scan(state, hex_to_rgb(ds.color))
state.datasets[state.active_dataset].points = sampled
```

## Design principles

- The `AppState` is intentionally a single central mutable object to simplify wiring between GTK callbacks. Callbacks accept the state and mutate it rather than relying on global variables.
- Data stored in `Dataset.points` is always in data coordinates. Drawing and hit-testing translate between data and canvas coordinates with `data_to_canvas` and `canvas_to_data`.
- UI features that depend on platform-specific GTK behavior (file choosers, accelerators) are implemented defensively; helpers like `safe_open_dialog` and `safe_save_dialog` set `modal_active` and provide reasonable fallbacks when native dialogs are unavailable.

## Extending or testing

- To test coordinate transforms, construct a minimal `AppState` with `px_*` anchors and numeric ranges, then verify `data_to_canvas` and `canvas_to_data` round-trip sample points.
- To add new dataset-level metadata, extend the `Dataset` struct and update JSON serialization (`export_json`) and any UI code that reads/writes the new field.

---

If you want, I can also generate a `fields-table` (CSV/markdown table) enumerating every `AppState` field with type and short description, or produce example unit tests demonstrating calibration and transform correctness.
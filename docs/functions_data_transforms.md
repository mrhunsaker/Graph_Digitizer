# Graph_Digitizer — Data Transforms, Dialogs & Drawing (Function Reference)

This document collects focused, per-function documentation for the key functional areas:
- Data transforms (coordinate mapping between image/data and canvas),
- Safe file dialogs and focus helpers,
- Drawing helpers (magnifier and precision zoom),
- A minimal `index.html` snippet to link this doc from a static docs site.

Use this reference to understand function signatures, expected state, examples, and important caveats. These functions are defined in `src/graph_digitizer.jl`.

---

## Table of contents

- Data transforms
  - `data_to_canvas(state, dx, dy)`
  - `canvas_to_data(state, cx, cy)`
- Safe dialogs & focus helpers
  - `_get_focus_safe(win)`
  - `safe_open_dialog(state, title, parent, patterns)`
  - `safe_save_dialog(state, title, parent, patterns)`
- Drawing helpers
  - `draw_magnifier(state, cr, x, y)`
  - `draw_zoom_circle(state, cr, cx, cy)`
  - `draw_canvas(state, cr)` (notes on zoom overlay)
- Static docs index (HTML snippet)

---

## Data transforms

These functions convert coordinates between the application's data-space (user/X-Y values) and canvas pixel coordinates used for drawing and hit-testing. They depend on the calibration anchors recorded by the user.

### data_to_canvas(state, dx, dy)
Signature:
- `data_to_canvas(state::AppState, dx::Float64, dy::Float64) -> (px::Float64, py::Float64)`

Purpose:
- Convert a data-space point (dx, dy) into canvas pixel coordinates for drawing.
- Returns `(0.0, 0.0)` if calibration anchors are missing.

Inputs:
- `state` — AppState containing calibration anchors:
  - `px_xmin`, `px_xmax`, `px_ymin`, `px_ymax` (expected as canvas pixel tuples (x, y)),
  - numeric axis ranges `x_min`, `x_max`, `y_min`, `y_max`,
  - `x_log` and `y_log` booleans to indicate log10-scaled axes.
- `dx`, `dy` — numeric data coordinates to map.

Behavior:
- If the corresponding axis is linear, performs a simple linear interpolation between pixel anchors and numeric range.
- If axis is logarithmic, maps using base-10 logs: uses log10(dx) and log10(range).
- Produces canvas X coordinate by interpolating between `px_xmin[1]` and `px_xmax[1]`.
- Produces canvas Y coordinate by interpolating between `px_ymin[2]` and `px_ymax[2]`.

Edge cases:
- When `dx` or `dy` are non-positive and their axis is log-scale, the result clamps to the anchor end (function uses a safe fallback to avoid NaNs).
- If calibration anchors are `nothing`, the function returns `(0, 0)`.

Example:
```/dev/null/example_data_to_canvas.jl#L1-4
px, py = data_to_canvas(state, 12.3, 45.6)
# px,py can be fed directly to Cairo drawing APIs
```

Testing tips:
- Unit test roundtrip: given anchors and ranges, compute px,py = data_to_canvas(...), then compute dx2,dy2 = canvas_to_data(..., px, py) and assert dx2 ≈ dx and dy2 ≈ dy (within numerical tolerances).

---

### canvas_to_data(state, cx, cy)
Signature:
- `canvas_to_data(state::AppState, cx::Float64, cy::Float64) -> (dx::Float64, dy::Float64)`

Purpose:
- Convert canvas pixel coordinates `(cx, cy)` to data values `(x, y)`.
- Inverse of `data_to_canvas` with equivalent handling of log axes.

Inputs:
- `state` — same as above; requires calibration anchors and numeric ranges.
- `cx`, `cy` — canvas pixel coordinates (e.g., from mouse events).

Behavior:
- Computes interpolation fraction `t` between anchor pixels for X and `u` for Y.
- If axis is log-scale, computes value using 10^(log10(min) + t * (log10(max) - log10(min))).
- Returns `(0.0, 0.0)` if calibration anchors are missing.

Edge cases:
- Zero-length anchor spans: when `xpx2 - xpx1 == 0` or `ypx2 - ypx1 == 0` the function avoids division by zero by setting the fraction to 0.0.

Example:
```/dev/null/example_canvas_to_data.jl#L1-3
xval, yval = canvas_to_data(state, event.x, event.y)
push!(state.datasets[state.active_dataset].points, (xval, yval))
```

Testing tips:
- Validate preconditions (anchors and ranges set) and assert expected numeric outcomes for known anchor/test points.

---

## Safe dialogs & focus helpers

The app must run across different platforms and Gtk.jl versions. These helpers construct file chooser dialogs defensively and expose fallbacks.

### _get_focus_safe(win)
Signature:
- `_get_focus_safe(win) -> widget_or_nothing`

Purpose:
- Wrap `Gtk.get_focus(win)` in a try/catch and return `nothing` on error.

Usage:
- Useful when needing to find which widget has keyboard focus; safe for all Gtk versions.

---

### safe_open_dialog(state, title, parent, patterns)
Signature:
- `safe_open_dialog(state::AppState, title::AbstractString, parent, patterns::Vector{String}) -> String`

Purpose:
- Show a file-open dialog robustly; if a native dialog cannot be created, the function returns an empty string.
- Sets `state.modal_active = true` while active so other code can detect modal state.

Inputs:
- `state` — used for the `modal_active` flag.
- `title` — dialog title.
- `parent` — parent widget (usually `state.win`).
- `patterns` — file filter patterns like `["*.png", "*.jpg"]`.

Return value:
- Selected filename string (absolute) or empty string if cancelled/unavailable.

Notes:
- The function tries several Gtk constructors and falls back to a non-modal message if none succeed.
- Always clears `state.modal_active` in a `finally` block.

Example:
```/dev/null/example_safe_open.jl#L1-6
fname = safe_open_dialog(state, "Open Image", state.win, ["*.png", "*.jpg"])
if fname != ""
    img = load(fname)
    ...
end
```

---

### safe_save_dialog(state, title, parent, patterns)
Signature:
- `safe_save_dialog(state::AppState, title::AbstractString, parent, patterns::Vector{String}) -> String`

Purpose:
- Show a robust save dialog. If a native Save dialog cannot be made, returns a sensible fallback path (Downloads or temp) and updates `state.status_label`.

Inputs & returns:
- Same parameters as `safe_open_dialog`.
- Returns chosen filename (possibly a fallback path) or `""` on cancel/error.

Behavioral details:
- Attempts to infer extension from `patterns` (e.g., if `*.json` present, uses `.json`).
- Uses `default_filename_for_save(state, ext)` to compute fallback path.
- Communicates fallback action via `state.status_label`.

Usage pattern:
- Use this helper for all save/export flows so the application works even in restricted environments.

---

## Drawing helpers

Drawing helpers implement both UI niceties (magnifier) and the precision circular zoom (Alt+Z) requested for pixel-level placement.

Notes:
- All drawing functions expect a valid Cairo context (named `cr` in the app).
- `draw_canvas(state, cr)` is the application's central canvas render function; it delegates to other helpers as needed.

---

### draw_magnifier(state, cr, x, y)
Signature:
- `draw_magnifier(state::AppState, cr, x::Float64, y::Float64)`

Purpose:
- Draw a small rectangular magnifier preview near `(x, y)` that shows a zoomed portion of the image.
- This is a lighter-weight preview than the circular precision zoom and is used by the "Magnifier" toggle.

Behavior:
- Computes a source window around `(x, y)` in image coordinates and paints it (scaled) into a small rectangular region offset from the pointer.
- Has a white background and thin border to make the preview readable.

Caveats:
- Requires `state.img_surface` to be non-`nothing`.
- Respects `state.display_scale` when computing source/destination rectangles.

---

### draw_zoom_circle(state, cr, cx, cy)
Signature:
- `draw_zoom_circle(state::AppState, cr, cx::Float64, cy::Float64)`

Purpose:
- Draw a circular precision zoom overlay centered at `(cx, cy)` with an approximate physical radius of 1 cm (in canvas pixels), and magnify the pixels inside that circle.
- Intended for precise pixel-level selection when zoom mode is active (Alt+Z).

Behavior:
- Computes a source region in image pixel coordinates based on `cx/cy`, `state.display_scale`, and `zoom_level`.
- Clips drawing to the circular region so only the magnified pixels are visible within the circle.
- Draws a guide circle outline so users can place points relative to the circle center.
- Attempts to draw a subtle pixel grid overlay inside the circle (best-effort) to show pixel boundaries at high magnification.

Important parameters:
- `state.zoom_radius_px` — radius of the circle in canvas px (approx 1 cm converted to px at the current DPI).
- `state.zoom_level` — magnification factor (e.g. 6x).
- The overlay uses `state.img_surface` and `state.display_scale`; if those are missing the overlay will not be rendered.

Interaction model (used by the app):
- Pressing Alt+Z toggles `state.zoom_mode` and sets `state.zoom_center` to the current mouse position (or last seen position).
- While `zoom_mode` is active, moving the pointer updates `state.zoom_center`.
- Clicking the left mouse button when `zoom_mode` is active places a point at the `zoom_center` location (converted back to data coordinates using `canvas_to_data`) — allowing precise placement.

Example usage flow:
1. Ensure an image is loaded and calibration applied.
2. Move mouse to desired approximate location.
3. Press Alt+Z to toggle zoom mode (a circular zoom appears).
4. Refine pointer position; click to place the point at the center of the circle.
5. Press Alt+Z again to exit zoom mode.

---

### draw_canvas(state, cr) — Notes re: zoom overlay
- This is the main canvas rendering function. Typical responsibilities:
  - Clear background and paint the loaded image (scaled and offset).
  - Draw calibration anchors and calibration click overlays.
  - Draw dataset points (converted from data to canvas).
  - If `state.zoom_mode` is enabled and `state.zoom_center` is set, call `draw_zoom_circle(state, cr, cx, cy)` to draw the precision overlay.
  - If the user has also enabled the standard magnifier toggle, optionally draw the rectangular magnifier near the pointer.

Performance:
- Keep heavy computations out of the paint handler; precompute `state.display_scale` and offsets before drawing where possible.
- Avoid allocating large temporary arrays in the draw path (e.g., for grids). The implementation uses small, bounded loops only when necessary.

---

## Index HTML (simple template)

If you want a tiny static HTML index page to link the generated markdown docs (`docs/API_REFERENCE.md`, `docs/types.md`, `docs/utilities.md`, `docs/functions_data_transforms.md`, etc.), here is a minimal example you can drop into `docs/index.html`:

```/dev/null/docs_index.html#L1-60
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Graph Digitizer Docs</title>
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <style>
    body { font-family: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial; margin: 32px; line-height:1.5; }
    nav { margin-bottom: 24px; }
    a { color: #0b66c2; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .section { margin-bottom: 20px; }
  </style>
</head>
<body>
  <h1>Graph Digitizer — Documentation</h1>
  <nav>
    <ul>
      <li><a href="API_REFERENCE.md">API Reference</a></li>
      <li><a href="types.md">Types</a></li>
      <li><a href="utilities.md">Utilities</a></li>
      <li><a href="functions_data_transforms.md">Data Transforms & Drawing (this page)</a></li>
    </ul>
  </nav>
  <p>Click a page to view the generated markdown documentation. For offline browsing open the .md files in a Markdown viewer or render them with a static site generator.</p>
</body>
</html>
```

Notes:
- This file assumes your static site setup serves the `.md` files (e.g., via a Markdown-aware static viewer) or you will convert them to HTML with a generator (like MkDocs, Jekyll, or a simple markdown-to-html tool).
- If you want I can provide a ready-made conversion (markdown -> HTML) for each page and create a small multipage site, but I didn't create those HTML files automatically here — only the index snippet.

---

## Testing & QA suggestions

- Add unit tests for `data_to_canvas` and `canvas_to_data` round-trip for linear and log scales. Use small tolerances for floating point checks.
- Add tests for `_sanitize_filename` with a set of representative input strings (Unicode, spaces, punctuation).
- Validate `safe_save_dialog` fallback extension inference by calling it with `["*.json"]`, `["*.csv"]`, and other patterns (mocking or stubbing dialog creation if running headless).
- Test the precision zoom interaction manually:
  - Load a test image with visible pixels (e.g., a checkerboard).
  - Calibrate so the mapping is known.
  - Move the cursor, press Alt+Z, verify the magnified circle appears and clicking places a point at the circle center.

---

If you'd like, I can:
- Split this single file into multiple function-level markdown files (one per function).
- Produce HTML files rendered from these pages and create a `docs/index.html` that links them.
- Provide small example scripts/tests that exercise calibration and transform behavior.

Which next step do you want me to do?
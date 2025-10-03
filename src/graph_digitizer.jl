# Graph Digitizer — Julia
#
# Copyright 2025  Michael Ryan Hunsaker, M.Ed., Ph.D.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Usage:
# julia --project=@. src/graph_digitizer.jl

using Gtk
using FileIO
using ImageCore
using ImageIO
using Colors
using JSON
using CSV
using DataFrames
using Cairo
using Graphics
using GeometryBasics
using Dates

# --------------------------
# Constants & Types
# --------------------------
const APP_VERSION = "0.1.0"
const MAX_DATASETS = 6
const DEFAULT_COLORS = ["#0072B2", "#E69F00", "#009E73", "#CC79A7", "#F0E442", "#56B4E9"]

"""
A container for a single dataset stored by the application.

Fields:
- `name::String` : user-visible name of the dataset.
- `color::String` : color string (hex) associated with the dataset.
- `color_rgb::RGB{Float64}` : parsed RGB color for drawing.
- `points::Vector{Tuple{Float64,Float64}}` : list of (x, y) data points in data coordinates.

This is a simple mutable struct used to keep per-dataset state.
"""
mutable struct Dataset
    name::String
    color::String
    color_rgb::RGB{Float64}
    points::Vector{Tuple{Float64,Float64}}
end

"""
Global application state for the Graph Digitizer GUI.

Holds references to important widgets, image surfaces, calibration parameters,
datasets, and transient UI state (dragging, modal dialogs, etc).

Fields are documented inline in the source; consumers typically use this object
to read or modify application state when implementing callbacks or I/O.
"""
mutable struct AppState
    win::GtkWindow
    canvas::GtkCanvas
    image::Union{Nothing,Any}
    img_surface::Union{Nothing,Any}
    img_w::Int
    img_h::Int
    display_scale::Float64
    offset_x::Float64
    offset_y::Float64

    px_xmin::Union{Nothing,Tuple{Float64,Float64}}
    px_xmax::Union{Nothing,Tuple{Float64,Float64}}
    px_ymin::Union{Nothing,Tuple{Float64,Float64}}
    px_ymax::Union{Nothing,Tuple{Float64,Float64}}

    x_min::Float64
    x_max::Float64
    y_min::Float64
    y_max::Float64
    x_log::Bool
    y_log::Bool

    datasets::Vector{Dataset}
    active_dataset::Int

    dragging::Bool
    drag_idx::Union{Nothing,Tuple{Int,Int}}

    title_entry::GtkEntry
    xlabel_entry::GtkEntry
    ylabel_entry::GtkEntry
    status_label::GtkLabel

    # Lightweight pointer tracking & zoom support for precise point placement.
    # `last_mouse` stores the most recent canvas mouse position (x,y) which is
    # used by the Alt+Z precision zoom feature.
    last_mouse::Tuple{Float64,Float64}
    # Toggle that enables the precision zoom overlay. When `true` a circular
    # zoom overlay is drawn centered at `zoom_center`.
    zoom_mode::Bool
    # Center of the zoom overlay in canvas coordinates, or `nothing` when inactive.
    zoom_center::Union{Nothing,Tuple{Float64,Float64}}
    # Requested radius of the zoom circle in canvas pixels (computed from cm).
    zoom_radius_px::Float64
    # Magnification factor applied inside the zoom circle.
    zoom_level::Float64

    # Modal flag to indicate a file chooser / modal dialog is active.
    modal_active::Bool

    # Non-blocking calibration fields
    calibration_mode::Bool
    calib_clicks::Vector{Tuple{Float64,Float64}}
end

# --------------------------
# Utilities
# --------------------------

"""
Convert a hex color string (e.g. "#RRGGBB" or "#RGB") to `RGB{Float64}`.

Attempts to parse using Colorant parsing first; falls back to hexadecimal
parsing if necessary. Returns black (`RGB(0,0,0)`) on parse failure.

Arguments:
- `hex::String` : a hex color string (with or without leading '#').

Returns:
- `RGB{Float64}` : parsed RGB color with components in [0,1].
"""
function hex_to_rgb(hex::String)::RGB{Float64}
    try
        c = parse(Colorant, hex)
        return RGB{Float64}(c)
    catch
        h = replace(hex, "#" => "")
        if length(h) == 3
            h = string(h[1], h[1], h[2], h[2], h[3], h[3])
        end
        if length(h) == 6
            r = parse(Int, h[1:2], base=16) / 255
            g = parse(Int, h[3:4], base=16) / 255
            b = parse(Int, h[5:6], base=16) / 255
            return RGB{Float64}(r, g, b)
        end
        return RGB{Float64}(0, 0, 0)
    end
end

"""
Compute Euclidean distance between two `RGB{Float64}` colors.

This helper is used for simple color matching and is inlined for performance.

Arguments:
- `a::RGB{Float64}` : first color.
- `b::RGB{Float64}` : second color.

Returns:
- `Float64` : Euclidean distance in RGB space.
"""
@inline function color_distance_rgb(a::RGB{Float64}, b::RGB{Float64})
    dr = a.r - b.r
    dg = a.g - b.g
    db = a.b - b.b
    return sqrt(dr * dr + dg * dg + db * db)
end

"""
Safely parse the text in a `GtkEntry` to a `Float64`.

Trims whitespace and returns `nothing` if the entry is empty or not a valid
floating point number.

Arguments:
- `entry::GtkEntry` : widget holding the textual numeric input.

Returns:
- `Union{Float64,Nothing}` : parsed float or `nothing` if invalid.
"""
function safe_parse_float(entry::GtkEntry)
    txt = Gtk.get_gtk_property(entry, :text, String)
    txt = strip(txt)
    if isempty(txt)
        return nothing
    end
    v = tryparse(Float64, txt)
    return v
end

"""
Convert an image object to a Cairo surface suitable for drawing.

This implementation writes the image to a temporary PNG file and uses Cairo to
read that file into a surface. Returns `nothing` on failure.

Arguments:
- `img` : image object (typically returned by `load()`).

Returns:
- `Union{Nothing,Any}` : Cairo surface or `nothing` if conversion failed.
"""
function image_to_surface(img)::Union{Nothing,Any}
    tmp = tempname() * ".png"
    try
        FileIO.save(tmp, img)
        surf = Cairo.read_from_png(tmp)
        return surf
    catch e
        @warn "Failed to create image surface: $e"
        return nothing
    end
end

"""
Compute a display scaling factor for the current image and canvas size.

Given the `AppState` with image dimensions and the canvas widget, returns the
scaling factor that fits the image inside the canvas while preserving aspect
ratio. If image or canvas sizes are not available returns `1.0`.

Arguments:
- `state::AppState` : application state containing image and canvas.

Returns:
- `Float64` : recommended display scale.
"""
function compute_display_scale(state::AppState)
    if state.img_surface === nothing
        return 1.0
    end
    cw = Gtk.width(state.canvas)
    ch = Gtk.height(state.canvas)
    if state.img_w == 0 || state.img_h == 0 || cw == 0 || ch == 0
        return 1.0
    end
    sx = cw / state.img_w
    sy = ch / state.img_h
    return min(sx, sy)
end

# --------------------------
# Filename helpers & README creation
# --------------------------

"""
Return the user's Downloads folder when available, otherwise fallback to `tempdir()`.

This is a small helper used by fallback save routines when a file chooser dialog is
not available.
"""
function _preferred_downloads_dir()::String
    try
        d = joinpath(homedir(), "Downloads")
        if isdir(d)
            return d
        else
            return tempdir()
        end
    catch
        return tempdir()
    end
end

"""
Sanitize a string into a filesystem-safe base filename.

Removes or replaces characters that are likely to be problematic in filenames and
collapses repeated underscores. Trims leading/trailing underscores or dots.

Arguments:
- `s::AbstractString` : input string (e.g. title).

Returns:
- `String` : sanitized filename (may be empty if input was empty).
"""
function _sanitize_filename(s::AbstractString)::String
    s = strip(String(s))
    if isempty(s)
        return ""
    end
    # Replace disallowed characters with underscore
    t = replace(s, r"[^A-Za-z0-9_.-]" => "_")
    # Collapse multiple underscores
    t = replace(t, r"_+" => "_")
    # Trim leading/trailing underscores or dots
    t = replace(t, r"^[_.]+|[_.]+$" => "")
    return isempty(t) ? "" : t
end

"""
Create a sensible default filename for saving using the title entry or a timestamp.

Arguments:
- `state::AppState` : application state (used to obtain title text).
- `ext::AbstractString` : file extension (without leading dot).

Returns:
- `String` : path to a default filename in the preferred downloads directory.
"""
function default_filename_for_save(state::AppState, ext::AbstractString)::String
    title = try
        Gtk.get_gtk_property(state.title_entry, :text, String)
    catch
        ""
    end
    base = _sanitize_filename(title)
    if isempty(base)
        base = "graphdigitizer_export_" * Dates.format(Dates.now(), "yyyy-mm-dd_HHMMSS")
    end
    dir = _preferred_downloads_dir()
    return joinpath(dir, string(base, ".", ext))
end

"""
Ensure the returned filename has the given extension.

If the filename derived from `default_filename_for_save` lacks the extension,
it will be appended.

Arguments:
- `state::AppState` : application state.
- `ext::AbstractString` : desired extension (without dot).

Returns:
- `String` : filename with ensured extension.
"""
function default_filename_from_title(state::AppState, ext::AbstractString)::String
    fname = default_filename_for_save(state, ext)
    if !endswith(lowercase(fname), "." * lowercase(ext))
        fname *= "." * lowercase(ext)
    end
    return fname
end

"""
Ensure a README.md exists in the current working directory.

If a README is missing, writes a basic help file describing the app and usage.
This is best-effort and will ignore write errors.
"""
function ensure_readme()
    p = joinpath(pwd(), "README.md")
    if isfile(p)
        return
    end
    content = """
    # GraphDigitizer

    GraphDigitizer is a small GUI tool (Julia + Gtk) for digitizing data points from raster images of graphs.

    ## Version

    Version: $(APP_VERSION)

    ## Installation

    1. Install Julia (1.6+ recommended).
    2. From the project directory run:
       ```
       julia --project=@. -e 'using Pkg; Pkg.instantiate();'
       ```
       This will install the required packages from Project.toml / Manifest.toml.

    ## Running

    Start the app:
    ```
    julia --project=@. src/graph_digitizer.jl
    ```

    ## How to use

    1. Click **Load Image** and open a PNG/JPEG image containing the plot.
    2. Click **Calibrate Clicks** then click four points on the image in this order:
       - X-left pixel (leftmost known x position)
       - X-right pixel (rightmost known x position)
       - Y-bottom pixel (bottom known y position)
       - Y-top pixel (top known y position)
    3. Enter numeric X/Y min and max values in the boxes and click **Apply Calibration**.
    4. Add points by left-clicking on the graph; right-click near a point to delete it.
    5. Use **Auto Trace Active Dataset** to extract points along a curve color-matched to the dataset color.
    6. Save your datasets as JSON or CSV using the toolbar, File menu, or keyboard shortcuts:
       - Primary+S (Ctrl+S on Windows and Linux) — Save JSON
       - Primary+Shift+S — Save CSV

    Notes:
    - When a file chooser dialog is unavailable, the app will fall back to saving files into your Downloads directory using the image Title as the filename when provided.
    - The app keeps datasets independent; switch active dataset via the dataset combo box.

    ## File format

    - JSON contains title, labels, axis ranges, flags for log scale, and datasets with point arrays.
    - CSV contains three columns: dataset, x, y.

    ## About / License

    Copyright 2025 Michael Ryan Hunsaker

    Licensed under the Apache License, Version 2.0
    """

    try
        open(p, "w") do io
            write(io, content)
        end
    catch
        # best-effort: ignore write errors
    end
end

# --------------------------
# Safe dialogs and focus helpers
# --------------------------

"""
Robustly get the currently focused widget, returning `nothing` on error.

This wraps `Gtk.get_focus` in a try/catch to avoid exceptions when called in
various platform/widget states.
"""
function _get_focus_safe(win)
    try
        return Gtk.get_focus(win)
    catch
        return nothing
    end
end

"""
Show a safe file-open dialog and return the selected filename.

This function attempts several Gtk APIs to create a file chooser. If all GUI
attempts fail it returns an empty string. Sets `state.modal_active` while the
dialog is shown to avoid re-entrancy.

Arguments:
- `state::AppState` : current application state (modal flag & status label).
- `title::AbstractString` : dialog title.
- `parent` : parent widget for the dialog (usually `state.win`).
- `patterns::Vector{String}` : list of file filter patterns (e.g. ["*.png", "*.jpg"]).

Returns:
- `String` : selected filename or empty string if cancelled/unavailable.
"""
function safe_open_dialog(state::AppState, title::AbstractString, parent, patterns::Vector{String})
    state.modal_active = true
    dlg = nothing
    try
        try
            dlg = Gtk.FileChooserDialog(title, parent, Gtk.FileChooserAction.OPEN,
                ("Cancel", Gtk.ResponseType.CANCEL, "Open", Gtk.ResponseType.ACCEPT))
        catch
            try
                dlg = Gtk.FileChooserDialog(title, parent, Gtk.FileChooserAction.OPEN)
                Gtk.Dialog.add_button(dlg, "Cancel", Gtk.ResponseType.CANCEL)
                Gtk.Dialog.add_button(dlg, "Open", Gtk.ResponseType.ACCEPT)
            catch
                dlg = try
                    Gtk.MessageDialog(parent, 0, Gtk.MessageType.INFO, Gtk.ButtonsType.OK, title)
                catch
                    try
                        d = Gtk.Dialog(title, parent, 0)
                        try
                            content = Gtk.Box(:v)
                            lbl = GtkLabel(title)
                            push!(content, lbl)
                            try
                                area = Gtk.get_content_area(d)
                                push!(area, content)
                            catch
                                try
                                    push!(d, content)
                                catch
                                end
                            end
                        catch
                        end
                        d
                    catch
                        nothing
                    end
                end
            end
        end

        try
            Gtk.set_gtk_property!(dlg, :modal, true)
        catch
        end

        try
            for pat in patterns
                f = Gtk.FileFilter()
                Gtk.FileFilter.add_pattern(f, pat)
                Gtk.FileChooser.add_filter(dlg, f)
            end
        catch
        end

        resp = try
            Gtk.Dialog.run(dlg)
        catch
            try
                Gtk.dialog_run(dlg)
            catch
                try
                    Gtk.showall(dlg)
                    Gtk.destroy(dlg)
                catch
                end
                return ""
            end
        end

        fname = ""
        try
            if resp == Gtk.ResponseType.ACCEPT || resp == Gtk.RESPONSE_ACCEPT || resp == Gtk.ResponseType(1)
                fname = try
                    Gtk.FileChooser.get_filename(dlg)
                catch
                    ""
                end
                if fname === nothing
                    fname = ""
                end
            end
        catch
            fname = ""
        end

        return fname === nothing ? "" : fname
    finally
        try
            Gtk.Widget.destroy(dlg)
        catch
            try
                Gtk.destroy(dlg)
            catch
            end
        end
        state.modal_active = false
    end
end

"""
Show a safe file-save dialog and return the selected filename.

If a native Save dialog cannot be created, this function will produce a
sensible fallback path (Downloads or temp) and update the status label.

Arguments:
- `state::AppState` : application state used for modal flag and status.
- `title::AbstractString` : dialog title.
- `parent` : parent widget for the dialog.
- `patterns::Vector{String}` : file filters to present (used to infer extension for fallback).

Returns:
- `String` : destination filename or empty string on cancel/error.
"""
function safe_save_dialog(state::AppState, title::AbstractString, parent, patterns::Vector{String})
    state.modal_active = true
    dlg = nothing
    try
        try
            dlg = Gtk.FileChooserDialog(title, parent, Gtk.FileChooserAction.SAVE,
                ("Cancel", Gtk.ResponseType.CANCEL, "Save", Gtk.ResponseType.ACCEPT))
        catch
            try
                dlg = Gtk.FileChooserDialog(title, parent, Gtk.FileChooserAction.SAVE)
                Gtk.Dialog.add_button(dlg, "Cancel", Gtk.ResponseType.CANCEL)
                Gtk.Dialog.add_button(dlg, "Save", Gtk.ResponseType.ACCEPT)
            catch
                dlg = try
                    Gtk.MessageDialog(parent, 0, Gtk.MessageType.INFO, Gtk.ButtonsType.OK, title)
                catch
                    try
                        d = Gtk.Dialog(title, parent, 0)
                        try
                            content = Gtk.Box(:v)
                            lbl = GtkLabel(title)
                            push!(content, lbl)
                            area = try
                                Gtk.get_content_area(d)
                            catch
                                nothing
                            end
                            if area !== nothing
                                push!(area, content)
                            else
                                try
                                    push!(d, content)
                                catch
                                end
                            end
                        catch
                        end
                        d
                    catch
                        nothing
                    end
                end
            end
        end

        # If we couldn't construct a dialog, provide a safe fallback filename (Downloads or temp)
        if dlg === nothing
            try
                # decide extension from patterns
                ext = "dat"
                for p in patterns
                    pp = lowercase(p)
                    if occursin(".json", pp)
                        ext = "json"
                        break
                    elseif occursin(".csv", pp)
                        ext = "csv"
                        break
                    end
                end
                fname = default_filename_for_save(state, ext)
                state.modal_active = false
                set_label(state.status_label, "No save dialog available; will save to: $fname")
                return fname
            catch e
                state.modal_active = false
                set_label(state.status_label, "Save dialog unavailable and fallback failed: $e")
                return ""
            end
        end

        try
            Gtk.set_gtk_property!(dlg, :modal, true)
        catch
        end

        try
            Gtk.FileChooser.set_do_overwrite_confirmation(dlg, true)
        catch
        end

        try
            for pat in patterns
                f = Gtk.FileFilter()
                Gtk.FileFilter.add_pattern(f, pat)
                Gtk.FileChooser.add_filter(dlg, f)
            end
        catch
        end

        resp = try
            Gtk.Dialog.run(dlg)
        catch
            try
                Gtk.dialog_run(dlg)
            catch
                try
                    Gtk.showall(dlg)
                    Gtk.destroy(dlg)
                catch
                end
                return ""
            end
        end

        fname = ""
        try
            if resp == Gtk.ResponseType.ACCEPT || resp == Gtk.RESPONSE_ACCEPT || resp == Gtk.ResponseType(1)
                fname = try
                    Gtk.FileChooser.get_filename(dlg)
                catch
                    ""
                end
                if fname === nothing
                    fname = ""
                end
            end
        catch
            fname = ""
        end

        return fname === nothing ? "" : fname
    finally
        try
            Gtk.Widget.destroy(dlg)
        catch
            try
                Gtk.destroy(dlg)
            catch
            end
        end
        state.modal_active = false
    end
end

# --------------------------
# Top-level helpers for menu items and accelerators
# --------------------------

"""
Construct a menu item widget with an accelerator label aligned on the right.

Attempts to use `Gtk.AccelLabel` when available; falls back to a plain label.

Arguments:
- `label_text::AbstractString` : visible menu text.
- `accel_text::AbstractString` : textual accelerator hint (e.g. "Ctrl+S").

Returns:
- `Gtk.MenuItem` : configured menu item widget.
"""
function menu_item_with_accel(label_text::AbstractString, accel_text::AbstractString="")
    mi = try
        Gtk.MenuItem()
    catch
        try
            Gtk.MenuItem(label_text)
        catch
            Gtk.MenuItem()
        end
    end
    try
        # Horizontal box with spacing to visually separate label and accel
        box = Gtk.Box(:h, 12)
        lbl = Gtk.Label(label_text)
        try
            Gtk.set_gtk_property!(lbl, :hexpand, true)
        catch
        end
        a_lbl = try
            Gtk.AccelLabel(accel_text)
        catch
            Gtk.Label(accel_text)
        end
        try
            Gtk.set_gtk_property!(a_lbl, :halign, GtkAlign.END)
        catch
        end
        try
            Gtk.set_gtk_property!(box, :hexpand, true)
        catch
        end
        push!(box, lbl)
        push!(box, a_lbl)
        push!(mi, box)
    catch
        try
            mi = Gtk.MenuItem(label_text)
        catch
        end
    end
    return mi
end

"""
Register an accelerator for a widget against an `AccelGroup` using a key string.

Attempts several Gtk APIs to add the accelerator in a robust manner.

Arguments:
- `widget` : widget to attach accelerator to.
- `ag` : accelerator group (may be `nothing`).
- `keystr::AbstractString` : accelerator string (e.g. "<Ctrl>S" or "<Primary>S").
- `signal::AbstractString` : signal name to trigger (defaults to "activate").
"""
function _add_accel(widget, ag, keystr::AbstractString, signal::AbstractString="activate")
    if ag === nothing
        return
    end
    key = 0
    mods = 0
    try
        key, mods = Gtk.accelerator_parse(keystr)
    catch
        key = Int(keystr[1])
        mods = 0
    end
    try
        Gtk.Widget.add_accelerator(widget, signal, ag, key, mods, Gtk.AccelFlags.VISIBLE)
    catch
        try
            Gtk.add_accelerator(widget, signal, ag, key, mods, Gtk.AccelFlags.VISIBLE)
        catch
            try
                Gtk.Widget.add_accelerator(widget, signal, ag, key, mods, Gtk.AccelFlags(1))
            catch
            end
        end
    end
end

# --------------------------
# Drawing / Auto-trace / Transforms
# --------------------------

"""
Parse a color string and return an (r,g,b) tuple of Float64 components.

This is a tiny adapter used by drawing code that expects a 3-tuple instead of
an `RGB` object.

Arguments:
- `colname::String` : color string (e.g. hex).

Returns:
- `(Float64,Float64,Float64)` : RGB components in [0,1].
"""
function parse_color(colname::String)
    try
        rgb = hex_to_rgb(colname)
        return (rgb.r, rgb.g, rgb.b)
    catch
        return (0.0, 0.0, 0.0)
    end
end

"""
Transform a data-space point (dx, dy) into canvas pixel coordinates.

Uses the calibration pixel positions stored in `state.px_xmin`, `state.px_xmax`,
`state.px_ymin`, and `state.px_ymax` as well as numeric ranges and log flags.

Arguments:
- `state::AppState` : application state including calibration.
- `dx::Float64` : data x-value.
- `dy::Float64` : data y-value.

Returns:
- `(Float64,Float64)` : canvas coordinates (px, py). Returns (0,0) if not calibrated.
"""
function data_to_canvas(state::AppState, dx::Float64, dy::Float64)
    if state.px_xmin === nothing || state.px_xmax === nothing || state.px_ymin === nothing || state.px_ymax === nothing
        return (0.0, 0.0)
    end
    xpx1 = state.px_xmin[1]
    xpx2 = state.px_xmax[1]
    if state.x_log
        if dx <= 0 || state.x_min <= 0
            t = 0.0
        else
            t = (log10(dx) - log10(state.x_min)) / (log10(state.x_max) - log10(state.x_min))
        end
    else
        t = (dx - state.x_min) / (state.x_max - state.x_min)
    end
    px = xpx1 + t * (xpx2 - xpx1)

    ypx1 = state.px_ymin[2]
    ypx2 = state.px_ymax[2]
    if state.y_log
        if dy <= 0 || state.y_min <= 0
            u = 0.0
        else
            u = (log10(dy) - log10(state.y_min)) / (log10(state.y_max) - log10(state.y_min))
        end
    else
        u = (dy - state.y_min) / (state.y_max - state.y_min)
    end
    py = ypx1 + u * (ypx2 - ypx1)
    return px, py
end

"""
Transform canvas coordinates to data-space (inverse of `data_to_canvas`).

Uses calibration pixel positions and numeric ranges; respects logarithmic axes.

Arguments:
- `state::AppState` : application state including calibration.
- `cx::Float64` : canvas x coordinate.
- `cy::Float64` : canvas y coordinate.

Returns:
- `(Float64,Float64)` : (x, y) in data coordinates. Returns (0,0) if not calibrated.
"""
function canvas_to_data(state::AppState, cx::Float64, cy::Float64)
    if state.px_xmin === nothing || state.px_xmax === nothing || state.px_ymin === nothing || state.px_ymax === nothing
        return (0.0, 0.0)
    end
    xpx1 = state.px_xmin[1]
    xpx2 = state.px_xmax[1]
    denomx = (xpx2 - xpx1)
    if denomx == 0.0
        t = 0.0
    else
        t = (cx - xpx1) / denomx
    end
    if state.x_log
        val = 10^(log10(state.x_min) + t * (log10(state.x_max) - log10(state.x_min)))
    else
        val = state.x_min + t * (state.x_max - state.x_min)
    end
    ypx1 = state.px_ymin[2]
    ypx2 = state.px_ymax[2]
    denomy = (ypx2 - ypx1)
    if denomy == 0.0
        u = 0.0
    else
        u = (cy - ypx1) / denomy
    end
    if state.y_log
        valy = 10^(log10(state.y_min) + u * (log10(state.y_max) - log10(state.y_min)))
    else
        valy = state.y_min + u * (state.y_max - state.y_min)
    end
    return val, valy
end

"""
Perform an auto-trace scan across the calibrated X range attempting to find
the best color match per column for `target_rgb`.

This scans along pixel columns between the calibrated X pixel positions and
for each column finds the pixel row with minimal color distance to the target.
The found canvas coordinates are converted to data coordinates and returned.

Arguments:
- `state::AppState` : application state with image and calibration.
- `target_rgb::RGB{Float64}` : RGB color to match (components in [0,1]).

Returns:
- `Vector{Tuple{Float64,Float64}}` : sampled data points (x,y).

Example:
- To auto-trace the currently active dataset's color:
    ds = state.datasets[state.active_dataset]
    sampled = auto_trace_scan(state, hex_to_rgb(ds.color))
    # `sampled` will contain a Vector{Tuple{Float64,Float64}} of data-space points
"""
function auto_trace_scan(state::AppState, target_rgb::RGB{Float64})
    if state.px_xmin === nothing || state.px_xmax === nothing || state.px_ymin === nothing || state.px_ymax === nothing
        return Tuple{Float64,Float64}[]
    end

    x1 = state.px_xmin[1]
    x2 = state.px_xmax[1]
    ncols = Int(round(abs(x2 - x1)))
    sampled = Tuple{Float64,Float64}[]
    img = state.image
    if img === nothing
        return sampled
    end

    for i in 0:max(0, ncols - 1)
        cx = x1 + (i / (max(1, ncols - 1))) * (x2 - x1)
        ix = Int(round((cx - state.offset_x) / state.display_scale))
        if ix < 1 || ix > state.img_w
            continue
        end
        dists = Vector{Float64}(undef, state.img_h)
        for j in 1:state.img_h
            pixel = try
                img[j, ix]
            catch
                nothing
            end
            if pixel === nothing
                dists[j] = Inf
                continue
            end
            pr = float(red(pixel))
            pg = float(green(pixel))
            pb = float(blue(pixel))
            dists[j] = sqrt((pr - target_rgb.r)^2 + (pg - target_rgb.g)^2 + (pb - target_rgb.b)^2)
        end
        if all(isinf, dists)
            continue
        end
        besty = argmin(dists)
        canvas_x = cx
        canvas_y = state.offset_y + state.display_scale * (besty - 1)
        dx, dy = canvas_to_data(state, canvas_x, canvas_y)
        push!(sampled, (dx, dy))
    end
    return sampled
end

"""
Draw the main canvas including image, calibration markers, calibration click overlays,
and dataset points.

Intended to be called from a canvas draw callback. The function expects the
Cairo context `cr` and the `AppState` describing current application state.
"""
function draw_canvas(state::AppState, cr)
    Cairo.set_source_rgb(cr, 1, 1, 1)
    Cairo.paint(cr)
    if state.image === nothing || state.img_surface === nothing
        Cairo.set_source_rgb(cr, 0, 0, 0)
        # Try to select a standard sans font and set a larger font size for the placeholder text.
        try
            Cairo.select_font_face(cr, "Sans", Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_NORMAL)
        catch
        end
        try
            Cairo.set_font_size(cr, 16.0)
        catch
        end
        # Move down a bit to accommodate the larger font size
        Cairo.move_to(cr, 10, 30)
        Cairo.show_text(cr, "Load an image to begin.")
        return
    end

    cw = Gtk.width(state.canvas)
    ch = Gtk.height(state.canvas)
    s = compute_display_scale(state)
    state.display_scale = s
    tx = (cw - state.img_w * s) / 2.0
    ty = (ch - state.img_h * s) / 2.0
    state.offset_x, state.offset_y = tx, ty

    Cairo.save(cr)
    Cairo.translate(cr, tx, ty)
    Cairo.scale(cr, s, s)
    Cairo.set_source_surface(cr, state.img_surface, 0, 0)
    Cairo.paint(cr)
    Cairo.restore(cr)

    for p in (state.px_xmin, state.px_xmax, state.px_ymin, state.px_ymax)
        if p !== nothing
            Cairo.set_source_rgb(cr, 0, 0, 0)
            Cairo.arc(cr, p[1], p[2], 5.0, 0, 2pi)
            Cairo.fill(cr)
        end
    end

    if state.calibration_mode && !isempty(state.calib_clicks)
        for (i, c) in enumerate(state.calib_clicks)
            Cairo.set_source_rgb(cr, 0.0, 0.0, 0.0)
            Cairo.arc(cr, c[1], c[2], 6.0, 0, 2pi)
            Cairo.fill(cr)
            Cairo.move_to(cr, c[1] + 8, c[2] - 8)
            Cairo.show_text(cr, string(i))
        end
    end

    for (di, ds) in enumerate(state.datasets)
        Cairo.set_source_rgb(cr, ds.color_rgb.r, ds.color_rgb.g, ds.color_rgb.b)
        for (pi, p) in enumerate(ds.points)
            cx, cy = data_to_canvas(state, p[1], p[2])
            Cairo.arc(cr, cx, cy, 5.0, 0, 2pi)
            Cairo.fill(cr)
            if state.drag_idx !== nothing && state.drag_idx == (di, pi)
                Cairo.set_source_rgb(cr, 0, 0, 0)
                Cairo.arc(cr, cx, cy, 8.0, 0, 2pi)
                Cairo.stroke(cr)
            end
        end
    end

    # Precision zoom overlay: when `zoom_mode` is enabled draw a circular
    # magnified view centered at `zoom_center`. The overlay renders a scaled
    # region of the underlying image surface inside a filled circle so the
    # user can place points with greater pixel-level accuracy.
    if state.zoom_mode && state.zoom_center !== nothing
        zx, zy = state.zoom_center
        Cairo.save(cr)
        # background circle for contrast
        Cairo.set_source_rgb(cr, 1.0, 1.0, 1.0)
        Cairo.arc(cr, zx, zy, state.zoom_radius_px, 0, 2pi)
        Cairo.fill(cr)

        sx = state.display_scale
        if state.img_surface !== nothing && sx > 0
            try
                # map canvas center to image pixel coordinates
                img_cx = (zx - state.offset_x) / sx
                img_cy = (zy - state.offset_y) / sx
                # compute source half-width in image pixels (account for zoom level)
                rpx = max(1.0, state.zoom_radius_px / (sx * state.zoom_level))
                src_x = clamp(img_cx - rpx, 0.0, max(0.0, state.img_w - 1.0))
                src_y = clamp(img_cy - rpx, 0.0, max(0.0, state.img_h - 1.0))

                # Destination square (in device pixels) where we'll paint the scaled region.
                dst_size = 2 * state.zoom_radius_px

                # Draw the scaled image region into the destination square.
                Cairo.save(cr)
                Cairo.translate(cr, zx - state.zoom_radius_px, zy - state.zoom_radius_px)
                # Note: scale by (zoom_level * display_scale) to convert image pixels
                # into canvas device pixels with magnification. We wrap in try/catch
                # to remain robust across Cairo versions.
                Cairo.scale(cr, state.zoom_level * sx, state.zoom_level * sx)
                Cairo.set_source_surface(cr, state.img_surface, -src_x, -src_y)
                Cairo.rectangle(cr, 0, 0, dst_size / (state.zoom_level * sx), dst_size / (state.zoom_level * sx))
                try
                    Cairo.paint(cr)
                catch
                    # best-effort: if paint/filter not available, continue
                end
                Cairo.restore(cr)

                # Optionally draw a subtle grid to make pixel boundaries clearer (best-effort).
                try
                    # compute an approximate pixel grid step in canvas space and draw if reasonable
                    step = max(1.0, 1.0 * state.zoom_level)
                    Cairo.set_source_rgba(cr, 0.0, 0.0, 0.0, 0.15)
                    i = -state.zoom_radius_px
                    while i <= state.zoom_radius_px
                        Cairo.move_to(cr, zx + i, zy - state.zoom_radius_px)
                        Cairo.line_to(cr, zx + i, zy + state.zoom_radius_px)
                        i += step
                    end
                    i = -state.zoom_radius_px
                    while i <= state.zoom_radius_px
                        Cairo.move_to(cr, zx - state.zoom_radius_px, zy + i)
                        Cairo.line_to(cr, zx + state.zoom_radius_px, zy + i)
                        i += step
                    end
                    Cairo.stroke(cr)
                catch
                    # ignore grid-draw errors
                end
            catch
                # ignore any errors while computing zoom region
            end
        end

        # draw circle outline
        Cairo.set_source_rgb(cr, 0.0, 0.0, 0.0)
        Cairo.arc(cr, zx, zy, state.zoom_radius_px, 0, 2pi)
        Cairo.stroke(cr)
        Cairo.restore(cr)
    end
end

# --------------------------
# Helper: find nearest point on canvas
# --------------------------
# Returns a tuple (dataset_index, point_index) of the nearest point within
# `maxdist` canvas pixels from (x, y), or `nothing` if no such point found.
function find_nearest_point(state::AppState, x::Float64, y::Float64, maxdist::Float64)
    best = nothing
    bestd = maxdist
    for (di, ds) in enumerate(state.datasets)
        for (pi, p) in enumerate(ds.points)
            # convert data point to canvas coordinates
            cx, cy = data_to_canvas(state, p[1], p[2])
            d = sqrt((cx - x)^2 + (cy - y)^2)
            if d <= bestd
                bestd = d
                best = (di, pi)
            end
        end
    end
    return best
end

# --------------------------
# I/O helpers
# --------------------------

"""
Set the text of a `GtkLabel` in a safe best-effort manner.

Wraps `Gtk.set_gtk_property!` and ignores errors that might occur on some
platforms or with certain widget implementations.
"""
function set_label(lbl::GtkLabel, txt::AbstractString)
    try
        Gtk.set_gtk_property!(lbl, :label, txt)
    catch
        # best-effort: ignore if property setting not available
    end
end

"""
Export all datasets to a CSV file.

CSV contains three columns: `dataset`, `x`, `y`. Uses `CSV.write` and will
throw on IO errors.

Arguments:
- `state::AppState` : application state containing datasets.
- `fname::String` : destination filename (should end in .csv).
"""
function export_csv(state::AppState, fname::String)
    rows = DataFrame(dataset=String[], x=Float64[], y=Float64[])
    for ds in state.datasets
        for p in ds.points
            push!(rows, (ds.name, p[1], p[2]))
        end
    end
    CSV.write(fname, rows)
end

"""
Export the full application data to a JSON file.

JSON contains title, axis labels, numeric ranges, log flags, and each dataset
(including color and points). Uses `JSON.print` to write the file.

Arguments:
- `state::AppState` : application state to serialize.
- `fname::String` : destination filename (should end in .json).
"""
function export_json(state::AppState, fname::String)
    out = Dict{String,Any}()
    try
        out["title"] = Gtk.get_gtk_property(state.title_entry, :text, String)
    catch
        out["title"] = ""
    end
    try
        out["xlabel"] = Gtk.get_gtk_property(state.xlabel_entry, :text, String)
    catch
        out["xlabel"] = ""
    end
    try
        out["ylabel"] = Gtk.get_gtk_property(state.ylabel_entry, :text, String)
    catch
        out["ylabel"] = ""
    end
    out["x_min"] = state.x_min
    out["x_max"] = state.x_max
    out["y_min"] = state.y_min
    out["y_max"] = state.y_max
    out["x_log"] = state.x_log
    out["y_log"] = state.y_log
    out["datasets"] = []
    for ds in state.datasets
        push!(out["datasets"], Dict("name" => ds.name, "color" => ds.color, "points" => [[p[1], p[2]] for p in ds.points]))
    end
    open(fname, "w") do io
        JSON.print(io, out)
    end
end

# --------------------------
# Exit / confirmation helpers
# --------------------------

"""
Prompt the user to save before exiting.

Shows a dialog asking whether to `Save`, `Discard`, or `Cancel`. If dialogs
cannot be created a fallback save using `safe_save_dialog` is attempted.
Returns true if it is OK to exit (either saved or discard chosen), false if
the user cancelled.

Arguments:
- `state::AppState` : application state (used to present dialogs and access state).

Returns:
- `Bool` : `true` if the application may exit, `false` to abort closing.
"""
function confirm_exit_and_maybe_save(state::AppState)::Bool
    dlg = try
        Gtk.Dialog("Save current datasets before exiting?", state.win)
    catch
        try
            Gtk.Dialog("Save current datasets before exiting?", state.win, 0)
        catch
            nothing
        end
    end

    # If dialog cannot be created, route through the robust save helper which itself
    # will show a file chooser when possible and otherwise provide a sensible fallback.
    if dlg === nothing
        try
            fname = safe_save_dialog(state, "Save JSON File", state.win, ["*.json"])
            if fname != ""
                if !endswith(lowercase(fname), ".json")
                    fname *= ".json"
                end
                try
                    export_json(state, fname)
                    set_label(state.status_label, "No dialog available; saved JSON to: $fname")
                catch e
                    try
                        set_label(state.status_label, "Save failed during fallback: $e")
                    catch
                    end
                end
            else
                # The save helper returned no filename (user cancelled or helper failed).
                # Allow the exit to continue but notify the user via the status label.
                try
                    set_label(state.status_label, "No dialog available and save was cancelled.")
                catch
                end
            end
        catch e
            try
                set_label(state.status_label, "No dialog available and fallback save failed: $e")
            catch
            end
        end
        # Allow the application to close (Exit / Ctrl+Q should still close the app).
        return true
    end

    try
        content = Gtk.Box(:v)
        lbl = GtkLabel("Save current datasets before exiting?")
        push!(content, lbl)
        try
            area = Gtk.get_content_area(dlg)
            push!(area, content)
        catch
            try
                push!(dlg, content)
            catch
            end
        end
    catch
    end

    try
        Gtk.Dialog.add_button(dlg, "Save", Gtk.ResponseType.YES)
        Gtk.Dialog.add_button(dlg, "Discard", Gtk.ResponseType.NO)
        Gtk.Dialog.add_button(dlg, "Cancel", Gtk.ResponseType.CANCEL)
    catch
        try
            Gtk.add_button(dlg, "Save", Gtk.ResponseType.YES)
            Gtk.add_button(dlg, "Discard", Gtk.ResponseType.NO)
            Gtk.add_button(dlg, "Cancel", Gtk.ResponseType.CANCEL)
        catch
            try
                Gtk.Dialog.add_button(dlg, "OK", Gtk.ResponseType.OK)
                Gtk.Dialog.add_button(dlg, "Cancel", Gtk.ResponseType.CANCEL)
            catch
            end
        end
    end

    resp = try
        Gtk.Dialog.run(dlg)
    catch
        try
            Gtk.dialog_run(dlg)
        catch
            try
                Gtk.showall(dlg)
                Gtk.destroy(dlg)
            catch
            end
            return false
        end
    end

    if dlg !== nothing
        try
            Gtk.Widget.destroy(dlg)
        catch
            try
                Gtk.destroy(dlg)
            catch
            end
        end
    end

    if resp == Gtk.ResponseType.YES || (isdefined(Gtk, :RESPONSE_YES) && resp == Gtk.RESPONSE_YES) || resp == Gtk.ResponseType(6)
        fname = safe_save_dialog(state, "Save JSON File", state.win, ["*.json"])
        if fname == ""
            return false
        end
        if !endswith(lowercase(fname), ".json")
            fname *= ".json"
        end
        try
            export_json(state, fname)
        catch e
            set_label(state.status_label, "Failed to save JSON: $e")
            return false
        end
        return true
    elseif resp == Gtk.ResponseType.NO || (isdefined(Gtk, :RESPONSE_NO) && resp == Gtk.RESPONSE_NO) || resp == Gtk.ResponseType(5)
        return true
    else
        return false
    end
end

"""
Forcefully quit the application by attempting several shutdown paths.

This helper clears the modal flag, attempts to call `Gtk.main_quit`, destroys
the main window widget, and falls back to other available destruction APIs.
"""
function force_quit(state::AppState)
    # Clear modal flag so helpers don't block
    try
        state.modal_active = false
    catch
    end

    # Try to quit the GTK main loop cleanly
    try
        Gtk.main_quit()
        return
    catch
    end

    # Try destroying the main window widget
    try
        Gtk.Widget.destroy(state.win)
        return
    catch
    end

    # Fallback: try Gtk.destroy if available
    try
        Gtk.destroy(state.win)
        return
    catch
    end

    # If all else fails, raise a warning (best-effort)
    @warn "force_quit: failed to cleanly quit Gtk; application may remain running"
end

# --------------------------
# Main App creation
# --------------------------

"""
Construct and initialize the full Graph Digitizer application UI.

This function creates the main window, widgets, signals, and returns the
`AppState` object which can be used by the caller for further manipulation
or testing. The returned state is fully wired with callback handlers for
loading images, calibration, point editing, auto-trace, saving, and exit.

Returns:
- `AppState` : initialized application state (window is created but not shown).
"""
function create_app()
    win = GtkWindow("Graph Digitizer – Julia", 1100, 820)
    mainbox = GtkBox(:v)

    try
        Gtk.set_gtk_property!(mainbox, :margin_start, 12)
        Gtk.set_gtk_property!(mainbox, :margin_end, 12)
        Gtk.set_gtk_property!(mainbox, :margin_top, 12)
        Gtk.set_gtk_property!(mainbox, :margin_bottom, 12)
    catch
        try
            Gtk.set_gtk_property!(mainbox, :margin, 12)
        catch
            try
                Gtk.set_gtk_property!(mainbox, :spacing, 12)
            catch
            end
        end
    end

    # Add a style class to the mainbox so CSS rules can target it explicitly
    try
        Gtk.StyleContext.add_class(Gtk.get_style_context(mainbox), "app-main")
    catch
    end

    # Apply CSS font-size where available (force 16pt globally and add classes for specific widgets)
    try
        provider = try
            Gtk.CssProvider()
        catch
            # fallback for older Gtk.jl builds
            try
                Gtk.css_provider_new()
            catch
                nothing
            end
        end

        css_data = "* { font-size: 16pt; }\n.app-main { font-size: 16pt; }\n.app-status { font-size: 16pt; }"

        try
            Gtk.CssProvider.load_from_data(provider, css_data)
        catch
            try
                Gtk.css_provider_load_from_data(provider, css_data)
            catch
            end
        end

        try
            scr = Gdk.Screen.get_default()
            Gtk.StyleContext.add_provider_for_screen(scr, provider, Gtk.STYLE_PROVIDER_PRIORITY_USER)
        catch
            try
                scr = Gdk.screen_get_default()
                Gtk.StyleContext.add_provider_for_screen(scr, provider, Gtk.STYLE_PROVIDER_PRIORITY_USER)
            catch
            end
        end
    catch
    end

    push!(win, mainbox)

    menubar = try
        Gtk.MenuBar()
    catch
        nothing
    end

    # placeholders that will be defined if the menubar is constructed
    save_json_mi = nothing
    save_csv_mi = nothing
    exit_mi = nothing
    help_mi = nothing
    howto_mi = nothing
    about_mi = nothing

    if menubar !== nothing
        file_mi = try
            Gtk.MenuItem("_File")
        catch
            Gtk.MenuItem()
        end
        file_menu = try
            Gtk.Menu()
        catch
            nothing
        end

        if file_menu !== nothing
            primary_name = Sys.isapple() ? "Cmd" : "Ctrl"
            save_json_mi = menu_item_with_accel("Save JSON", string(" ", primary_name, "+S"))
            save_csv_mi = menu_item_with_accel("Save CSV", string(" ", primary_name, "+Shift+S"))
            exit_mi = menu_item_with_accel("Exit", string(" ", primary_name, "+Q"))

            try
                push!(file_menu, save_json_mi)
                push!(file_menu, save_csv_mi)
                push!(file_menu, Gtk.SeparatorMenuItem())
                push!(file_menu, exit_mi)
            catch
            end
        end

        try
            if file_menu !== nothing
                Gtk.set_gtk_property!(file_mi, :submenu, file_menu)
            end
        catch
        end

        try
            push!(menubar, file_mi)
        catch
        end

        # Help menu
        help_mi = try
            Gtk.MenuItem("_Help")
        catch
            Gtk.MenuItem()
        end
        help_menu = try
            Gtk.Menu()
        catch
            nothing
        end

        if help_menu !== nothing
            howto_mi = menu_item_with_accel("How to use", "")
            about_mi = menu_item_with_accel("About", "")

            try
                push!(help_menu, howto_mi)
                push!(help_menu, about_mi)
            catch
            end

            try
                Gtk.signal_connect(howto_mi, "activate") do _
                    # Ensure README exists (creates a default if missing)
                    try
                        ensure_readme()
                    catch
                    end

                    readme_path = joinpath(pwd(), "README.md")
                    opened = false

                    # Try to open README.md in the system default viewer first.
                    # This provides the best user experience on each platform.
                    try
                        if Sys.iswindows()
                            # Use cmd start (empty title argument required)
                            run(`cmd /c start "" "$(readme_path)"`)
                        elseif Sys.isapple()
                            run(`open "$(readme_path)"`)
                        else
                            # Linux / other Unix-like platforms
                            run(`xdg-open "$(readme_path)"`)
                        end
                        opened = true
                    catch
                        opened = false
                    end

                    # If external viewer opened, nothing more to do here.
                    if opened
                        # best-effort: do not block the UI further
                    else
                        # Fallback: display README content in an internal, scrollable dialog
                        content = try
                            read(readme_path, String)
                        catch
                            "How-to information is not available."
                        end

                        dlg = try
                            Gtk.Dialog("How to use", win)
                        catch
                            try
                                Gtk.MessageDialog(win, 0, Gtk.MessageType.INFO, Gtk.ButtonsType.OK, "How to use")
                            catch
                                nothing
                            end
                        end

                        if dlg !== nothing
                            try
                                area = Gtk.get_content_area(dlg)
                                tv = Gtk.TextView()
                                buf = Gtk.TextBuffer()
                                Gtk.TextBuffer.set_text(buf, content)
                                Gtk.set_gtk_property!(tv, :buffer, buf)
                                Gtk.set_gtk_property!(tv, :editable, false)
                                scr = try
                                    Gtk.ScrolledWindow()
                                catch
                                    nothing
                                end
                                if scr !== nothing
                                    try
                                        push!(scr, tv)
                                        push!(area, scr)
                                    catch
                                        try
                                            push!(area, tv)
                                        catch
                                        end
                                    end
                                else
                                    try
                                        push!(area, tv)
                                    catch
                                    end
                                end
                            catch
                            end
                            try
                                Gtk.Dialog.run(dlg)
                                Gtk.Widget.destroy(dlg)
                            catch
                            end
                        end
                    end
                end
            catch
            end

            try
                Gtk.signal_connect(about_mi, "activate") do _
                    # Guaranteed-visible About window (no reliance on AboutDialog/MessageDialog)
                    try
                        about_text = "Graph Digitizer\n\n(c) 2025 Michael Ryan Hunsaker, M.Ed., Ph.D.\n\nhttps://github.com/mrhunsaker/Graph_Digitizer\n\n"
                        wnd = nothing
                        try
                            wnd = GtkWindow("About - Graph Digitizer", 480, 200)
                        catch
                            wnd = nothing
                        end
                        if wnd !== nothing
                            box = Gtk.Box(:v)
                            try
                                Gtk.set_gtk_property!(box, :margin, 8)
                            catch
                            end
                            lbl = GtkLabel(about_text)
                            try
                                Gtk.set_gtk_property!(lbl, :wrap, true)
                                Gtk.set_gtk_property!(lbl, :justify, Gtk.Justification.LEFT)
                            catch
                            end
                            close_btn = GtkButton("Close")
                            try
                                push!(box, lbl)
                                push!(box, close_btn)
                                push!(wnd, box)
                            catch
                            end
                            try
                                Gtk.signal_connect(close_btn, "clicked") do _
                                    try
                                        Gtk.Widget.destroy(wnd)
                                    catch
                                        try
                                            Gtk.destroy(wnd)
                                        catch
                                        end
                                    end
                                end
                            catch
                            end
                            try
                                Gtk.showall(wnd)
                            catch
                                try
                                    Gtk.show(wnd)
                                catch
                                end
                            end
                            return
                        else
                            try
                                set_label(state.status_label, "About: https://github.com/mrhunsaker/Graph_Digitizer")
                            catch
                            end
                            try
                                println("About: https://github.com/mrhunsaker/Graph_Digitizer")
                            catch
                            end
                        end
                    catch e
                        try
                            set_label(state.status_label, "About handler error: $(e)")
                        catch
                        end
                        try
                            println("About handler error: ", e)
                        catch
                        end
                    end
                end
            catch
            end

            try
                Gtk.set_gtk_property!(help_mi, :submenu, help_menu)
            catch
            end
            try
                push!(menubar, help_mi)
            catch
            end
        end

        try
            push!(mainbox, menubar)
        catch
        end
    end

    # Toolbar
    toolbar = GtkBox(:h)
    Gtk.set_gtk_property!(toolbar, :spacing, 10)
    push!(mainbox, toolbar)
    load_btn = GtkButton("Load Image")
    push!(toolbar, load_btn)
    calib_btn = GtkButton("Calibrate Clicks")
    push!(toolbar, calib_btn)
    apply_calib_btn = GtkButton("Apply Calibration")
    push!(toolbar, apply_calib_btn)
    auto_trace_btn = GtkButton("Auto Trace Active Dataset")
    push!(toolbar, auto_trace_btn)
    save_csv_btn = GtkButton("Export CSV")
    push!(toolbar, save_csv_btn)
    save_json_btn = GtkButton("Export JSON")
    push!(toolbar, save_json_btn)
    exit_btn = GtkButton("Exit")
    push!(toolbar, exit_btn)

    # Accel group
    ag = nothing
    try
        ag = Gtk.AccelGroup()
    catch
        try
            ag = Gtk.accel_group_new()
        catch
            ag = nothing
        end
    end
    if ag !== nothing
        try
            try
                Gtk.window_add_accel_group(win, ag)
            catch
                try
                    Gtk.add_accel_group(win, ag)
                catch
                    try
                        Gtk.Window.add_accel_group(win, ag)
                    catch
                    end
                end
            end
        catch
        end

        try
            if Sys.isapple()
                _add_accel(save_json_mi, "<Primary>S")
                _add_accel(save_csv_mi, "<Primary><Shift>S")
                _add_accel(exit_mi, "<Primary>Q")
                _add_accel(save_json_btn, "<Primary>S", "clicked")
                _add_accel(save_csv_btn, "<Primary><Shift>S", "clicked")
                _add_accel(exit_btn, "<Primary>Q", "clicked")
            else
                _add_accel(save_json_mi, "<Ctrl>S")
                _add_accel(save_csv_mi, "<Ctrl><Shift>S")
                _add_accel(exit_mi, "<Ctrl>Q")
                _add_accel(save_json_btn, "<Ctrl>S", "clicked")
                _add_accel(save_csv_btn, "<Ctrl><Shift>S", "clicked")
                _add_accel(exit_btn, "<Ctrl>Q", "clicked")
            end
        catch
        end
    end

    # Unified form grid (Title / labels / axis ranges)
    form_grid = GtkGrid()
    push!(mainbox, form_grid)
    Gtk.set_gtk_property!(form_grid, :row_spacing, 8)
    Gtk.set_gtk_property!(form_grid, :column_spacing, 10)
    try
        Gtk.set_gtk_property!(form_grid, :row_homogeneous, false)
    catch
    end
    try
        Gtk.set_gtk_property!(form_grid, :column_homogeneous, false)
    catch
    end

    # Fixed label width so left edges of all labels align
    label_width = 140

    # helper functions
    function _style_label(lbl)
        try
            Gtk.set_gtk_property!(lbl, :halign, GtkAlign.START)
        catch
        end
        try
            Gtk.set_gtk_property!(lbl, :valign, GtkAlign.CENTER)
        catch
        end
        try
            Gtk.set_gtk_property!(lbl, :margin_end, 6)
        catch
        end
        try
            Gtk.set_gtk_property!(lbl, :width_request, label_width)
        catch
        end
    end
    function _style_entry(ent)
        try
            Gtk.set_gtk_property!(ent, :hexpand, true)
        catch
        end
        try
            Gtk.set_gtk_property!(ent, :halign, GtkAlign.FILL)
        catch
        end
        try
            Gtk.set_gtk_property!(ent, :valign, GtkAlign.CENTER)
        catch
        end
        try
            Gtk.set_gtk_property!(ent, :margin_top, 2)
            Gtk.set_gtk_property!(ent, :margin_bottom, 2)
        catch
        end
    end

    # create widgets
    title_label = GtkLabel("Title:")
    title_entry = GtkEntry()
    _style_label(title_label)
    _style_entry(title_entry)

    xlabel_label = GtkLabel("X label:")
    xlabel_entry = GtkEntry()
    _style_label(xlabel_label)
    _style_entry(xlabel_entry)

    ylabel_label = GtkLabel("Y label:")
    ylabel_entry = GtkEntry()
    _style_label(ylabel_label)
    _style_entry(ylabel_entry)

    lxmin = GtkLabel("X min:")
    x_min_entry = GtkEntry()
    _style_label(lxmin)
    _style_entry(x_min_entry)

    lxmax = GtkLabel("X max:")
    x_max_entry = GtkEntry()
    _style_label(lxmax)
    _style_entry(x_max_entry)

    lymin = GtkLabel("Y min:")
    y_min_entry = GtkEntry()
    _style_label(lymin)
    _style_entry(y_min_entry)

    lymax = GtkLabel("Y max:")
    y_max_entry = GtkEntry()
    _style_label(lymax)
    _style_entry(y_max_entry)

    # place rows (labels in column 1, entries in column 2)
    form_grid[1, 1] = title_label
    form_grid[2, 1] = title_entry
    form_grid[1, 2] = xlabel_label
    form_grid[2, 2] = xlabel_entry
    form_grid[1, 3] = ylabel_label
    form_grid[2, 3] = ylabel_entry
    form_grid[1, 4] = lxmin
    form_grid[2, 4] = x_min_entry
    form_grid[1, 5] = lxmax
    form_grid[2, 5] = x_max_entry
    form_grid[1, 6] = lymin
    form_grid[2, 6] = y_min_entry
    form_grid[1, 7] = lymax
    form_grid[2, 7] = y_max_entry
    # Backwards-compatible aliases for legacy label variable names.
    # The unified `form_grid` above created labels named `lxmin`, `lxmax`, `lymin`, `lymax`.
    # Define short aliases so older code (and any downstream references) still work.
    try
        x_min_label = lxmin
        x_max_label = lxmax
        y_min_label = lymin
        y_max_label = lymax
    catch
    end

    # Note: the corresponding entry widgets (x_min_entry, x_max_entry, y_min_entry, y_max_entry)
    # were already created and placed into `form_grid` above. Do not redeclare them here.
    # Create the X/Y log checkboxes (these were referenced earlier; define them here and attach to `log_box`).
    xlog_chk = GtkCheckButton("X log")
    try
        Gtk.set_gtk_property!(xlog_chk, :active, false)
        Gtk.set_gtk_property!(xlog_chk, :margin_end, 6)
    catch
    end
    ylog_chk = GtkCheckButton("Y log")
    try
        Gtk.set_gtk_property!(ylog_chk, :active, false)
        Gtk.set_gtk_property!(ylog_chk, :margin_end, 6)
    catch
    end

    # Place the X/Y log checkboxes below the axis entry grid but above the dataset row.
    log_box = GtkBox(:h)
    Gtk.set_gtk_property!(log_box, :spacing, 12)
    try
        Gtk.set_gtk_property!(log_box, :margin_top, 8)
        Gtk.set_gtk_property!(log_box, :margin_bottom, 4)
    catch
    end
    try
        push!(log_box, xlog_chk)
        push!(log_box, ylog_chk)
    catch
    end
    push!(mainbox, log_box)

    ds_box = GtkBox(:h)
    Gtk.set_gtk_property!(ds_box, :spacing, 10)
    push!(mainbox, ds_box)
    ds_select = GtkComboBoxText()
    for i in 1:MAX_DATASETS
        push!(ds_select, "Dataset $i")
    end
    Gtk.set_gtk_property!(ds_select, :active, 0)
    push!(ds_box, ds_select)

    ds_name_entry = GtkEntry()
    Gtk.set_gtk_property!(ds_name_entry, :text, "Dataset 1")
    push!(ds_box, ds_name_entry)

    ds_color_entry = GtkEntry()
    Gtk.set_gtk_property!(ds_color_entry, :text, DEFAULT_COLORS[1])
    push!(ds_box, ds_color_entry)

    delete_btn = GtkButton("Delete Selected Point")
    push!(ds_box, delete_btn)

    canvas = GtkCanvas()
    # Ensure the canvas can receive keyboard focus so keyboard shortcuts (Alt+Z) work.
    try
        Gtk.set_gtk_property!(canvas, :can_focus, true)
    catch
        # best-effort fallback: some Gtk versions may not accept :can_focus property
    end
    Gtk.set_gtk_property!(canvas, :width_request, 1000)
    Gtk.set_gtk_property!(canvas, :height_request, 520)
    push!(mainbox, canvas)

    status_label = GtkLabel("No image loaded.")
    try
        Gtk.StyleContext.add_class(Gtk.get_style_context(status_label), "app-status")
    catch
    end
    push!(mainbox, status_label)

    state = AppState(win, canvas, nothing, nothing, 0, 0, 1.0, 0.0, 0.0, nothing, nothing, nothing, nothing,
        0.0, 1.0, 0.0, 1.0, false, false, Dataset[], 1, false, nothing, title_entry, xlabel_entry, ylabel_entry, status_label,
        # initialize pointer/zoom helper fields
        (0.0, 0.0),    # last_mouse
        false,         # zoom_mode
        nothing,       # zoom_center
        38.0,          # zoom_radius_px (approx 1 cm at ~96 DPI)
        6.0,           # zoom_level
        false,         # modal_active
        false, Tuple{Float64,Float64}[])

    for i in 1:MAX_DATASETS
        ds = Dataset("Dataset $i", DEFAULT_COLORS[i], hex_to_rgb(DEFAULT_COLORS[i]), Tuple{Float64,Float64}[])
        push!(state.datasets, ds)
    end

    # Callbacks
    Gtk.signal_connect(load_btn, "clicked") do _
        fname = try
            open_dialog("Open Image", state.win, ["*.png", "*.jpg", "*.jpeg"])
        catch
            try
                safe_open_dialog(state, "Open Image", state.win, ["*.png", "*.jpg", "*.jpeg"])
            catch
                ""
            end
        end

        if fname != ""
            try
                img = load(fname)
                state.image = img
                size_tuple = size(img)
                state.img_h = size_tuple[1]
                state.img_w = size_tuple[2]
                state.img_surface = image_to_surface(img)
                state.display_scale = compute_display_scale(state)
                set_label(state.status_label, "Loaded: $(fname)")
                draw(canvas)
            catch e
                set_label(state.status_label, "Failed to load image: $(e)")
            end
        end
    end

    Gtk.signal_connect(calib_btn, "clicked") do _
        if state.image === nothing
            set_label(state.status_label, "Load image first")
            return
        end
        state.calibration_mode = true
        empty!(state.calib_clicks)
        set_label(state.status_label, "Calibration mode: click X-left, X-right, Y-bottom, Y-top (4 clicks).")
        draw(canvas)
    end

    Gtk.signal_connect(apply_calib_btn, "clicked") do _
        if state.px_xmin === nothing
            set_label(state.status_label, "Calibration not recorded")
            return
        end
        xm = safe_parse_float(x_min_entry)
        xM = safe_parse_float(x_max_entry)
        ym = safe_parse_float(y_min_entry)
        yM = safe_parse_float(y_max_entry)
        if xm === nothing || xM === nothing || ym === nothing || yM === nothing
            set_label(state.status_label, "Please enter valid numeric X/Y min/max")
            return
        end
        state.x_min = xm
        state.x_max = xM
        state.y_min = ym
        state.y_max = yM
        state.x_log = Gtk.get_gtk_property(xlog_chk, :active, Bool)
        state.y_log = Gtk.get_gtk_property(ylog_chk, :active, Bool)
        set_label(state.status_label, "Calibration applied.")
    end

    Gtk.signal_connect(ds_select, "changed") do widget
        idx = Gtk.get_gtk_property(widget, :active, Int) + 1
        state.active_dataset = idx
        Gtk.set_gtk_property!(ds_name_entry, :text, state.datasets[idx].name)
        Gtk.set_gtk_property!(ds_color_entry, :text, state.datasets[idx].color)
    end

    Gtk.signal_connect(ds_name_entry, "activate") do widget
        state.datasets[state.active_dataset].name = Gtk.get_gtk_property(widget, :text, String)
        set_label(state.status_label, "Dataset name updated")
        draw(canvas)
    end

    Gtk.signal_connect(ds_color_entry, "activate") do widget
        col = Gtk.get_gtk_property(widget, :text, String)
        state.datasets[state.active_dataset].color = col
        state.datasets[state.active_dataset].color_rgb = hex_to_rgb(col)
        set_label(state.status_label, "Dataset color updated")
        draw(canvas)
    end

    Gtk.signal_connect(delete_btn, "clicked") do _
        if state.drag_idx !== nothing
            di, pi = state.drag_idx
            if 1 <= di <= length(state.datasets) && 1 <= pi <= length(state.datasets[di].points)
                deleteat!(state.datasets[di].points, pi)
            end
            state.drag_idx = nothing
            set_label(state.status_label, "Deleted selected point")
            draw(canvas)
        else
            set_label(state.status_label, "No selected point to delete – click near a point to select")
        end
    end

    Gtk.signal_connect(auto_trace_btn, "clicked") do _
        if state.image === nothing
            set_label(state.status_label, "Load an image first")
            return
        end
        if state.px_xmin === nothing || state.px_xmax === nothing || state.px_ymin === nothing || state.px_ymax === nothing
            set_label(state.status_label, "Please perform calibration before auto-trace")
            return
        end
        ds = state.datasets[state.active_dataset]
        target_rgb = hex_to_rgb(ds.color)
        sampled = auto_trace_scan(state, target_rgb)
        state.datasets[state.active_dataset].points = sampled
        set_label(state.status_label, "Auto-trace completed – $(length(sampled)) points")
        draw(canvas)
    end

    @guarded draw(canvas) do widget
        ctx = getgc(canvas)
        draw_canvas(state, ctx)
    end

    Gtk.signal_connect(canvas, "button-press-event") do widget, event
        # Grab focus on mouse click so the canvas receives key events (Alt+Z toggling).
        try
            # Prefer setting can_focus at widget creation; ensure here too (best-effort).
            Gtk.set_gtk_property!(widget, :can_focus, true)
        catch
        end
        try
            Gtk.grab_focus(widget)
        catch
            try
                # Fallbacks for different Gtk.jl versions
                Gtk.Widget.grab_focus(widget)
            catch
            end
        end

        if state.calibration_mode
            px = event.x
            py = event.y
            push!(state.calib_clicks, (px, py))
            nleft = 4 - length(state.calib_clicks)
            if nleft > 0
                set_label(state.status_label, "Calibration: recorded click $(length(state.calib_clicks)). $(nleft) more.")
            else
                state.px_xmin = state.calib_clicks[1]
                state.px_xmax = state.calib_clicks[2]
                state.px_ymin = state.calib_clicks[3]
                state.px_ymax = state.calib_clicks[4]
                state.calibration_mode = false
                set_label(state.status_label, "Calibration clicks recorded – enter numeric ranges and Apply Calibration")
            end
            draw(canvas)
            return true
        end

        if state.image === nothing
            return false
        end

        # If zoom mode is active, use the zoom center for point placement and hit-testing;
        # otherwise use the raw event coordinates.
        if state.zoom_mode && state.zoom_center !== nothing
            x, y = state.zoom_center
        else
            x = event.x
            y = event.y
        end

        found = find_nearest_point(state, x, y, 8.0)
        if event.button == 1
            if found !== nothing
                state.dragging = true
                state.drag_idx = found
                set_label(state.status_label, "Selected point for dragging (dataset $(found[1]), point $(found[2]))")
            else
                dx, dy = canvas_to_data(state, x, y)
                push!(state.datasets[state.active_dataset].points, (dx, dy))
                set_label(state.status_label, "Added point: ($(dx), $(dy))")
            end
            draw(canvas)
            return true
        elseif event.button == 3
            if found !== nothing
                di, pi = found
                deleteat!(state.datasets[di].points, pi)
                set_label(state.status_label, "Deleted point from dataset $(di)")
            end
            draw(canvas)
            return true
        end
        return false
    end

    Gtk.signal_connect(canvas, "motion-notify-event") do widget, event
        # track the most recent mouse position for precision zoom activation
        try
            state.last_mouse = (event.x, event.y)
        catch
        end

        # If precision zoom is active, move the zoom overlay to follow the cursor
        try
            if state.zoom_mode && state.zoom_center !== nothing
                # keep the zoom overlay centered on the most recent pointer
                state.zoom_center = state.last_mouse
                # redraw to reflect the overlay movement
                draw(canvas)
            end
        catch
        end

        if state.dragging && state.drag_idx !== nothing
            di, pi = state.drag_idx
            dx, dy = canvas_to_data(state, event.x, event.y)
            if 1 <= di <= length(state.datasets) && 1 <= pi <= length(state.datasets[di].points)
                state.datasets[di].points[pi] = (dx, dy)
            end
            draw(canvas)
        end
        return false
    end

    Gtk.signal_connect(canvas, "button-release-event") do widget, event
        if state.dragging
            state.dragging = false
            set_label(state.status_label, "Drag finished")
            return true
        end
        return false
    end

    # Key handling: Delete/Backspace handled above; add accelerators for Save/Exit

    # Canvas-level key handling for precision zoom (Alt+Z toggles zoom-mode when the canvas has focus).
    Gtk.signal_connect(canvas, "key-press-event") do widget, event
        # detect Alt modifier robustly
        alt = false
        try
            st = event.state
            alt_mask = 0
            try
                alt_mask = Gdk.ModifierType.MOD1_MASK
            catch
                try
                    alt_mask = Gtk.gdk.MOD1_MASK
                catch
                    alt_mask = 0x8
                end
            end
            if alt_mask != 0
                alt = (Int(st) & Int(alt_mask)) != 0
            else
                alt = (Int(st) & 0x8) != 0
            end
        catch
            alt = false
        end

        key = event.keyval
        ch = '\0'
        try
            ch = uppercase(Char(key))
        catch
            ch = '\0'
        end

        if alt && ch == 'Z'
            # Toggle precision zoom centered at the last known mouse position.
            state.zoom_mode = !state.zoom_mode
            if state.zoom_mode
                state.zoom_center = state.last_mouse
                # Attempt to query screen DPI; fallback to 96 dpi.
                dpi = 96.0
                try
                    scr = Gdk.Screen.get_default()
                    dpi_try = try
                        Gdk.Screen.get_resolution(scr)
                    catch
                        0.0
                    end
                    if dpi_try > 0
                        dpi = dpi_try
                    end
                catch
                end
                px_per_cm = dpi / 2.54
                state.zoom_radius_px = px_per_cm * 1.0
                # default magnification for precision placement
                state.zoom_level = 6.0
                set_label(state.status_label, "Zoom precision enabled")
            else
                state.zoom_center = nothing
                set_label(state.status_label, "Zoom precision disabled")
            end
            draw(canvas)
            return true
        end

        return false
    end
    Gtk.signal_connect(win, "key-press-event") do widget, event
        # event.keyval is an integer; try to robustly derive a character and modifier state
        key = event.keyval
        # detect modifier state safely
        primary = false
        shift = false
        try
            st = event.state
            # Try to obtain platform constants; fall back to bit masks
            control_mask = 0
            try
                control_mask = Gdk.ModifierType.CONTROL_MASK
            catch
                try
                    control_mask = Gtk.gdk.CONTROL_MASK
                catch
                    control_mask = 0
                end
            end
            shift_mask = 0
            try
                shift_mask = Gdk.ModifierType.SHIFT_MASK
            catch
                try
                    shift_mask = Gtk.gdk.SHIFT_MASK
                catch
                    shift_mask = 0
                end
            end
            if control_mask != 0
                primary = (Int(st) & Int(control_mask)) != 0
            else
                # common fallback: ControlMask is often 1<<2 == 0x4
                primary = (Int(st) & 0x4) != 0
            end
            if shift_mask != 0
                shift = (Int(st) & Int(shift_mask)) != 0
            else
                # common fallback: ShiftMask often 1 (0x1)
                shift = (Int(st) & 0x1) != 0
            end
        catch
            st2 = 0
            try
                st2 = event.state
            catch
                st2 = 0
            end
            primary = (Int(st2) & 0x4) != 0
            shift = (Int(st2) & 0x1) != 0
        end

        # Map keyval to a char where possible
        ch = '\0'
        try
            ch = uppercase(Char(key))
        catch
            try
                # GDK uppercase mapping might be available via keysym; warn and skip
                ch = '\0'
            catch
                ch = '\0'
            end
        end

        # Handle Delete/Backspace already covered by buttonless event earlier; but keep other shortcuts:
        if primary && ch == 'S'
            # Primary+S -> Save JSON; Primary+Shift+S -> Save CSV
            if shift
                # Save CSV
                fname = safe_save_dialog(state, "Save CSV File", state.win, ["*.csv"])
                if fname != ""
                    if !endswith(lowercase(fname), ".csv")
                        fname *= ".csv"
                    end
                    try
                        export_csv(state, fname)
                        set_label(state.status_label, "Saved CSV to: $fname")
                    catch e
                        set_label(state.status_label, "CSV save failed: $e")
                    end
                end
            else
                # Save JSON
                fname = safe_save_dialog(state, "Save JSON File", state.win, ["*.json"])
                if fname != ""
                    if !endswith(lowercase(fname), ".json")
                        fname *= ".json"
                    end
                    try
                        export_json(state, fname)
                        set_label(state.status_label, "Saved JSON to: $fname")
                    catch e
                        set_label(state.status_label, "JSON save failed: $e")
                    end
                end
            end
            return true
        elseif primary && ch == 'Q'
            ok = confirm_exit_and_maybe_save(state)
            if ok
                force_quit(state)
                return false
            else
                # swallow to prevent window close
                return true
            end
        else
            return false
        end
    end

    # Wire up Save / Export / Exit actions for buttons and menu items (best-effort)
    handler_save_json = function (_=nothing)
        fname = safe_save_dialog(state, "Save JSON File", state.win, ["*.json"])
        if fname == ""
            return
        end
        if !endswith(lowercase(fname), ".json")
            fname *= ".json"
        end
        try
            export_json(state, fname)
            set_label(state.status_label, "Saved JSON to: $fname")
        catch e
            set_label(state.status_label, "Failed to save JSON: $e")
        end
    end

    handler_save_csv = function (_=nothing)
        fname = safe_save_dialog(state, "Save CSV File", state.win, ["*.csv"])
        if fname == ""
            return
        end
        if !endswith(lowercase(fname), ".csv")
            fname *= ".csv"
        end
        try
            export_csv(state, fname)
            set_label(state.status_label, "Saved CSV to: $fname")
        catch e
            set_label(state.status_label, "Failed to save CSV: $e")
        end
    end

    handler_exit = function (_=nothing)
        ok = confirm_exit_and_maybe_save(state)
        if ok
            force_quit(state)
        end
    end

    try
        if save_json_btn !== nothing
            Gtk.signal_connect(save_json_btn, "clicked") do w
                handler_save_json()
            end
        end
    catch
    end
    try
        if save_csv_btn !== nothing
            Gtk.signal_connect(save_csv_btn, "clicked") do w
                handler_save_csv()
            end
        end
    catch
    end
    try
        if save_json_mi !== nothing
            Gtk.signal_connect(save_json_mi, "activate") do w
                handler_save_json()
            end
        end
    catch
    end
    try
        if save_csv_mi !== nothing
            Gtk.signal_connect(save_csv_mi, "activate") do w
                handler_save_csv()
            end
        end
    catch
    end
    try
        Gtk.signal_connect(exit_btn, "clicked") do _
            handler_exit()
        end
    catch
    end
    try
        if exit_mi !== nothing
            Gtk.signal_connect(exit_mi, "activate") do _
                handler_exit()
            end
        end
    catch
    end

    # When the window is asked to close, confirm/save
    try
        Gtk.signal_connect(win, "delete-event") do widget, event
            ok = confirm_exit_and_maybe_save(state)
            if ok
                force_quit(state)
                # return false to allow default handler to destroy window
                return false
            else
                # prevent window from closing
                return true
            end
        end
    catch
    end

    # return the state so caller can manipulate it
    return state
end

# --------------------------
# Run the app when executed directly
# --------------------------
if abspath(PROGRAM_FILE) == @__FILE__
    global app_state = nothing
    # Basic startup diagnostics to help when the app does not open and no terminal output is visible.
    # These prints are intentionally lightweight and will always go to stdout/stderr.
    try
        println("GraphDigitizer: starting up")
        println("Julia version: ", VERSION)
        println("Current working directory: ", pwd())
        ensure_readme()
    catch e
        @warn "ensure_readme() failed" exception = (e, catch_backtrace())
    end

    # Create the UI and enter the GTK main loop with stronger diagnostics and error logging.
    try
        println("GraphDigitizer: creating application UI...")
        global app_state = create_app()
    catch e
        bt = catch_backtrace()
        @error "Failed to create application UI" exception = (e, bt)
        println("ERROR: Failed to create application UI: ", e)
        rethrow(e)
    end

    # Show the main window (attempt both showall and show) and enter the main loop.
    try
        println("GraphDigitizer: showing window...")
        try
            Gtk.showall(app_state.win)
        catch inner
            @warn "Gtk.showall failed, attempting Gtk.show" error = inner
            try
                Gtk.show(app_state.win)
            catch inner2
                @error "Gtk.show also failed" error = inner2
                println("ERROR: Unable to show window. See logs for details.")
                rethrow(inner2)
            end
        end

        println("GraphDigitizer: entering GTK main loop...")

        # Robustly choose an available GTK main-loop entry point.
        # Prefer `main`, then `gtk_main`, then `start`. Only call the first one
        # that is present and succeeds.
        did_run = false

        if isdefined(Gtk, :main) && !did_run
            try
                Gtk.main()
                did_run = true
            catch e
                @warn "Gtk.main raised an exception; will try fallbacks" exception = (e, catch_backtrace())
            end
        end

        if isdefined(Gtk, :gtk_main) && !did_run
            try
                Gtk.gtk_main()
                did_run = true
            catch e2
                @warn "Gtk.gtk_main raised an exception; will try Gtk.start()" exception = (e2, catch_backtrace())
            end
        end

        if isdefined(Gtk, :start) && !did_run
            try
                Gtk.start()
                did_run = true
            catch e3
                @error "Gtk.start raised an exception; GTK main loop failed" exception = (e3, catch_backtrace())
                println("ERROR: GTK main loop failed: ", e3)
                rethrow(e3)
            end
        end

        if !did_run
            @error "No known GTK main-loop entry point found (Gtk.main, Gtk.gtk_main, Gtk.start)"
            error("No GTK main loop entry point available")
        end
    catch e
        @error "Failed while showing window or running GTK main loop" exception = (e, catch_backtrace())
        println("ERROR: Failed to start GraphDigitizer: ", e)
        rethrow(e)
    end
end

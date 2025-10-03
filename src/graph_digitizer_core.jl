module GraphDigitizerCore

# Headless core utilities for GraphDigitizer
#
# This module provides pure, GUI-independent implementations of:
# - filename sanitization and default filename helpers
# - coordinate transforms between data-space and canvas/image pixels
# - simple hex color parsing (returns RGB tuple)
#
# The intent is that tests and headless examples can use these routines
# without constructing GTK widgets or touching the GUI code.

using Dates

export CoreState,
       _sanitize_filename,
       _preferred_downloads_dir,
       default_filename_for_save,
       default_filename_from_title,
       hex_to_rgb_tuple,
       compute_display_scale,
       data_to_canvas,
       canvas_to_data

# -----------------------
# Core types
# -----------------------

"""
Lightweight headless application state used for pure transforms.

Fields:
- `img_w::Int` / `img_h::Int` : image pixel dimensions (width, height)
- `display_scale::Float64` : uniform scale applied when drawing image into canvas
- `offset_x::Float64` / `offset_y::Float64` : top-left offset of the image in canvas coordinates

Calibration anchors (canvas pixel coordinates):
- `px_xmin::Union{Nothing,Tuple{Float64,Float64}}`
- `px_xmax::Union{Nothing,Tuple{Float64,Float64}}`
- `px_ymin::Union{Nothing,Tuple{Float64,Float64}}`
- `px_ymax::Union{Nothing,Tuple{Float64,Float64}}`

Numeric ranges and log flags:
- `x_min`, `x_max`, `y_min`, `y_max` :: Float64
- `x_log`, `y_log` :: Bool
"""
mutable struct CoreState
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

    CoreState(img_w::Int=0, img_h::Int=0;
              display_scale::Float64=1.0,
              offset_x::Float64=0.0,
              offset_y::Float64=0.0,
              px_xmin=nothing,
              px_xmax=nothing,
              px_ymin=nothing,
              px_ymax=nothing,
              x_min::Float64=0.0,
              x_max::Float64=1.0,
              y_min::Float64=0.0,
              y_max::Float64=1.0,
              x_log::Bool=false,
              y_log::Bool=false) = new(img_w, img_h, display_scale, offset_x, offset_y,
                                        px_xmin, px_xmax, px_ymin, px_ymax,
                                        x_min, x_max, y_min, y_max, x_log, y_log)
end

# Keyword-only constructor for convenience in tests/examples:
# Allows calling CoreState(img_w=..., img_h=..., x_min=..., ...) with keywords.
function CoreState(; img_w::Int=0, img_h::Int=0,
                   display_scale::Float64=1.0,
                   offset_x::Float64=0.0,
                   offset_y::Float64=0.0,
                   px_xmin=nothing,
                   px_xmax=nothing,
                   px_ymin=nothing,
                   px_ymax=nothing,
                   x_min::Float64=0.0,
                   x_max::Float64=1.0,
                   y_min::Float64=0.0,
                   y_max::Float64=1.0,
                   x_log::Bool=false,
                   y_log::Bool=false)
    return CoreState(img_w, img_h;
                     display_scale=display_scale,
                     offset_x=offset_x,
                     offset_y=offset_y,
                     px_xmin=px_xmin,
                     px_xmax=px_xmax,
                     px_ymin=px_ymin,
                     px_ymax=px_ymax,
                     x_min=x_min,
                     x_max=x_max,
                     y_min=y_min,
                     y_max=y_max,
                     x_log=x_log,
                     y_log=y_log)
end

# -----------------------
# Filename helpers
# -----------------------

"""
Return the user's Downloads directory when available; otherwise return `tempdir()`.

Best-effort: catches exceptions and uses `tempdir()` as a final fallback.
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
Sanitize a string to be used as a filesystem base filename.

Behavior:
- Trim leading/trailing whitespace.
- Replace any character not in A-Za-z0-9_.- with underscore.
- Collapse consecutive underscores into one.
- Trim leading/trailing underscores or dots.

Returns an empty string when the sanitized result is empty.
"""
function _sanitize_filename(s::AbstractString)::String
    s2 = strip(String(s))
    if isempty(s2)
        return ""
    end
    # Replace disallowed characters with underscore
    t = replace(s2, r"[^A-Za-z0-9_.-]" => "_")
    # Collapse multiple underscores into a single underscore
    t = replace(t, r"_+" => "_")
    # Remove underscores immediately before a dot (e.g. "name_.json" -> "name.json")
    t = replace(t, r"_+\." => ".")
    # Collapse multiple dots to a single dot (avoid sequences like "..")
    t = replace(t, r"\.+" => ".")
    # Trim leading/trailing underscores or dots
    t = replace(t, r"^[_.]+|[_.]+$" => "")
    return isempty(t) ? "" : t
end

"""
Construct a default filename path for saving using the provided title (or timestamp).

Arguments:
- `title::AbstractString` : title text (may be empty)
- `ext::AbstractString` : extension without leading dot (e.g. "json", "csv")

Returns a full path in the preferred downloads directory.
"""
function default_filename_for_save(title::AbstractString, ext::AbstractString)::String
    base = _sanitize_filename(title)
    if isempty(base)
        base = "graphdigitizer_export_" * Dates.format(Dates.now(), "yyyy-mm-dd_HHMMSS")
    end
    dir = _preferred_downloads_dir()
    return joinpath(dir, string(base, ".", lowercase(ext)))
end

"""
Ensure a filename (derived from title) ends with the requested extension.

If the provided `fname` lacks the given extension it will be appended.
"""
function default_filename_from_title(title::AbstractString, ext::AbstractString)::String
    fname = default_filename_for_save(title, ext)
    if !endswith(lowercase(fname), "." * lowercase(ext))
        fname *= "." * lowercase(ext)
    end
    return fname
end

# -----------------------
# Color parsing (headless)
# -----------------------

"""
Parse a hex color string into an (r,g,b) tuple of Float64 values in [0,1].

Supported inputs:
- "#RRGGBB", "RRGGBB"
- "#RGB", "RGB" (3-digit shorthand)

Returns `(0.0, 0.0, 0.0)` on parse failure.
"""
function hex_to_rgb_tuple(hex::AbstractString)::NTuple{3,Float64}
    h = String(strip(hex))
    if startswith(h, "#")
        h = h[2:end]
    end
    try
        if length(h) == 3
            # Expand shorthand e.g. "f80" -> "ff8800"
            h = string(h[1], h[1], h[2], h[2], h[3], h[3])
        end
        if length(h) == 6
            r = parse(Int, h[1:2], base=16) / 255.0
            g = parse(Int, h[3:4], base=16) / 255.0
            b = parse(Int, h[5:6], base=16) / 255.0
            return (float(r), float(g), float(b))
        end
    catch
        # fall through to failure
    end
    return (0.0, 0.0, 0.0)
end

# -----------------------
# Display scale helper
# -----------------------

"""
Compute a uniform display scale to fit an image of size (`img_w`, `img_h`)
inside a canvas of size (`canvas_w`, `canvas_h`) while preserving aspect ratio.

Returns 1.0 if any dimension is zero or unknown.
"""
function compute_display_scale(img_w::Int, img_h::Int, canvas_w::Int, canvas_h::Int)::Float64
    if img_w <= 0 || img_h <= 0 || canvas_w <= 0 || canvas_h <= 0
        return 1.0
    end
    sx = canvas_w / float(img_w)
    sy = canvas_h / float(img_h)
    return min(sx, sy)
end

"""
Compute display scale using a CoreState and canvas dimensions.

This is a small convenience wrapper that updates `state.display_scale` and
returns the computed value.
"""
function compute_display_scale(state::CoreState, canvas_w::Int, canvas_h::Int)::Float64
    s = compute_display_scale(state.img_w, state.img_h, canvas_w, canvas_h)
    state.display_scale = s
    return s
end

# -----------------------
# Coordinate transforms
# -----------------------

"""
Map a data-space point `(dx, dy)` to canvas coordinates `(px, py)` using the
calibration anchors and numeric ranges stored in `state`.

Returns `(0.0, 0.0)` when calibration anchors are missing or invalid.

Behavior:
- Linear interpolation for linear axes.
- Base-10 log interpolation when `state.x_log` or `state.y_log` are true.
"""
function data_to_canvas(state::CoreState, dx::Float64, dy::Float64)::Tuple{Float64,Float64}
    if state.px_xmin === nothing || state.px_xmax === nothing || state.px_ymin === nothing || state.px_ymax === nothing
        return (0.0, 0.0)
    end

    xpx1 = state.px_xmin[1]
    xpx2 = state.px_xmax[1]

    # X fraction
    if state.x_log
        if dx <= 0 || state.x_min <= 0
            t = 0.0
        else
            num = log10(dx) - log10(state.x_min)
            den = log10(state.x_max) - log10(state.x_min)
            t = den == 0.0 ? 0.0 : num / den
        end
    else
        den = (state.x_max - state.x_min)
        t = den == 0.0 ? 0.0 : (dx - state.x_min) / den
    end
    px = xpx1 + t * (xpx2 - xpx1)

    ypx1 = state.px_ymin[2]
    ypx2 = state.px_ymax[2]

    if state.y_log
        if dy <= 0 || state.y_min <= 0
            u = 0.0
        else
            num = log10(dy) - log10(state.y_min)
            den = log10(state.y_max) - log10(state.y_min)
            u = den == 0.0 ? 0.0 : num / den
        end
    else
        den = (state.y_max - state.y_min)
        u = den == 0.0 ? 0.0 : (dy - state.y_min) / den
    end
    py = ypx1 + u * (ypx2 - ypx1)

    return (px, py)
end

"""
Inverse transform: convert canvas coordinates `(cx, cy)` into data values `(x, y)`
using the calibration anchors and numeric ranges in `state`.

Returns `(0.0, 0.0)` when calibration anchors are missing or invalid.
"""
function canvas_to_data(state::CoreState, cx::Float64, cy::Float64)::Tuple{Float64,Float64}
    if state.px_xmin === nothing || state.px_xmax === nothing || state.px_ymin === nothing || state.px_ymax === nothing
        return (0.0, 0.0)
    end

    xpx1 = state.px_xmin[1]
    xpx2 = state.px_xmax[1]
    denomx = (xpx2 - xpx1)
    t = denomx == 0.0 ? 0.0 : (cx - xpx1) / denomx

    if state.x_log
        val = 10.0 ^ (log10(state.x_min) + t * (log10(state.x_max) - log10(state.x_min)))
    else
        val = state.x_min + t * (state.x_max - state.x_min)
    end

    ypx1 = state.px_ymin[2]
    ypx2 = state.px_ymax[2]
    denomy = (ypx2 - ypx1)
    u = denomy == 0.0 ? 0.0 : (cy - ypx1) / denomy

    if state.y_log
        valy = 10.0 ^ (log10(state.y_min) + u * (log10(state.y_max) - log10(state.y_min)))
    else
        valy = state.y_min + u * (state.y_max - state.y_min)
    end

    return (val, valy)
end

end # module GraphDigitizerCore

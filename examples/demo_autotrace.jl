#!/usr/bin/env julia
#
# demo_autotrace.jl
#
# Example script that programmatically demonstrates a simple calibration and
# the auto-trace routine provided by GraphDigitizer. This script:
#
# 1. Loads the library source (safe to `include` because the GUI main loop is
#    guarded in `src/graph_digitizer.jl`).
# 2. Creates an application state via `create_app()` (widgets are created but
#    the GUI is not shown).
# 3. Loads the provided image file and computes a simple calibration that maps
#    image pixel coordinates directly to data coordinates (useful for demos).
# 4. Runs `auto_trace_scan` using a dataset color and writes JSON/CSV outputs.
#
# Usage:
#   julia --project=@. examples/demo_autotrace.jl path/to/image.png [xmin xmax ymin ymax] [hexcolor] [title]
#
# Example:
#   julia --project=@. examples/demo_autotrace.jl examples/sample_plot.png 0 10 0 100 "#E69F00" "Demo Plot"
#
# Notes:
# - This script uses a pragmatic calibration: left/right X anchors -> image left/right
#   and bottom/top Y anchors -> image bottom/top. For best results, supply numeric
#   axis ranges that match the plot in the image.
# - The script requires the repository environment (packages listed in Project.toml)
#   and a working GTK runtime for Gtk.jl to instantiate widgets (create_app).
#
using Printf, FileIO, ImageIO, Colors, ImageCore

function print_usage_and_exit()
    println("Usage: julia --project=@. examples/demo_autotrace.jl <image_path> [xmin xmax ymin ymax] [hexcolor] [title]")
    println("Example: julia --project=@. examples/demo_autotrace.jl test/plot.png 0 10 0 100 \"#E69F00\" \"Demo Plot\"")
    exit(1)
end

# Parse args
if length(ARGS) < 1
    print_usage_and_exit()
end

image_path = ARGS[1]
xmin = nothing
xmax = nothing
ymin = nothing
ymax = nothing
color_hex = nothing
title_text = nothing

# Positional parsing (basic)
if length(ARGS) >= 5
    try
        xmin = parse(Float64, ARGS[2])
        xmax = parse(Float64, ARGS[3])
        ymin = parse(Float64, ARGS[4])
        ymax = parse(Float64, ARGS[5])
    catch
        println("Warning: failed to parse numeric ranges; falling back to pixel-based ranges.")
        xmin = nothing
    end
    if length(ARGS) >= 6
        color_hex = ARGS[6]
    end
    if length(ARGS) >= 7
        title_text = ARGS[7]
    end
elseif length(ARGS) >= 2
    # If only some additional args provided, try to use them flexibly
    try
        xmin = parse(Float64, ARGS[2])
    catch
        xmin = nothing
    end
    if length(ARGS) >= 3
        try
            xmax = parse(Float64, ARGS[3])
        catch
            xmax = nothing
        end
    end
    if length(ARGS) >= 4
        try
            ymin = parse(Float64, ARGS[4])
        catch
            ymin = nothing
        end
    end
    if length(ARGS) >= 5
        try
            ymax = parse(Float64, ARGS[5])
        catch
            ymax = nothing
        end
    end
    if length(ARGS) >= 6
        color_hex = ARGS[6]
    end
    if length(ARGS) >= 7
        title_text = ARGS[7]
    end
end

# Locate and include the core library. Use path relative to this script file so
# the demo can be launched from the repository root or other working directories.
script_dir = dirname(@__FILE__)
core_path = abspath(joinpath(script_dir, "..", "src", "graph_digitizer_core.jl"))
println("Including headless core from: ", core_path)
include(core_path)
using .GraphDigitizerCore

# Create a headless CoreState (will populate dims after image load)
state = CoreState()

# Load the image using the same loader used in the GUI (FileIO/ImageIO)
println("Loading image: ", image_path)
img = nothing
try
    img = load(image_path)
catch e
    println("Failed to load image: ", e)
    exit(1)
end

# Populate a headless CoreState using the loaded image dimensions
sz = size(img)
# Assume first two dims are (height, width)
img_h = Int(sz[1])
img_w = Int(sz[2])

# Create a CoreState that maps canvas coords 1..img_w and 1..img_h to data units by default.
# We'll set a simple pixel-based numeric range (1..img_w, 1..img_h) unless the user provided numeric ranges.
state = CoreState(img_w = img_w,
                  img_h = img_h,
                  display_scale = 1.0,
                  offset_x = 0.0,
                  offset_y = 0.0,
                  px_xmin = nothing,
                  px_xmax = nothing,
                  px_ymin = nothing,
                  px_ymax = nothing,
                  x_min = 1.0,
                  x_max = float(img_w),
                  y_min = 1.0,
                  y_max = float(img_h),
                  x_log = false,
                  y_log = false)

# Define a simple calibration that maps the full image pixel extents to data extents.
# px_xmin: left (x=1), px_xmax: right (x=img_w)
# px_ymin: bottom (y=img_h), px_ymax: top (y=1) -- canvas Y grows downward so bottom=img_h.
state.px_xmin = (1.0, 1.0)
state.px_xmax = (float(state.img_w), 1.0)
state.px_ymin = (1.0, float(state.img_h))
state.px_ymax = (1.0, 1.0)

# Set numeric axis ranges. If the user supplied values use them; otherwise use
# pixel-space ranges (so data values equal pixel coordinates).
if xmin !== nothing && xmax !== nothing && ymin !== nothing && ymax !== nothing
    state.x_min = xmin
    state.x_max = xmax
    state.y_min = ymin
    state.y_max = ymax
    println("Using numeric ranges: X in [", xmin, ", ", xmax, "], Y in [", ymin, ", ", ymax, "]")
else
    # default: map data units to pixel coordinates
    state.x_min = 1.0
    state.x_max = float(state.img_w)
    state.y_min = 1.0
    state.y_max = float(state.img_h)
    println("No numeric ranges supplied; using pixel-based ranges:")
    println("  x_min=", state.x_min, " x_max=", state.x_max)
    println("  y_min=", state.y_min, " y_max=", state.y_max)
end
# ensure linear mapping for demo
state.x_log = false
state.y_log = false

# Configure active dataset color
if color_hex !== nothing
    try
        state.datasets[state.active_dataset].color = color_hex
        state.datasets[state.active_dataset].color_rgb = hex_to_rgb(color_hex)
        println("Set active dataset color to ", color_hex)
    catch
        println("Warning: failed to set dataset color; using default.")
    end
else
    println("Using dataset color: ", state.datasets[state.active_dataset].color)
end

# Optional title for default filename
if title_text !== nothing
    try
        Gtk.set_gtk_property!(state.title_entry, :text, title_text)
    catch
        # best-effort
    end
end

# Run a headless auto-trace across image columns using the provided dataset color (or provided hex)
println("Running headless auto-trace ...")

# Determine target RGB: prefer a user-supplied hex color, otherwise default to the provided argument or a sensible default.
target_hex = color_hex !== nothing ? color_hex : "#0072B2"
tuple_rgb = hex_to_rgb_tuple(target_hex)
target_rgb = RGB{Float64}(tuple_rgb[1], tuple_rgb[2], tuple_rgb[3])

# Ensure calibration anchors are set in canvas pixel coordinates (canvas == image pixels for headless run)
# If they haven't been set earlier, set them to full image extents.
if state.px_xmin === nothing
    state.px_xmin = (1.0, float(state.img_h))
end
if state.px_xmax === nothing
    state.px_xmax = (float(state.img_w), float(state.img_h))
end
if state.px_ymin === nothing
    state.px_ymin = (1.0, float(state.img_h))
end
if state.px_ymax === nothing
    state.px_ymax = (1.0, 1.0)
end

# Headless column-wise color-match auto-trace:
sampled = Tuple{Float64,Float64}[]
for ix in 1:state.img_w
    bestd = Inf
    besty = 0
    for j in 1:state.img_h
        pixel = try
            img[j, ix]
        catch
            nothing
        end
        if pixel === nothing
            continue
        end
        pr = float(red(pixel))
        pg = float(green(pixel))
        pb = float(blue(pixel))
        d = sqrt((pr - target_rgb.r)^2 + (pg - target_rgb.g)^2 + (pb - target_rgb.b)^2)
        if d < bestd
            bestd = d
            besty = j
        end
    end
    if besty > 0
        cx = float(ix)
        cy = float(besty)
        dx, dy = canvas_to_data(state, cx, cy)
        push!(sampled, (dx, dy))
    end
end

println("Auto-trace found $(length(sampled)) points.")

# Print a short sample of points
nsample = min(10, length(sampled))
if nsample > 0
    println("First $(nsample) points (x, y):")
    for i in 1:nsample
        @printf("  %3d: % .6g, % .6g\n", i, sampled[i][1], sampled[i][2])
    end
else
    println("No points found by auto-trace (check the dataset color and calibration).")
end

# Save outputs: JSON + CSV. Use the safe default filename helpers so artists can
# locate results when run in environments without a Save dialog.
out_json = default_filename_from_title(state, "json")
out_csv = default_filename_from_title(state, "csv")

# Export JSON and CSV (wrap in try/catch to avoid hard failures in demo)
try
    export_json(state, out_json)
    println("Saved JSON export to: ", out_json)
catch e
    println("Failed to save JSON: ", e)
end

try
    export_csv(state, out_csv)
    println("Saved CSV export to: ", out_csv)
catch e
    println("Failed to save CSV: ", e)
end

println("Demo complete.")

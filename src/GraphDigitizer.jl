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

module GraphDigitizer
# GraphDigitizer.jl
#
# Module wrapper for the GraphDigitizer package.
#
# This file makes the project a valid Julia package so that
# `Pkg.instantiate()` and `using GraphDigitizer` work without
# immediately pulling in the heavy GTK / GUI dependencies.
#
# Structure:
# - Always loads the lightweight, headless core (coordinate transforms,
#   filename helpers, color parsing) from `graph_digitizer_core.jl`.
# - Lazily loads the GUI implementation in `graph_digitizer.jl` only
#   when you explicitly call `start_gui()` or `gui_create_app()`.
#
# Rationale:
# Precompilation previously failed with:
#   "Missing source file for Base.PkgId(..., \"GraphDigitizer\")"
# because there was no `GraphDigitizer.jl` defining the module that
# matches Project.toml's name entry. This file resolves that while
# avoiding hard dependencies on GUI-only packages at import time.

###############
# Headless core
###############

include("graph_digitizer_core.jl")
using .GraphDigitizerCore

# Re-export core (pure) functionality so users can do:
# using GraphDigitizer; data_to_canvas(...)
export CoreState,
       _sanitize_filename,
       _preferred_downloads_dir,
       default_filename_for_save,
       default_filename_from_title,
       hex_to_rgb_tuple,
       compute_display_scale,
       data_to_canvas,
       canvas_to_data,
       start_gui,
       gui_create_app

#########################
# Lazy GUI load machinery
#########################

const _GUI_LOADED = Ref(false)

"""
_internal_load_gui!()

Internal helper that includes the large GUI script `graph_digitizer.jl`
exactly once. Any failure related to a missing dependency (notably
`Graphics.jl`) is trapped to provide a clearer diagnostic before rethrowing.
"""
function _internal_load_gui!()
    if _GUI_LOADED[]
        return
    end
    try
        # The GUI script contains: using Gtk, Cairo, Graphics, etc.
        # It also defines `create_app()` and a guarded main runner block.
        include("graph_digitizer.jl")
        _GUI_LOADED[] = true
    catch e
        # Heuristic: detect missing Graphics dependency (common issue).
        io = IOBuffer()
        showerror(io, e)
        msg = String(take!(io))
        if occursin("Graphics", msg)
            @error "Missing dependency 'Graphics'. Install it with:\n    import Pkg; Pkg.add(\"Graphics\")"
        end
        rethrow(e)
    end
end

"""
gui_create_app() -> state

Load the GUI code (if not already loaded) and construct the application
without starting the GTK main loop or showing the window. Returns the
`AppState` object defined in the GUI script.

This is useful for programmatic testing or embedding when you want
control over when the window is shown and when the GTK main loop starts.
"""
function gui_create_app()
    _internal_load_gui!()
    # After inclusion, `create_app` is defined in this module's scope.
    return getfield(GraphDigitizer, :create_app)()
end

"""
start_gui(; show_window::Bool=true, run_loop::Bool=true) -> state

Convenience launcher for the interactive GUI.

Arguments (keywords):
- show_window (Bool, default: true): whether to call `Gtk.showall(state.win)`.
- run_loop (Bool, default: true): whether to enter the GTK main loop (blocks the current task).

Returns:
- The `AppState` instance produced by the underlying `create_app()` function.

Examples:
    using GraphDigitizer
    state = start_gui()  # typical interactive use

    # Advanced: create only, then manually manage loop
    state = start_gui(show_window=true, run_loop=false)
    # ... custom instrumentation ...
    Gtk.main()

Errors:
- If the user lacks the `Graphics` package (required by the original GUI code),
  an explanatory error is emitted instructing installation.
"""
function start_gui(; show_window::Bool=true, run_loop::Bool=true)
    state = gui_create_app()

    if show_window
        # Best-effort show (Gtk.showall preferred, fallback to Gtk.show)
        try
            Gtk.showall(state.win)
        catch
            try
                Gtk.show(state.win)
            catch
            end
        end
    end

    if run_loop
        # Enter the GTK main loop only if not already running.
        # Try common entry points (Gtk.main / Gtk.start) defensively.
        already = false
        try
            if isdefined(Gtk, :main_level)
                already = Gtk.main_level() > 0
            end
        catch
        end
        if !already
            started = false
            if isdefined(Gtk, :main)
                try
                    Gtk.main()
                    started = true
                catch
                end
            end
            if !started && isdefined(Gtk, :start)
                Gtk.start()
            end
        end
    end

    return state
end

################
# Package init
################

"""
__init__()

Currently a no-op; reserved for future runtime initialization
(e.g. logging setup, optional dependency probing, environment checks).
"""
function __init__()
    # Intentionally empty for now.
    nothing
end

end # module GraphDigitizer

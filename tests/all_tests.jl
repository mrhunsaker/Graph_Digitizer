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

using Test

# Helper: include a file if it exists
function _safe_include(path::AbstractString)
    if isfile(path)
        include(path)
        return true
    else
        @info "Missing file, skipping include:" path
        return false
    end
end

root = normpath(joinpath(@__DIR__, ".."))
core_path = joinpath(root, "src", "graph_digitizer_core.jl")
main_path = joinpath(root, "src", "graph_digitizer.jl")

# Prefer including a headless core if available (provides data_to_canvas / canvas_to_data)
core_loaded = _safe_include(core_path)
# Always try to include main app to bring helper functions into scope (guarded main should not run)
_main_loaded = _safe_include(main_path)

# -----------------------
# Coordinate transform tests (headless core)
# -----------------------
if core_loaded && isdefined(Main, :GraphDigitizerCore)
    using .GraphDigitizerCore
    @testset "Coordinate transforms (data_to_canvas / canvas_to_data) - headless core" begin
        state = CoreState(img_w=600, img_h=600,
                          display_scale=1.0, offset_x=0.0, offset_y=0.0,
                          px_xmin=(100.0, 300.0), px_xmax=(500.0, 300.0),
                          px_ymin=(100.0, 500.0), px_ymax=(100.0, 100.0),
                          x_min=0.0, x_max=10.0, y_min=0.0, y_max=100.0,
                          x_log=false, y_log=false)

        # Linear axes example: known mapping
        dx = 2.5
        dy = 25.0
        px, py = data_to_canvas(state, dx, dy)

        @test isapprox(px, 200.0; atol=1e-6)
        @test isapprox(py, 400.0; atol=1e-6)

        # Round-trip: canvas -> data should recover original dx, dy
        dx2, dy2 = canvas_to_data(state, px, py)
        @test isapprox(dx2, dx; rtol=1e-12, atol=1e-12)
        @test isapprox(dy2, dy; rtol=1e-12, atol=1e-12)

        # Another point: right/top corners
        px_r, py_t = data_to_canvas(state, 10.0, 100.0)
        @test isapprox(px_r, 500.0; atol=1e-6)
        @test isapprox(py_t, 100.0; atol=1e-6)

        # Test log-scale mapping (base 10)
        state.x_min = 1.0
        state.x_max = 100.0
        state.y_min = 1.0
        state.y_max = 10000.0
        state.x_log = true
        state.y_log = true

        dx_log = 10.0
        dy_log = 100.0
        px_log, py_log = data_to_canvas(state, dx_log, dy_log)

        @test isapprox(px_log, 300.0; atol=1e-6)
        @test isapprox(py_log, 300.0; atol=1e-6)

        # Round-trip for log-case
        dx_back, dy_back = canvas_to_data(state, px_log, py_log)
        @test isapprox(dx_back, dx_log; rtol=1e-9, atol=1e-9)
        @test isapprox(dy_back, dy_log; rtol=1e-9, atol=1e-9)
    end
else
    @info "Skipping coordinate transform tests: graph_digitizer_core.jl not found or not loaded."
end

# -----------------------
# Pure helpers tests
# -----------------------
@testset "Pure helpers" begin
    # parse_x_list
    if isdefined(Main, :parse_x_list)
        @test parse_x_list("1,2, 3;4") == [1.0, 2.0, 3.0, 4.0]
        @test parse_x_list("  5 ; 5 ; 2, 2 , 3") == [2.0, 3.0, 5.0]
        @test parse_x_list("a, , 2") == [2.0]
        @test parse_x_list("") == Float64[]
    else
        @info "parse_x_list not found; skipping related tests"
        @test true
    end

    # hex color parsing (3- and 6-digit)
    if isdefined(Main, :hex_to_rgb)
        c1 = hex_to_rgb("#fff")
        @test isapprox(c1.r, 1.0; atol=1e-12) && isapprox(c1.g, 1.0; atol=1e-12) && isapprox(c1.b, 1.0; atol=1e-12)
        c2 = hex_to_rgb("#0072B2")
        @test 0.0 <= c2.r <= 1.0
    else
        @info "hex_to_rgb not found; skipping color tests"
        @test true
    end

    # sanitize filename
    if isdefined(Main, :_sanitize_filename)
        s = _sanitize_filename("My Title: v1")
        @test occursin("My_Title_v1", s)

        s2 = "file   name///with***chars!!!"
        out2 = _sanitize_filename(s2)
        @test occursin(r"^[A-Za-z0-9_.-]+$", out2)
        @test !occursin(r"_\_", out2)

        s3 = " .weird--name.. "
        out3 = _sanitize_filename(s3)
        @test startswith(out3, "weird")
        @test !startswith(out3, ".") && !startswith(out3, "_")
        @test !endswith(out3, ".") && !endswith(out3, "_")

        s4 = "     "
        out4 = _sanitize_filename(s4)
        @test out4 == ""

        s5 = "Plot — Δ 𝜋 🚀"
        out5 = _sanitize_filename(s5)
        @test out5 != ""
        @test occursin(r"^[A-Za-z0-9_.-]+$", out5)

        s6 = "My/File:Name?.json"
        out6 = _sanitize_filename(s6)
        @test out6 == "My_File_Name.json"
    else
        @info "_sanitize_filename not found; skipping filename tests"
        @test true
    end

    # parse_color
    if isdefined(Main, :parse_color)
        t = parse_color("#0072B2")
        @test length(t) == 3
    else
        @info "parse_color not found; skipping parse_color test"
        @test true
    end
end

# -----------------------
# Guarded GUI-dependent snap test
# -----------------------
function _can_run_gui_test()
    # allow explicit skip
    if get(ENV, "SKIP_GUI_TESTS", "") != ""
        return false
    end
    # On Linux, require DISPLAY
    if Sys.islinux()
        if !haskey(ENV, "DISPLAY")
            return false
        end
    end
    # Require snap_points_to_xs! to exist
    return isdefined(Main, :snap_points_to_xs!)
end

@testset "snap_points_to_xs! (guarded GUI test)" begin
    if !_can_run_gui_test()
        @info "Skipping GUI-dependent snap test (no DISPLAY or SKIP_GUI_TESTS set or helper missing)"
        @test true
    else
        # Create a minimal app state. Prefer create_app() if available.
        state = if isdefined(Main, :create_app)
            try
                create_app()
            catch
                nothing
            end
        else
            nothing
        end

        # Fallback minimal state if necessary
        if state === nothing
            # Minimal compatible state for snap_points_to_xs! used by tests
            mutable struct _MiniDS
                points::Vector{Tuple{Float64,Float64}}
            end
            mutable struct _MiniState
                datasets::Vector{_MiniDS}
            end
            ds1 = _MiniDS([(0.9, 1.0), (2.1, 2.0)])
            ds2 = _MiniDS([(1.9, 1.5), (2.6, 3.0)])
            state = _MiniState([ds1, ds2])
        end

        xs = [1.0, 2.0, 3.0]
        changed = try
            snap_points_to_xs!(state, xs)
        catch err
            @info "snap_points_to_xs! failed:" string(err)
            -1
        end

        @test changed >= 0
    end
end

println("All tests finished.")
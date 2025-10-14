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

# Graph_Digitizer/test/runtests.jl
#
# Unit tests for core utilities:
# - data_to_canvas / canvas_to_data (linear and log scales, round-trip)
# - _sanitize_filename
#
# This test file includes the library source (safe because the main loop is guarded)
# and creates an application state via `create_app()` for exercising the coordinate
# transforms. The GUI window is not shown by the tests.
using Test

# Include the headless core library so tests can run without creating GTK windows.
# The core module provides pure transforms and filename helpers used by the GUI.
include(joinpath(@__DIR__, "..", "src", "graph_digitizer_core.jl"))
using .GraphDigitizerCore

@testset "Coordinate transforms (data_to_canvas / canvas_to_data) - headless core" begin
    # Use the headless CoreState from GraphDigitizerCore so tests do not require GTK.
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
    # Configure numeric ranges for logs and pick a value with known log position
    # e.g., x_min=1, x_max=100, x=10 -> t = 1/2 -> px midpoint 300
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

@testset "Filename sanitizer (_sanitize_filename) - headless core" begin
    # Basic substitutions
    s1 = "My Graph: Title (v1)"
    out1 = _sanitize_filename(s1)
    @test out1 == "My_Graph_Title_v1"

    # Collapse repeated punctuation/spaces
    s2 = "file   name///with***chars!!!"
    out2 = _sanitize_filename(s2)
    # expect only allowed characters and no repeated underscores
    @test occursin(r"^[A-Za-z0-9_.-]+$", out2)
    @test !occursin(r"_\_", out2)  # no double underscores (collapsed)

    # Preserve dots and dashes but trim leading/trailing dots/underscores
    s3 = " .weird--name.. "
    out3 = _sanitize_filename(s3)
    @test startswith(out3, "weird")
    @test !startswith(out3, ".") && !startswith(out3, "_")
    @test !endswith(out3, ".") && !endswith(out3, "_")

    # Empty or whitespace-only input returns empty string
    s4 = "     "
    out4 = _sanitize_filename(s4)
    @test out4 == ""

    # Unicode and emoji sanitized to underscores (non-ASCII replaced)
    s5 = "Plot — Δ 𝜋 🚀"
    out5 = _sanitize_filename(s5)
    @test out5 != ""  # should not be empty, should be sanitized
    @test occursin(r"^[A-Za-z0-9_.-]+$", out5)

    # Known transformation example
    s6 = "My/File:Name?.json"
    out6 = _sanitize_filename(s6)
    @test out6 == "My_File_Name.json"
end

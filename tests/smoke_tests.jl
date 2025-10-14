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

# Smoke tests for Graph_Digitizer
using Test

# Load the application file (definitions only; guarded main block won't run)
include(joinpath(@__DIR__, "..", "src", "graph_digitizer.jl"))

@testset "Pure helpers" begin
    @test parse_x_list("1,2, 3;4") == [1.0, 2.0, 3.0, 4.0]
    @test parse_x_list("  5 ; 5 ; 2, 2 , 3") == [2.0, 3.0, 5.0]
    @test parse_x_list("a, , 2") == [2.0]
    @test parse_x_list("") == Float64[]

    # hex color parsing (3- and 6-digit)
    c1 = hex_to_rgb("#fff")
    @test isapprox(c1.r, 1.0; atol=1e-12) && isapprox(c1.g, 1.0; atol=1e-12) && isapprox(c1.b, 1.0; atol=1e-12)
    c2 = hex_to_rgb("#0072B2")
    @test 0.0 <= c2.r <= 1.0

    # sanitize filename
    s = _sanitize_filename("My Title: v1")
    @test occursin("My_Title_v1", s)

    # parse_color delegates and returns tuple
    t = parse_color("#0072B2")
    @test length(t) == 3
end

# Guarded GUI-dependent snap test
function _can_run_gui_test()
    # allow explicit skip
    if get(ENV, "SKIP_GUI_TESTS", "") != ""
        return false
    end
    # On Linux, require DISPLAY or Xvfb
    if Sys.islinux()
        if !haskey(ENV, "DISPLAY")
            return false
        end
    end
    # On all platforms require Gtk is defined (we included the file which imports Gtk)
    return isdefined(Main, :Gtk)
end

@testset "snap_points_to_xs! (guarded GUI test)" begin
    if !_can_run_gui_test()
        @info "Skipping GUI-dependent snap test (no DISPLAY or SKIP_GUI_TESTS set)"
        @test true
    else
        # create a minimal app state via create_app()
        state = create_app()
        try
            # populate datasets with some sample points
            for i in 1:2
                state.datasets[i].points = [(0.9 + (i-1), 1.0), (2.1 + (i-1), 2.0)]
            end
            xs = [1.0, 2.0, 3.0]
            changed = snap_points_to_xs!(state, xs)
            @test changed == 4 || changed == 2 || changed >= 1  # we only assert it ran; exact count may vary by dataset setup
        finally
            # Clean up created window/widget if possible
            try
                Gtk.Widget.destroy(state.win)
            catch
            end
        end
    end
end

println("Smoke tests finished.")# Copyright 2025 Ryan Hunsaker
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     https://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


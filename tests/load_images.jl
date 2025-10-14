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

# Simple guarded loader test — attempts to load images in tests/samples or tests/data
using FileIO, Test

root = normpath(joinpath(@__DIR__, ".."))
candidates = String[]
for dir in ["tests/samples", "tests/data", "tests"]
    d = joinpath(root, dir)
    if isdir(d)
        for ext in ["png","jpg","jpeg","bmp","tif","tiff","webp"]
            for f in sort(readdir(d; join=true))
                if endswith(lowercase(f), "." * ext)
                    push!(candidates, f)
                end
            end
        end
    end
end

if isempty(candidates)
    @info "No sample images found under tests/ — skipping load tests. To run, add sample images under tests/samples or tests/data."
    @test true
else
    @testset "Load image formats" begin
        for f in candidates
            @info "Attempting to load: $f"
            try
                img = load(f)
                @test !isempty(size(img))
                @info "Loaded OK: $f size=$(size(img))"
            catch e
                @warn "Failed to load $f: $e"
                @test false
            end
        end
    end
end

println("load_images.jl finished.")# Copyright 2025 Ryan Hunsaker
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


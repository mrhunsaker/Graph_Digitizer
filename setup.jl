#!/usr/bin/env julia

import Pkg

println("Activating project and instantiating dependencies...")
Pkg.activate(".")
Pkg.instantiate()
Pkg.precompile()

println("Done. You can now run src/graph_digitizer.jl")

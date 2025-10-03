# Graph_Digitizer/scripts/fix_gd_main_loop.jl
#
# Small fixer script that corrects a malformed catch block at the end of
# `src/graph_digitizer.jl` where backslashes/escape sequences replaced quoting,
# causing a Julia ParseError. The script:
#
# - backs up the original file to `src/graph_digitizer.jl.bak.<timestamp>`
# - searches for the broken `catch e ... rethrow(e) end end` tail using a
#   robust regex (single-line / DOTALL) and replaces it with a clean, well-formed
#   catch block.
# - prints what it did (patched / nothing found / errors).
#
# Usage:
#   julia --project=@. scripts/fix_gd_main_loop.jl
#
# NOTE: This script makes a textual substitution and is deliberately conservative:
# it only replaces when it finds a matching malformed catch/rethrow tail near the
# end of the file. Always review the backup created if you want to inspect/restore.

using Dates

const SRC = joinpath(@__DIR__, "..", "src", "graph_digitizer.jl") |> normpath

function now_timestamp()
    return Dates.format(Dates.now(), "yyyyMMdd_HHMMSS")
end

function make_backup(path::AbstractString)
    bak = path * ".bak." * now_timestamp()
    try
        cp(path, bak; force=true)
        println("Backup written to: ", bak)
        return bak
    catch e
        println("Warning: failed to write backup: ", e)
        return nothing
    end
end

function read_source(path::AbstractString)
    try
        s = read(path, String)
        return s
    catch e
        error("Failed to read source file '$(path)': $(e)")
    end
end

function write_source(path::AbstractString, content::String)
    try
        open(path, "w") do io
            write(io, content)
        end
        println("Wrote patched file: ", path)
    catch e
        error("Failed to write patched file '$(path)': $(e)")
    end
end

function fix_malformed_catch_block!(path::AbstractString)
    s = read_source(path)

    # Canonical replacement block (well-formed)
    good_block = """
    catch e
        @error \"Failed while showing window or running GTK main loop\" exception = (e, catch_backtrace())
        println(\"ERROR: Failed to start GraphDigitizer: \", e)
        rethrow(e)
    end
end
"""

    # Primary regex: match a `catch e` ... `rethrow(e)` tail near EOF (DOTALL / non-greedy).
    # This will capture the broken block even if quotes/backslashes were mangled.
    rx_primary = Regex("(?s)catch\\s+e.*?rethrow\\(e\\)\\s*end\\s*end\\s*$")

    # Secondary, more permissive regex that looks for a catch block containing
    # the words "Failed while showing window" or an escaped ERROR token; used
    # if primary didn't match.
    rx_secondary = Regex("(?s)catch\\s+e.*?(Failed while showing window|Failed to start GraphDigitizer|\\\\ERROR: Failed to start).*?rethrow\\(e\\)\\s*end\\s*end\\s*$")

    if occursin(rx_primary, s)
        println("Detected malformed final catch/rethrow block (primary pattern).")
        bak = make_backup(path)
        s2 = replace(s, rx_primary => good_block)
        write_source(path, s2)
        println("Patch applied (primary). Please run julia --project=@. src/graph_digitizer.jl to verify.")
        return true
    elseif occursin(rx_secondary, s)
        println("Detected malformed final catch/rethrow block (secondary pattern).")
        bak = make_backup(path)
        s2 = replace(s, rx_secondary => good_block)
        write_source(path, s2)
        println("Patch applied (secondary). Please run julia --project=@. src/graph_digitizer.jl to verify.")
        return true
    else
        println("No matching malformed catch block found at end of file. No changes made.")
        return false
    end
end

# --- main execution ---
try
    if !isfile(SRC)
        println("Source file not found: ", SRC)
        exit(2)
    end

    ok = fix_malformed_catch_block!(SRC)
    if ok
        println("fix_gd_main_loop.jl: completed successfully.")
        exit(0)
    else
        println("fix_gd_main_loop.jl: no modifications required.")
        exit(0)
    end
catch e
    println("Error while running fixer: ", e)
    println("Backtrace:")
    showerror(stdout, e, catch_backtrace())
    exit(1)
end

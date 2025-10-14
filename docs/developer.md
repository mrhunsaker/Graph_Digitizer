# Graph_Digitizer — Developer Guide

This document helps developers understand, extend, and test Graph_Digitizer.

## Project layout

- src/graph_digitizer.jl — single-file application implementation (UI, helpers, I/O).
- docs/ — user & developer documentation.
- tests/ — smoke tests and quick verification scripts.
- README.md — user-facing quickstart, auto-generated if missing.

## High-level architecture

- Single-file app structured into sections:
  - Constants & Types
  - Utilities
  - Drawing / transforms / auto-trace
  - I/O helpers
  - Dialog helpers
  - App creation (`create_app()`) and top-level run guard
- `AppState` holds all runtime data. Many helpers accept `AppState` to operate on current state.

## Key extension points

- UI: `create_app()` builds and returns `AppState`. You can call `create_app()` programmatically in tests or to embed the UI.
- Drawing: `draw_canvas(state, cr)` accepts a Cairo context and can be reused/extended for alternate rendering.
- Auto-trace: `auto_trace_scan(state, target_rgb)` returns sampled points and can be reused in headless analysis pipelines (requires `state.image` and calibration).
- Snap Xs flow: `parse_x_list(txt)` parses user X lists; `snap_points_to_xs!(state, xs)` performs snapping.

## Coding & style guidelines

- Keep functions small and focused. The project currently uses plain functions rather than modules.
- Defensive programming: many helpers use try/catch and best-effort fallbacks to remain cross-platform.
- Use docstrings for exported helpers. Keep docstrings concise and include arguments/returns.
- Tests should prefer pure helpers (parsing, sanitization, color parsing) where possible. GUI-dependent tests are provided but guarded.

## Development workflow

- Use the project environment:
  - PowerShell:

    ```powershell
    julia --project=@. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
    ```

- Run the app locally:

  ```bash
  julia --project=@. src/graph_digitizer.jl
  ```

- Iterative development:
  - Edit `src/graph_digitizer.jl` (it contains most of the code).
  - Use the smoke tests in `tests/` to validate changes quickly.

## Debugging tips

- The top-level guard prevents automatic GUI launch when the file is included. Use `include("src/graph_digitizer.jl")` from a REPL or test file to load definitions without running the main loop.
- Use the `ensure_readme()` helper to regenerate README when debugging help UI.
- Many operations update `state.status_label` — check this text for user-visible diagnostics.
- If Gtk fails to start on CI/headless systems, guard GUI tests or run with a virtual framebuffer (Xvfb) on Linux. On Windows ensure Gtk build succeeded earlier.

## Tests & CI

- `tests/smoke_tests.jl` contains lightweight smoke tests for pure helpers and a guarded GUI snap test.
- Running tests:
  - PowerShell:

    ```powershell
    julia --project=@. tests/smoke_tests.jl
    ```

- In CI:
  - Prefer running only pure helper tests on headless runners or run GUI tests behind a feature flag.
  - Ensure `Pkg.instantiate()` is executed before tests.

## Contributing

- Fork → branch → PR against `main`.
- Provide unit/smoke test(s) for functional changes.
- Keep changes backwards-compatible where possible (existing tool flow depends on the current `AppState` layout).

## Future improvements (ideas)

- Split the monolithic file into modules under `src/` (ui/, io/, core/).
- Add proper unit tests with small module boundaries that avoid Gtk dependencies.
- Add linting (JuliaFormatter.jl) and pre-commit hooks for consistent style.
- Add a CI matrix that runs GUI tests on a Windows runner with Gtk installed.
<!--
 Copyright 2025 Ryan Hunsaker
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
     https://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
-->

# Smoke Tests — Graph_Digitizer

This document describes the smoke tests and how to run them.

## Purpose

Smoke tests quickly verify basic correctness of pure helpers and a small end-to-end snap workflow (guarded). They are not a full unit test suite but useful for CI or local validation.

## What is tested

- parse_x_list: token parsing, deduplication, sorting
- hex_to_rgb: hex color parsing (3- and 6-digit forms)
- _sanitize_filename: filename sanitization rules
- snap_points_to_xs!: basic snap behavior (guarded GUI test that creates an AppState)

## Running the tests

From repository root (PowerShell recommended):

```powershell
julia --project=@. tests/smoke_tests.jl
```

Behavior:

- Pure helper tests will always run.
- The snap/GUI test will run when Gtk is available and when not running on a clearly headless *nix environment without DISPLAY (test contains guards). On Windows it will attempt to run if Gtk is installed.

## CI recommendations

- Install package dependencies via `Pkg.instantiate()` on the runner.
- For headless Linux runners either:
  - Run only the pure helper tests.
  - Or run the GUI test within an Xvfb session.

## Troubleshooting

- If tests fail with Gtk errors, either ensure Gtk is installed in the environment or skip GUI tests by setting `SKIP_GUI_TESTS=1` in the environment before running tests:
  - PowerShell:

    ```powershell
    $env:SKIP_GUI_TESTS = "1"
    julia --project=@. tests/smoke_tests.jl
    ```

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

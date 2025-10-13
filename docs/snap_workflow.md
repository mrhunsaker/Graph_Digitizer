# Snap X Workflow

This document describes the new "Snap Xs" workflow (Place Snap Lines + Snap Datapoints to X).

## Overview

You can provide a list of X coordinates (comma- or semicolon-separated) and:

- Place vertical stippled guide lines at those X values (visual aids).
- Snap all datapoints across all datasets to the nearest provided X value.

Both actions are separate:

1. Enter the X list in the "Snap Xs:" entry (e.g. `0, 1, 2.5, 4`).
2. Click **Place Snap Lines** to show vertical guides on the canvas. Calibration must be applied for the lines to map properly onto the image.
3. Click **Snap Datapoints to X** to snap every dataset point's X coordinate to the nearest X value from the list (Y preserved).

## Input format

- Accepts comma or semicolon separators.
- Whitespace is ignored.
- Invalid tokens are ignored.
- Duplicate values are deduplicated and sorted.

Examples:

- `0,1,2.5,4`
- `0; 1; 2.5; 4`

## Behavior & Notes

- Guide line placement requires calibration anchors (calibration clicks + numeric ranges applied).
- Snapping does not change Y values.
- Snapping operates on all datasets (global action).
- If you want snapping only when within a maximum delta, adjust the code in `snap_points_to_xs!` to add a tolerance check (not applied by default).
- Status messages appear in the app status bar indicating number of lines placed and number of points snapped.

## Troubleshooting

- If guide lines are not visible: ensure calibration has been applied (use Calibrate Clicks + Apply Calibration).
- If no points are snapped: verify the provided X list contains valid numbers and that dataset points are within range.
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

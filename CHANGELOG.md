# Changelog

All notable changes to this project are documented in this file.

The format follows a short, human-friendly summary of what changed and why. This entry consolidates recent documentation-focused edits and the version bump to v1.0.0.

---

## [1.0.0] - 2025-10-03

### Summary
This release is primarily a documentation and metadata refresh to prepare the project for the 1.0.0 milestone. It standardizes platform guidance for Windows and Linux, clarifies save/chooser fallbacks, and updates version metadata used by the runtime and package manifest.

### Changed
- Project metadata
  - `Project.toml` version updated from `0.9.0` → `1.0.0`.
  - Runtime constant `APP_VERSION` updated to `1.0.0` in `src/graph_digitizer.jl`.
  - README and example README now reference the packaged version `1.0.0`.
- Documentation updates (user-facing and developer docs)
  - `README.md`
    - Explicitly states the project/docs are aimed at Windows and Linux.
    - Reworded installation notes to call out Linux system GTK packages and Windows prebuilt binaries (removed macOS-specific guidance).
    - Standardised shortcut phrasing to reference `Ctrl`/`Primary` for Windows and Linux.
    - Clarified fallback save behavior (Downloads folder or system temp) and that the status label is updated with the fallback path.
  - `examples/assets/sample_README.md`
    - Brought into alignment with main README (Windows/Linux emphasis).
  - `docs/API_REFERENCE.md`, `docs/utilities.md`, `docs/types.md`, `docs/functions_data_transforms.md`
    - Updated platform notes and wording to explicitly emphasize Windows and Linux behavior where platform-specific caveats appear (file chooser fallbacks, GTK runtime availability, Downloads-folder fallback, accelerator behavior).
    - Clarified safe dialog behavior when native file choosers are unavailable (prefer Downloads on Windows/Linux; system temp as fallback).
- Source comments and inline help
  - `src/graph_digitizer.jl`
    - Updated inline README generator (`ensure_readme`) content to reference `Primary+S` as `Ctrl+S` on Windows/Linux where appropriate.
    - Modified some help text strings to reflect Windows/Linux guidance.
    - Minor code comments updated to match the docs changes.
- New project file
  - `CHANGELOG.md` (this file) added to record the version bump and documentation changes.

### Fixed / Improved
- Documentation consistency:
  - Removed mixed references to macOS-specific shortcuts and clarified the platform behavior to prioritize Windows and Linux.
  - Ensured "safe save" and "safe open" dialog descriptions are explicit about Downloads vs temp fallback behavior on Windows/Linux.
  - Strengthened wording around GTK runtime requirements for Linux distributions (advice to install distribution packages) and Windows (prebuilt binaries with Gtk.jl).
- Developer docs:
  - API reference and function-level docs now state that examples and platform notes are oriented toward Windows and Linux.

### Notes for users & developers
- If you use the Julia environment pinned here:
  - Run the following from the repository root to instantiate the environment:
    - `julia --project=@. -e 'using Pkg; Pkg.instantiate()'`
  - Launch the application from the project root:
    - `julia --project=@. src/graph_digitizer.jl`
  - Keep the launching terminal open for diagnostic messages; the application prints status messages, fallback save paths, and startup diagnostics to stdout/stderr.
- GTK on Linux:
  - Gtk.jl often requires system GTK libraries. On Debian/Ubuntu-based distros install packages like `libgtk-3-dev` or the distro-equivalent GTK runtime packages before using Gtk.jl.
- GTK on Windows:
  - Gtk.jl typically uses prebuilt GTK binaries; follow Gtk.jl's installation guidance for Windows if you encounter issues.
- Shortcuts:
  - Primary key binding is `Ctrl` on Windows and Linux in the UI and documentation. If you are using a platform that maps Primary to another modifier, consult your environment.
- Save fallback behavior:
  - When a native file chooser dialog cannot be constructed (various Gtk.jl / environment combinations), the application will attempt to write to your `Downloads` folder on Windows and Linux. If that is not available, it will fall back to the system temporary directory. The full path used is shown in the app's status label.

### Credits
- Documentation, wording and metadata updates performed by the repository maintainer(s).

---

If you want, I can:
- Add more granular changelog history prior to v1.0.0 (import previous release notes or derive entries from git history).
- Produce a release checklist (packaging, tagging, CI tasks) for making an official 1.0.0 release (git tag and optional GitHub release notes).
- Generate a small "Windows/Linux setup" HOWTO snippet (copyable commands) for common distributions (Ubuntu/Debian/Fedora) and Windows (MSYS2/Chocolatey), to include in docs or README.

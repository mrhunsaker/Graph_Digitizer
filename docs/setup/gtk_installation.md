# GTK Installation & Setup (Windows and Linux)
This document provides a concise, practical HOWTO for installing the GTK runtime and getting `Gtk.jl` working with the GraphDigitizer application on Windows and common Linux distributions. It focuses on the environment and steps necessary so that `using Gtk` in Julia succeeds and the GUI can be launched.

Contents
- Overview and prerequisites
- Quick verification (Julia smoke-test)
- Linux: Ubuntu/Debian, Fedora, Arch (commands)
- Windows: MSYS2 (recommended) and notes on Chocolatey
- Building / fixing `Gtk.jl` from Julia (Pkg steps)
- Troubleshooting tips and common pitfalls

---

## Overview & prerequisites
- GraphDigitizer uses `Gtk.jl` to provide its GUI. On Linux you generally need system GTK runtime and development libraries installed. On Windows the recommended route is MSYS2 (preferred by `Gtk.jl`) or a compatible GTK runtime.
- Ensure you are running a 64-bit Julia that matches the system/runtime you install (64-bit Julia with 64-bit GTK runtime).
- Always run Julia with the project environment before running the app:
  - From repository root: `julia --project=@. -e 'using Pkg; Pkg.instantiate()'`

---

## Quick verification (Julia smoke-test)
After installing system GTK libraries, verify from a Julia REPL that Gtk can be loaded.

Example manual test (this will attempt to create a simple window — run from an interactive terminal):
```/dev/null/julia_smoke_test.jl#L1-6
using Gtk
# Minimal interactive test (you'll need a graphical session)
win = GtkWindow("GTK test", 300, 120)
label = GtkLabel("GTK loaded successfully")
push!(win, label)
Gtk.showall(win)
# In many setups, call Gtk.main() to start the GUI loop.
```

If `using Gtk` errors, see the Troubleshooting section below.

---

## Linux installation (common distributions)

Important: choose the set of packages appropriate to the GTK version you need. `Gtk.jl` historically works with GTK3 and has increasing GTK4 support; installing GTK3 dev/runtime is commonly sufficient.

### Ubuntu / Debian (GTK3)
```/dev/null/ubuntu_install.sh#L1-6
sudo apt update
sudo apt install -y build-essential pkg-config libgtk-3-dev libgirepository1.0-dev
# Optional helpful packages
sudo apt install -y libpango1.0-dev libglib2.0-dev libgdk-pixbuf2.0-dev
```

If you prefer GTK4 (and your `Gtk.jl` binding supports it), install `libgtk-4-dev` instead:
```/dev/null/ubuntu_install_gtk4.sh#L1-3
sudo apt install -y libgtk-4-dev libgirepository1.0-dev
```

### Fedora (GTK3)
```/dev/null/fedora_install.sh#L1-5
sudo dnf install -y @development-tools pkgconfig gtk3-devel gobject-introspection-devel
# Optional
sudo dnf install -y cairo-devel pango-devel glib2-devel
```

### Arch Linux / Manjaro
```/dev/null/arch_install.sh#L1-4
sudo pacman -Syu
sudo pacman -S --needed base-devel gtk3 gobject-introspection
# For GTK4:
# sudo pacman -S --needed gtk4
```

Notes:
- Installing `libgirepository1.0-dev` / `gobject-introspection` is helpful because some Julia packages may build against GObject Introspection data.
- After installing system packages, re-open your terminal/IDE so environment changes take effect.

---

## Windows installation (MSYS2 recommended)
MSYS2 is the recommended method because it provides a native package manager (`pacman`) and the Mingw-w64 toolchains Gtk.jl expects.

1. Install MSYS2:
   - Download and install from https://www.msys2.org/
   - Follow the MSYS2 instructions to update core packages (`pacman -Syu`) and restart the MSYS2 shell as needed.

2. From the MSYS2 MinGW 64-bit shell run:
```/dev/null/msys2_mingw_install.sh#L1-8
# Update package databases & core system
pacman -Syu
# (restart shell if required)
# Install Mingw-w64 GTK3 runtime & common dependencies (64-bit)
pacman -S --needed mingw-w64-x86_64-gtk3 mingw-w64-x86_64-cairo \
  mingw-w64-x86_64-pango mingw-w64-x86_64-atk mingw-w64-x86_64-gdk-pixbuf2 \
  mingw-w64-x86_64-glib2
```

3. Ensure the MinGW64 runtime `bin` directory is on your PATH for the environment where you run Julia. For example, add (replace MSYS2 install path as appropriate):
```/dev/null/windows_path_example.ps1#L1-3
# Example PowerShell (temporary for current session)
$env:PATH = "C:\msys64\mingw64\bin;" + $env:PATH
# Start Julia from this same shell/session so PATH is visible.
```

4. Start Julia from the same shell (or ensure PATH is updated globally) and `using Gtk` in the REPL to verify.

Alternative: Chocolatey or other runtimes
- Some users attempt to use Chocolatey packages or GTK binary bundles. These can work but are less tested with `Gtk.jl`. If you encounter problems, MSYS2 is the most reliable approach.

---

## Building / fixing Gtk.jl in Julia
From the repository root in a Julia REPL:
```/dev/null/julia_pkg_steps.jl#L1-6
using Pkg
Pkg.instantiate()   # install dependencies from Project/Manifest
# If Gtk.jl needs build steps:
Pkg.build("Gtk")
# Then test:
using Gtk
```

If `Pkg.build("Gtk")` reports missing system libraries, install the appropriate system GTK packages per the Linux or Windows sections above and run `Pkg.build("Gtk")` again.

---

## Troubleshooting & common pitfalls

- "using Gtk" fails with missing shared library (e.g. cannot find libgtk-3.so or libgtk-3-0):
  - On Linux, install `libgtk-3-dev` / `libgtk-3-0` (or `libgtk-4-dev` if using GTK4).
  - On Windows, ensure MSYS2 `mingw64\bin` is on PATH and you started Julia from an environment that can see those DLLs.

- 32-bit vs 64-bit mismatch:
  - Ensure your Julia installation architecture (64-bit) matches the GTK runtime you installed (mingw-w64 64-bit).

- Headless / CI environments:
  - Running graphical apps requires an X11/Wayland display. In headless CI, either skip GUI tests or use a virtual framebuffer (Xvfb) on Linux.
  - On Windows, a graphical session is required.

- File chooser dialogs failing to display:
  - Some desktop environments and Gtk.jl versions may require additional desktop packages. The application provides safe-save fallbacks to write to `~/Downloads` (or the system temporary directory) when a native dialog cannot be created — check the status label for fallback file paths.

- If you see errors about GObject Introspection or GIR files:
  - Install `libgirepository1.0-dev` / `gobject-introspection` on Linux or the equivalent MSYS2 packages on Windows.

- If a package (e.g. ImageIO) fails to build because of missing `pkg-config` or related headers:
  - Install `pkg-config` and the required `-dev` packages for the dependency (e.g., libpng-dev, libjpeg-dev).

---

## Additional recommendations
- Restart your terminal, IDE (VS Code, Juno), or the OS after major system library installs to ensure PATH and library caches refresh.
- For reproducibility, always run the app using the repo's project environment:
  - `julia --project=@. src/graph_digitizer.jl`
- If you still have trouble, capture the full Julia stack trace when `using Gtk` fails and open an issue with:
  - OS and distribution + version
  - Julia version
  - Exact error message / stack trace
  - Whether you used MSYS2 / apt / dnf / pacman and which GTK package versions you installed

---

If you want, I can add short, copy-paste sections for specific Linux distributions not covered above, or provide a short PowerShell script that updates PATH for MSYS2 and launches Julia from the correct environment.
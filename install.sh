#!/usr/bin/env bash
#
# RedControl installer — checks dependencies (incl. umr), sets up the launcher,
# and gets you from a fresh clone to a working app. Safe: it asks before it
# installs anything and never runs silent sudo.
#
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- pretty output ----------------------------------------------------------
if [ -t 1 ]; then B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; C=$'\e[36m'; N=$'\e[0m'
else B=""; G=""; Y=""; R=""; C=""; N=""; fi
say()  { printf "%s\n" "$*"; }
ok()   { printf "%s✓%s %s\n" "$G" "$N" "$*"; }
warn() { printf "%s!%s %s\n" "$Y" "$N" "$*"; }
err()  { printf "%s✗%s %s\n" "$R" "$N" "$*"; }
head() { printf "\n%s%s%s\n" "$B$C" "$*" "$N"; }
ask()  { local a; read -r -p "$1 [y/N] " a; [[ "$a" =~ ^[Yy]$ ]]; }

head "RedControl installer"
say  "Folder: $HERE"

# ---- distro detection -------------------------------------------------------
DISTRO="unknown"; PM=""
if [ -r /etc/os-release ]; then . /etc/os-release; DISTRO="${ID:-unknown}"; fi
case "$DISTRO" in
  arch|cachyos|endeavouros|manjaro) PM="pacman" ;;
  debian|ubuntu|pop|linuxmint|elementary) PM="apt" ;;
  fedora|rhel|centos|nobara) PM="dnf" ;;
esac
say "Detected: ${DISTRO} (${PM:-no known package manager})"

# ---- 1. Python + Tkinter ----------------------------------------------------
head "1. Python & Tkinter"
if command -v python3 >/dev/null 2>&1; then ok "python3: $(python3 --version 2>&1)"
else err "python3 not found — install Python 3 first."; exit 1; fi
if python3 -c "import tkinter" 2>/dev/null; then ok "tkinter present"
else
  warn "tkinter (python3-tk) is missing — the GUI needs it."
  case "$PM" in
    pacman) say "  Install with: sudo pacman -S tk" ;;
    apt)    say "  Install with: sudo apt install python3-tk" ;;
    dnf)    say "  Install with: sudo dnf install python3-tkinter" ;;
    *)      say "  Install your distro's python3-tk / tk package." ;;
  esac
fi

# ---- 2. umr (the core dependency) -------------------------------------------
head "2. umr (User Mode Register debugger — required)"
if command -v umr >/dev/null 2>&1; then
  ok "umr found: $(command -v umr)"
else
  warn "umr is NOT installed. RedControl cannot talk to the GPU without it."
  case "$PM" in
    pacman)
      if command -v yay >/dev/null 2>&1 || command -v paru >/dev/null 2>&1; then
        AUR=$(command -v yay || command -v paru)
        if ask "Install umr from the AUR with $(basename "$AUR")?"; then
          "$AUR" -S --needed umr-git && ok "umr installed" || err "AUR install failed — see manual steps below."
        fi
      else
        warn "No AUR helper (yay/paru) found."
        say  "  Install one, then: yay -S umr-git   (or build from source, below)"
      fi
      ;;
    apt|dnf)
      say "umr isn't in most $PM repos, so it's built from source (a few minutes)."
      if ask "Install build tools and compile umr now?"; then
        set -e
        if [ "$PM" = apt ]; then
          sudo apt update
          sudo apt install -y git cmake pkg-config libpciaccess-dev libdrm-dev \
               libncurses-dev libjson-c-dev bison flex
        else
          sudo dnf install -y git cmake pkgconf-pkg-config libpciaccess-devel libdrm-devel \
               ncurses-devel json-c-devel bison flex
        fi
        tmp="$(mktemp -d)"; git clone --depth 1 https://gitlab.freedesktop.org/tomstdenis/umr "$tmp/umr"
        cmake -S "$tmp/umr" -B "$tmp/umr/build"; make -C "$tmp/umr/build" -j"$(nproc)"
        sudo make -C "$tmp/umr/build" install; rm -rf "$tmp"
        set +e
        command -v umr >/dev/null 2>&1 && ok "umr installed" || err "Build finished but umr not on PATH."
      fi
      ;;
    *)
      warn "Unknown distro — build umr from source (see below)."
      ;;
  esac
  if ! command -v umr >/dev/null 2>&1; then
    say ""
    say "${B}Manual umr install:${N}"
    say "  git clone https://gitlab.freedesktop.org/tomstdenis/umr"
    say "  cd umr && cmake -S . -B build && make -C build -j && sudo make -C build install"
  fi
fi

# ---- 3. Optional niceties ---------------------------------------------------
head "3. Optional extras (nicer names, tray icon)"
if ask "Install optional Python extras (pystray, pillow) for the tray icon?"; then
  python3 -m pip install --user --upgrade pystray pillow 2>/dev/null && ok "extras installed" \
    || warn "pip install skipped/failed — the app still runs without the tray."
fi

# ---- 4. Desktop launcher + icon ---------------------------------------------
head "4. Menu launcher"
APPS="$HOME/.local/share/applications"; ICONS="$HOME/.local/share/icons"
mkdir -p "$APPS" "$ICONS"
chmod +x "$HERE/redcontrol.py" 2>/dev/null
[ -f "$HERE/redcontrol-icon.png" ] && cp "$HERE/redcontrol-icon.png" "$ICONS/redcontrol.png"
cat > "$APPS/redcontrol.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=RedControl
Comment=AMD display pipeline control (dithering, depth, DisplayPort signal)
Exec=python3 "$HERE/redcontrol.py"
Icon=$ICONS/redcontrol.png
Terminal=false
Categories=System;Settings;Utility;
EOF
update-desktop-database "$APPS" >/dev/null 2>&1
ok "Launcher installed — search 'RedControl' in your app menu."

# ---- done -------------------------------------------------------------------
head "Done"
if command -v umr >/dev/null 2>&1; then ok "All set."; else warn "Install umr (above) before RedControl can control the GPU."; fi
say "Run now with:  python3 \"$HERE/redcontrol.py\""
if ask "Launch RedControl now?"; then setsid python3 "$HERE/redcontrol.py" >/dev/null 2>&1 & fi

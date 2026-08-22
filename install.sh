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
have_tk() { python3 -c "import tkinter" 2>/dev/null; }
if have_tk; then ok "tkinter present"
else
  warn "tkinter (python3-tk) is missing — the GUI needs it."
  case "$PM" in
    pacman) TK_PKG="tk" ;;
    apt)    TK_PKG="python3-tk" ;;
    dnf)    TK_PKG="python3-tkinter" ;;
    *)      TK_PKG="" ;;
  esac
  if [ -n "$TK_PKG" ] && ask "Install $TK_PKG now?"; then
    case "$PM" in
      pacman) sudo pacman -S --needed "$TK_PKG" ;;
      apt)    sudo apt update && sudo apt install -y "$TK_PKG" ;;
      dnf)    sudo dnf install -y "$TK_PKG" ;;
    esac
  else
    case "$PM" in
      pacman) say "  Install with: sudo pacman -S tk" ;;
      apt)    say "  Install with: sudo apt install python3-tk" ;;
      dnf)    say "  Install with: sudo dnf install python3-tkinter" ;;
      *)      say "  Install your distro's python3-tk / tk package." ;;
    esac
  fi
  if have_tk; then ok "tkinter present"
  else err "tkinter still missing — RedControl cannot start without it."; fi
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
      say "RedControl only needs umr's register CLI, so the build skips the GUI and"
      say "LLVM disassembler (-DUMR_NO_GUI=ON -DUMR_NO_LLVM=ON) — far fewer dependencies."
      if ask "Install build tools and compile umr now?"; then
        deps_ok=1
        if [ "$PM" = apt ]; then
          sudo apt update \
            && sudo apt install -y git cmake build-essential pkg-config \
                 libpciaccess-dev libdrm-dev libncurses-dev \
            || deps_ok=0
        else
          sudo dnf install -y git cmake gcc gcc-c++ make pkgconf-pkg-config \
               libpciaccess-devel libdrm-devel ncurses-devel \
            || deps_ok=0
        fi
        if [ "$deps_ok" -eq 0 ]; then
          err "Package install failed — fix the errors above and re-run this script."
        else
          tmp="$(mktemp -d)"
          if git clone --depth 1 https://gitlab.freedesktop.org/tomstdenis/umr "$tmp/umr" \
             && cmake -S "$tmp/umr" -B "$tmp/umr/build" -DUMR_NO_GUI=ON -DUMR_NO_LLVM=ON \
             && make -C "$tmp/umr/build" -j"$(nproc)" \
             && sudo make -C "$tmp/umr/build" install; then
            ok "umr installed"
          else
            err "umr build failed — see the error above, or try the manual steps below."
          fi
          rm -rf "$tmp"
        fi
      fi
      ;;
    *)
      warn "Unknown distro — build umr from source (see below)."
      ;;
  esac
  if ! command -v umr >/dev/null 2>&1; then
    say ""
    say "${B}Manual umr install (minimal build — all RedControl needs):${N}"
    say "  # Debian/Ubuntu/Mint:"
    say "  sudo apt install git cmake build-essential pkg-config libpciaccess-dev libdrm-dev libncurses-dev"
    say "  # Fedora:"
    say "  sudo dnf install git cmake gcc gcc-c++ make pkgconf-pkg-config libpciaccess-devel libdrm-devel ncurses-devel"
    say "  # Arch (or just: yay -S umr-git):"
    say "  sudo pacman -S --needed git base-devel cmake libpciaccess libdrm ncurses"
    say "  # then:"
    say "  git clone https://gitlab.freedesktop.org/tomstdenis/umr"
    say "  cd umr && cmake -S . -B build -DUMR_NO_GUI=ON -DUMR_NO_LLVM=ON && make -C build -j && sudo make -C build install"
  fi
fi

# ---- 3. Privileged helper + polkit policy -----------------------------------
head "3. Privileged helper"
say "RedControl runs as your normal user. GPU register access goes through a"
say "small root helper, authorised by polkit — no sudoers rule is installed."
if [ ! -f "$HERE/redcontrol-helper" ]; then
  err "redcontrol-helper is missing from $HERE — cannot continue."
elif ask "Install redcontrol-helper and its polkit policy?"; then
  helper_ok=1
  sudo install -d -m 0755 /usr/libexec || helper_ok=0
  sudo install -m 0755 -o root -g root "$HERE/redcontrol-helper" \
       /usr/libexec/redcontrol-helper || helper_ok=0
  sudo install -d -m 0755 /usr/share/polkit-1/actions || helper_ok=0
  sudo install -m 0644 -o root -g root "$HERE/org.redcontrol.helper.policy" \
       /usr/share/polkit-1/actions/org.redcontrol.helper.policy || helper_ok=0
  if [ "$helper_ok" -eq 1 ]; then
    ok "helper installed to /usr/libexec/redcontrol-helper"
    if ! command -v pkexec >/dev/null 2>&1; then
      warn "pkexec not found — install polkit, or RedControl falls back to sudo."
    fi
  else
    err "helper install failed — RedControl will not be able to reach the GPU."
  fi
fi

# Older versions wrote a passwordless sudo rule that also allowed find, cat and
# mount as root — enough for any local program to obtain a root shell. It is no
# longer used, so remove it.
# /etc/sudoers.d is not readable by a normal user, so probe the rule the way
# sudo would rather than testing for the file.
if sudo -n /usr/bin/true 2>/dev/null; then
  warn "An insecure passwordless sudo rule from an earlier version is installed."
  if ask "Remove /etc/sudoers.d/umr-passwordless now?"; then
    sudo rm -f /etc/sudoers.d/umr-passwordless && ok "removed" || err "removal failed"
    sudo -k
  fi
fi

# ---- 4. Optional niceties ---------------------------------------------------
head "4. Optional extras (nicer names, tray icon)"
if ask "Install optional Python extras (pystray, pillow) for the tray icon?"; then
  # Newer distros (PEP 668, e.g. Ubuntu 24.04 / Mint 22) refuse plain pip installs;
  # --break-system-packages with --user only touches ~/.local, so it's a safe fallback.
  if python3 -m pip install --user --upgrade pystray pillow \
     || python3 -m pip install --user --upgrade --break-system-packages pystray pillow; then
    ok "extras installed"
  else
    warn "pip install failed — the app still runs without the tray."
  fi
fi

# ---- 5. Desktop launcher + icon ---------------------------------------------
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
if ask "Launch RedControl now?"; then
  if have_tk; then setsid python3 "$HERE/redcontrol.py" >/dev/null 2>&1 &
  else err "Cannot launch — tkinter is not installed (see step 1)."; fi
fi

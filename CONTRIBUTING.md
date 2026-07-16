# Contributing to RedControl

Thanks for your interest! RedControl is a single-file Tkinter app (`redcontrol.py`).

## Reporting bugs
Open an issue with:
- Your GPU (e.g. RX 6600) and distro
- `umr --version` output
- What you did and what happened (a screenshot helps)
- Relevant lines from `python3 redcontrol.py --debug`

## Development
- Keep it a single file with no required third-party Python packages (Tkinter only; `pystray`/`pillow` are optional).
- Every register write must be logged to the CMD Log as its exact `umr` command.
- UI colors must come from the theme (`self.theme[...]`), never hardcoded — so dark, e-ink and future themes all work.
- Risky display changes must go through the Keep/Revert confirmation with auto-revert.

## Testing
Run `python3 -m py_compile redcontrol.py` before committing. Test on real hardware where possible.

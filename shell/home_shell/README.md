# Home Shell (version 0.1)

A full-screen home screen for Windows with big tiles. Works with an Xbox / PlayStation / GameSir
controller, a TV remote (as keyboard keys), keyboard and mouse. It runs ON TOP of Windows —
nothing about Windows is replaced, so nothing can break.

## First run (once)
```
cd C:\debrifyy\shell\home_shell
flutter create --platforms=windows .
flutter pub get
flutter run -d windows --release
```

## Controls
| Action | Controller | Keyboard / mouse |
|---|---|---|
| Move | D-pad / stick | Arrow keys / mouse |
| Open tile | A | Enter / click |
| Edit tile | Start | F2 / right-click |
| Power menu | B / Back | Esc / F10 |

**Open now row:** apps that are already running appear at the top. Select one to switch to it (Start / right-click closes it).

**Home gesture (from any app):** HOLD the Xbox Guide button for 1 second, or press Ctrl+Alt+H, and Home Shell comes forward. Nothing gets closed, and a quick tap of Guide still works in the other app (Playnite, Steam).
If the Windows Game Bar pops up on Guide, turn it off in Settings > Gaming > Game Bar.

Tiles are saved in `%APPDATA%\HomeShell\tiles.json`. Use **Add** to make your own tile
(a program path or a link like `steam://open/bigpicture`).

Debrify is untouched; the default Debrify tile just points at its built exe.

# Home Shell (small bar)

A small bar that floats at the top of the screen, on top of any app or game. Pick an open app to
switch to it, or start one of your tiles. Works with an Xbox controller, keyboard and mouse.
It runs on top of Windows and replaces nothing.

## First run (once)
```
cd C:\debrifyy\shell\home_shell
flutter create --platforms=windows .
flutter pub get
flutter run -d windows --release
```

## Starts by itself
The first time it runs, Home Shell sets itself to start when you sign in to Windows (Settings > "Start with Windows" turns that off). Run it from the built exe, e.g. `C:\\debrifyy\\shell\\home_shell\\build\\windows\\x64\\runner\\Release\\home_shell.exe`; if you move or rebuild into another folder, run it once from there to update the startup entry.

## Using it
- **Always on screen:** the bar stays at the top all the time (turn off in Settings). While you use another app it shrinks to just icons; your bar button (default: hold Guide) puts it back into focus so the controller drives it. B / Esc gives control back to the app you were in.
- **Show the bar from anywhere:** HOLD the Xbox Guide button for 1 second, or press Ctrl+Alt+H.
  A quick tap of Guide still goes to the other app (Playnite, Steam, Game Bar) untouched.
- **Controller:** D-pad = move, **A** = open, **X** = close an open app / edit a tile, **Y** = add, **B** = hide. (Keyboard: Enter, F2, F3, Esc.) The buttons are shown at the bottom of the bar.
- **Add (Y or +):** pick from your open apps, quick links (YouTube, Netflix...), or any installed app (Start menu) — no typing needed. "Type it myself" is there for anything else.
- **Open apps** (left, with a green dot) show their real icon. Start / F2 / right-click closes one.
- **Your tiles** (middle): Start / F2 / right-click edits or deletes one. **+** adds a new one.
- **Power** (right): sleep, restart, shut down, sign out, on-screen keyboard, close the bar.

Tiles are saved in `%APPDATA%\HomeShell\tiles.json`; icons are cached in `%APPDATA%\HomeShell\icons`.
If the Windows Game Bar pops up on Guide, turn that off in Settings > Gaming > Game Bar.

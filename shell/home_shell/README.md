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

## Using it
- **Show the bar from anywhere:** HOLD the Xbox Guide button for 1 second, or press Ctrl+Alt+H.
  A quick tap of Guide still goes to the other app (Playnite, Steam, Game Bar) untouched.
- **Move:** D-pad / arrow keys / mouse. **Select:** A / Enter / click. **Hide:** B / Esc.
- **Open apps** (left, with a green dot) show their real icon. Start / F2 / right-click closes one.
- **Your tiles** (middle): Start / F2 / right-click edits or deletes one. **+** adds a new one.
- **Power** (right): sleep, restart, shut down, sign out, on-screen keyboard, close the bar.

Tiles are saved in `%APPDATA%\HomeShell\tiles.json`; icons are cached in `%APPDATA%\HomeShell\icons`.
If the Windows Game Bar pops up on Guide, turn that off in Settings > Gaming > Game Bar.

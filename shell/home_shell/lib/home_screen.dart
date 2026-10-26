import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'icon_cache.dart';
import 'launcher.dart';
import 'open_windows.dart';
import 'shell_mode.dart';
import 'tiles.dart';

/// The whole app: one small bar that floats on top of whatever you are doing.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ShellTile> _tiles = [];
  List<OpenWindow> _open = [];
  final Map<String, File?> _icons = {};
  final Set<String> _iconRequested = {};
  final ValueNotifier<String> _label = ValueNotifier<String>('');
  Timer? _timer;
  bool _busyDialog = false;

  static const _idleHint = 'Hold Guide: show this bar     B / Esc: hide';

  @override
  void initState() {
    super.initState();
    _label.value = _idleHint;
    ShellMode.instance.barRequest.addListener(_applyBar);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (ShellMode.instance.visible && !_busyDialog) _refreshWindows();
    });
    TileStore.load().then((t) {
      if (!mounted) return;
      setState(() => _tiles = t);
      ShellMode.instance.showBar();
    });
  }

  @override
  void dispose() {
    ShellMode.instance.barRequest.removeListener(_applyBar);
    _timer?.cancel();
    super.dispose();
  }

  // ---- data ---------------------------------------------------------------

  void _refreshWindows() {
    if (!mounted) return;
    final list = OpenWindows.instance.list();
    final same = list.length == _open.length &&
        [
          for (var i = 0; i < list.length; i++)
            list[i].hwnd == _open[i].hwnd && list[i].title == _open[i].title,
        ].every((e) => e);
    if (same) return;
    final before = _barItemCount;
    setState(() => _open = list);
    if (_barItemCount != before) {
      ShellMode.instance.applyBar(itemCount: _barItemCount);
    }
  }

  int get _barItemCount => _open.length + _tiles.length + 2;

  Future<void> _applyBar() async {
    if (!mounted) return;
    _refreshWindows();
    await ShellMode.instance.applyBar(itemCount: _barItemCount);
  }

  Future<void> _save() => TileStore.save(_tiles);

  /// Real icon for an .exe (made once, then kept), or null while loading.
  File? _iconFor(String exe) {
    if (exe.isEmpty) return null;
    if (_iconRequested.add(exe)) {
      IconCache.instance.iconFor(exe).then((f) {
        if (mounted) setState(() => _icons[exe] = f);
      });
    }
    return _icons[exe];
  }

  String _tileExe(ShellTile t) {
    if (t.kind != 'app') return '';
    final p = Launcher.expand(t.target.trim());
    return p.toLowerCase().endsWith('.exe') && File(p).existsSync() ? p : '';
  }

  // ---- actions --------------------------------------------------------------

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text, maxLines: 2)));
  }

  void _switchTo(OpenWindow w) {
    OpenWindows.instance.switchTo(w.hwnd);
    ShellMode.instance.hide();
  }

  void _closeWindow(OpenWindow w) {
    OpenWindows.instance.close(w.hwnd);
    Future.delayed(const Duration(milliseconds: 700), _refreshWindows);
  }

  Future<void> _launch(ShellTile t) async {
    final err = await Launcher.open(t);
    if (err == null) {
      ShellMode.instance.hide();
    } else if (mounted) {
      _toast(err);
    }
  }

  /// Runs [body] in a bigger window (for dialogs), then shrinks back.
  Future<T?> _inBigWindow<T>(Future<T?> Function() body) async {
    _busyDialog = true;
    await ShellMode.instance.enterBig();
    try {
      return await body();
    } finally {
      _busyDialog = false;
      if (mounted) await ShellMode.instance.applyBar(itemCount: _barItemCount);
    }
  }

  Future<void> _edit(ShellTile? existing) async {
    final result = await _inBigWindow<_EditResult>(
      () => showDialog<_EditResult>(
        context: context,
        builder: (_) => _EditDialog(tile: existing),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.delete && existing != null) {
        _tiles.remove(existing);
      } else if (result.tile != null) {
        if (existing == null) {
          _tiles.add(result.tile!);
        } else {
          _tiles[_tiles.indexOf(existing)] = result.tile!;
        }
      }
    });
    await _save();
    await ShellMode.instance.applyBar(itemCount: _barItemCount);
  }

  Future<void> _powerMenu() async {
    final choice = await _inBigWindow<String>(
      () => showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Power & more'),
          children: [
            _menuItem(ctx, 'sleep', Icons.bedtime_rounded, 'Sleep', first: true),
            _menuItem(ctx, 'restart', Icons.restart_alt_rounded, 'Restart'),
            _menuItem(ctx, 'shutdown', Icons.power_settings_new_rounded, 'Shut down'),
            _menuItem(ctx, 'signout', Icons.logout_rounded, 'Sign out'),
            _menuItem(ctx, 'keyboard', Icons.keyboard_rounded, 'Open on-screen keyboard'),
            _menuItem(ctx, 'exit', Icons.close_rounded, 'Close this bar (Home Shell)'),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'sleep':
        await Launcher.sleep();
      case 'restart':
        await Launcher.restart();
      case 'shutdown':
        await Launcher.shutDown();
      case 'signout':
        await Launcher.signOut();
      case 'keyboard':
        await Launcher.screenKeyboard();
      case 'exit':
        await windowManager.destroy();
    }
  }

  Widget _menuItem(BuildContext ctx, String value, IconData icon, String label,
      {bool first = false}) {
    return ListTile(
      autofocus: first,
      leading: Icon(icon),
      title: Text(label, style: const TextStyle(fontSize: 20)),
      onTap: () => Navigator.pop(ctx, value),
    );
  }

  // ---- bar ------------------------------------------------------------------

  Widget _divider() => Container(
    width: 1,
    height: 40,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: Colors.white24,
  );

  Widget _imageOr(File? icon, Widget fallback) => icon == null
      ? fallback
      : Image.file(icon, width: 40, height: 40, filterQuality: FilterQuality.medium);

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    var first = true;
    bool af() {
      final v = first;
      first = false;
      return v;
    }

    for (final w in _open) {
      final letter = w.title.trim().isEmpty ? '?' : w.title.trim()[0].toUpperCase();
      final hue = (w.title.hashCode % 360).abs().toDouble();
      final fallbackColor = HSLColor.fromAHSL(1, hue, 0.45, 0.32).toColor();
      final icon = _iconFor(w.exePath);
      items.add(
        _BarItem(
          key: ValueKey('w${w.hwnd}'),
          label: w.title,
          color: icon != null ? const Color(0xFF232B3F) : fallbackColor,
          dot: true,
          autofocus: af(),
          onTap: () => _switchTo(w),
          onOptions: () => _closeWindow(w),
          onFocusLabel: (t) => _label.value = t,
          child: _imageOr(
            icon,
            Text(letter, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          ),
        ),
      );
    }
    if (_open.isNotEmpty && _tiles.isNotEmpty) items.add(_divider());
    for (final t in _tiles) {
      final icon = _iconFor(_tileExe(t));
      items.add(
        _BarItem(
          key: ValueKey('t${t.id}'),
          label: t.name,
          color: icon != null
              ? const Color(0xFF232B3F)
              : kTileColors[t.color.clamp(0, kTileColors.length - 1)],
          autofocus: af(),
          onTap: () => _launch(t),
          onOptions: () => _edit(t),
          onFocusLabel: (t) => _label.value = t,
          child: _imageOr(icon, Icon(kTileIcons[t.icon] ?? Icons.apps_rounded, size: 30)),
        ),
      );
    }
    items.add(_divider());
    items.add(
      _BarItem(
        key: const ValueKey('add'),
        label: 'Add an app or link',
        color: const Color(0xFF232B3F),
        autofocus: af(),
        onTap: () => _edit(null),
        onFocusLabel: (t) => _label.value = t,
        child: const Icon(Icons.add_rounded, size: 30),
      ),
    );
    items.add(
      _BarItem(
        key: const ValueKey('power'),
        label: 'Power & more',
        color: const Color(0xFF232B3F),
        onTap: _powerMenu,
        onFocusLabel: (t) => _label.value = t,
        child: const Icon(Icons.power_settings_new_rounded, size: 30),
      ),
    );

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _HideBarIntent(),
      },
      child: Actions(
        actions: {
          _HideBarIntent: CallbackAction<_HideBarIntent>(onInvoke: (_) {
            if (!_busyDialog) ShellMode.instance.hide();
            return null;
          }),
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF11151F),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 66,
                  child: Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(mainAxisSize: MainAxisSize.min, children: items),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                ValueListenableBuilder<String>(
                  valueListenable: _label,
                  builder: (_, v, __) => Text(
                    v,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HideBarIntent extends Intent {
  const _HideBarIntent();
}

class _BarItem extends StatefulWidget {
  const _BarItem({
    super.key,
    required this.child,
    required this.color,
    required this.label,
    required this.onTap,
    required this.onFocusLabel,
    this.onOptions,
    this.dot = false,
    this.autofocus = false,
  });
  final Widget child;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onOptions;
  final void Function(String) onFocusLabel;

  /// Small dot under the item = this app is open right now.
  final bool dot;
  final bool autofocus;

  @override
  State<_BarItem> createState() => _BarItemState();
}

class _BarItemState extends State<_BarItem> {
  bool _focused = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused || _hover;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) {
            widget.onFocusLabel(widget.label);
            Scrollable.ensureVisible(context,
                duration: const Duration(milliseconds: 120), alignment: 0.5);
          }
        },
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          final k = e.logicalKey;
          if (k == LogicalKeyboardKey.enter ||
              k == LogicalKeyboardKey.numpadEnter ||
              k == LogicalKeyboardKey.select ||
              k == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          if (widget.onOptions != null &&
              (k == LogicalKeyboardKey.mediaPlayPause ||
                  k == LogicalKeyboardKey.contextMenu ||
                  k == LogicalKeyboardKey.f2)) {
            widget.onOptions!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          onEnter: (_) {
            setState(() => _hover = true);
            widget.onFocusLabel(widget.label);
          },
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onTap,
            onSecondaryTap: widget.onOptions,
            onLongPress: widget.onOptions,
            child: AnimatedScale(
              scale: active ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 100),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _focused ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: widget.child,
                  ),
                  if (widget.dot)
                    Positioned(
                      bottom: 3,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF51CF66),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EditResult {
  _EditResult({this.tile, this.delete = false});
  final ShellTile? tile;
  final bool delete;
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({this.tile});
  final ShellTile? tile;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _target;
  late final TextEditingController _args;
  late String _kind;
  late String _icon;
  late int _color;

  @override
  void initState() {
    super.initState();
    final t = widget.tile;
    _name = TextEditingController(text: t?.name ?? '');
    _target = TextEditingController(text: t?.target ?? '');
    _args = TextEditingController(text: t?.args ?? '');
    _kind = t?.kind ?? 'app';
    _icon = t?.icon ?? 'apps';
    _color = t?.color ?? 0;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _args.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) return;
    Navigator.pop(
      context,
      _EditResult(
        tile: ShellTile(
          id: widget.tile?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
          name: _name.text.trim(),
          kind: _kind,
          target: _target.text.trim(),
          args: _args.text.trim(),
          icon: _icon,
          color: _color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.tile == null ? 'Add a tile' : 'Edit tile'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'app', label: Text('Program'), icon: Icon(Icons.apps_rounded)),
                  ButtonSegment(value: 'link', label: Text('Link'), icon: Icon(Icons.link_rounded)),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _target,
                decoration: InputDecoration(
                  labelText: _kind == 'app'
                      ? r'Full path to the .exe (example: C:\Games\app.exe)'
                      : 'Web address or link (example: https://… or steam://…)',
                ),
              ),
              if (_kind == 'app') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _args,
                  decoration: const InputDecoration(labelText: 'Extra options (optional)'),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in kTileIcons.entries)
                  ChoiceChip(
                    label: Icon(e.value),
                    selected: _icon == e.key,
                    onSelected: (_) => setState(() => _icon = e.key),
                  ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                for (var i = 0; i < kTileColors.length; i++)
                  InkWell(
                    onTap: () => setState(() => _color = i),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: kTileColors[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == i ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.tile != null)
          TextButton(
            onPressed: () => Navigator.pop(context, _EditResult(delete: true)),
            child: const Text('Delete'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

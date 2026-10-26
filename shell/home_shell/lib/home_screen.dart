import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'launcher.dart';
import 'open_windows.dart';
import 'shell_mode.dart';
import 'tiles.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ShellTile> _tiles = [];
  bool _loaded = false;
  DateTime _now = DateTime.now();
  Timer? _clock;
  final Map<String, FocusNode> _nodes = {};
  List<OpenWindow> _open = [];
  Timer? _windowTimer;
  final Map<int, FocusNode> _winNodes = {};

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    ShellMode.instance.bar.addListener(_onModeChange);
    ShellMode.instance.barRequest.addListener(_applyMode);
    _refreshWindows();
    _windowTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshWindows());
    TileStore.load().then((t) {
      if (!mounted) return;
      setState(() {
        _tiles = t;
        _loaded = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _nodeFor(_tiles.first).requestFocus();
      });
    });
  }

  @override
  void dispose() {
    ShellMode.instance.bar.removeListener(_onModeChange);
    ShellMode.instance.barRequest.removeListener(_applyMode);
    _clock?.cancel();
    _windowTimer?.cancel();
    for (final n in _winNodes.values) {
      n.dispose();
    }
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _onModeChange() {
    if (mounted) setState(() {});
  }

  int get _barItemCount => 1 + _open.length + _tiles.length + 1;

  void _applyMode() {
    if (!mounted) return;
    _refreshWindows();
    ShellMode.instance.applyWindow(itemCount: _barItemCount);
  }

  void _hideBar() {
    windowManager.hide();
  }

  void _barSwitch(int hwnd) {
    OpenWindows.instance.switchTo(hwnd);
    _hideBar();
  }

  Future<void> _barLaunch(ShellTile t) async {
    final err = await Launcher.open(t);
    if (err == null) {
      _hideBar();
    } else if (mounted) {
      _toast(err);
    }
  }

  Widget _buildBar() {
    final label = ValueNotifier<String>('');
    Widget item(IconData? icon, String text, VoidCallback onTap,
        {String? letter, bool autofocus = false, Color? color, int? key}) {
      return _BarItem(
        key: key == null ? null : ValueKey(key),
        icon: icon,
        letter: letter,
        color: color ?? const Color(0xFF2B3550),
        label: text,
        onTap: onTap,
        onFocusLabel: (t) => label.value = t,
        autofocus: autofocus,
      );
    }

    final divider = Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white24,
    );
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _HideBarIntent(),
      },
      child: Actions(
        actions: {
          _HideBarIntent: CallbackAction<_HideBarIntent>(onInvoke: (_) {
            _hideBar();
            return null;
          }),
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF11151F),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 64,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    shrinkWrap: true,
                    children: [
                      item(Icons.home_rounded, 'Home',
                          () => ShellMode.instance.showFull(),
                          autofocus: true),
                      if (_open.isNotEmpty) divider,
                      for (final w in _open)
                        item(
                          null,
                          w.title,
                          () => _barSwitch(w.hwnd),
                          key: w.hwnd,
                          letter: w.title.trim().isEmpty
                              ? '?'
                              : w.title.trim()[0].toUpperCase(),
                          color: HSLColor.fromAHSL(
                                  1, (w.title.hashCode % 360).abs().toDouble(), 0.45, 0.32)
                              .toColor(),
                        ),
                      if (_tiles.isNotEmpty) divider,
                      for (final t in _tiles)
                        item(
                          kTileIcons[t.icon] ?? Icons.apps_rounded,
                          t.name,
                          () => _barLaunch(t),
                          color: kTileColors[t.color.clamp(0, kTileColors.length - 1)],
                        ),
                      divider,
                      item(Icons.power_settings_new_rounded, 'Power menu', () {
                        ShellMode.instance.showFull();
                        WidgetsBinding.instance.addPostFrameCallback((_) => _powerMenu());
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                ValueListenableBuilder<String>(
                  valueListenable: label,
                  builder: (_, v, __) => Text(
                    v.isEmpty ? 'Hold Guide to show this bar   B / Esc: hide' : v,
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

  void _refreshWindows() {
    if (!mounted) return;
    final list = OpenWindows.instance.list();
    final same = list.length == _open.length &&
        [for (var i = 0; i < list.length; i++) list[i].hwnd == _open[i].hwnd && list[i].title == _open[i].title]
            .every((e) => e);
    if (same) return;
    final alive = list.map((w) => w.hwnd).toSet();
    for (final k in _winNodes.keys.where((k) => !alive.contains(k)).toList()) {
      final n = _winNodes.remove(k)!;
      WidgetsBinding.instance.addPostFrameCallback((_) => n.dispose());
    }
    setState(() => _open = list);
  }

  FocusNode _winNodeFor(int hwnd) =>
      _winNodes.putIfAbsent(hwnd, () => FocusNode(debugLabel: 'win-$hwnd'));

  FocusNode _nodeFor(ShellTile t) =>
      _nodes.putIfAbsent(t.id, () => FocusNode(debugLabel: t.id));

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _launch(ShellTile t) async {
    final err = await Launcher.open(t);
    if (err != null && mounted) _toast(err);
  }

  Future<void> _save() => TileStore.save(_tiles);

  Future<void> _edit(ShellTile? existing) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _EditDialog(tile: existing),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.delete && existing != null) {
        _tiles.remove(existing);
        _nodes.remove(existing.id)?.dispose();
      } else if (result.tile != null) {
        if (existing == null) {
          _tiles.add(result.tile!);
        } else {
          final i = _tiles.indexOf(existing);
          _tiles[i] = result.tile!;
        }
      }
    });
    await _save();
    if (_tiles.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _nodeFor(_tiles.first).requestFocus();
      });
    }
  }

  Future<void> _powerMenu() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Power & more'),
        children: [
          _menuItem(ctx, 'sleep', Icons.bedtime_rounded, 'Sleep', first: true),
          _menuItem(ctx, 'restart', Icons.restart_alt_rounded, 'Restart'),
          _menuItem(ctx, 'shutdown', Icons.power_settings_new_rounded, 'Shut down'),
          _menuItem(ctx, 'signout', Icons.logout_rounded, 'Sign out'),
          _menuItem(ctx, 'keyboard', Icons.keyboard_rounded, 'Open on-screen keyboard'),
          _menuItem(ctx, 'window', Icons.window_rounded, 'Leave full screen / minimize'),
          _menuItem(ctx, 'exit', Icons.close_rounded, 'Close Home Shell'),
        ],
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
      case 'window':
        await windowManager.setFullScreen(false);
        await windowManager.minimize();
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

  String get _timeText {
    final h = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final m = _now.minute.toString().padLeft(2, '0');
    return '$h:$m ${_now.hour >= 12 ? 'PM' : 'AM'}';
  }

  String get _dateText {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'];
    return '${days[_now.weekday - 1]}, ${months[_now.month - 1]} ${_now.day}';
  }

  @override
  Widget build(BuildContext context) {
    if (ShellMode.instance.bar.value) return _buildBar();
    return Shortcuts(
      shortcuts: const {
        // Escape (controller B / remote Back) opens the power menu.
        SingleActivator(LogicalKeyboardKey.escape): _PowerIntent(),
        SingleActivator(LogicalKeyboardKey.f10): _PowerIntent(),
      },
      child: Actions(
        actions: {
          _PowerIntent: CallbackAction<_PowerIntent>(onInvoke: (_) {
            _powerMenu();
            return null;
          }),
        },
        child: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(56, 36, 56, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_timeText,
                          style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w300)),
                      const SizedBox(width: 24),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(_dateText,
                            style: const TextStyle(fontSize: 24, color: Colors.white70)),
                      ),
                      const Spacer(),
                      _BarButton(icon: Icons.add_rounded, label: 'Add', onTap: () => _edit(null)),
                      const SizedBox(width: 12),
                      _BarButton(icon: Icons.power_settings_new_rounded, label: 'Power', onTap: _powerMenu),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_open.isNotEmpty) ...[
                    const Text('Open now',
                        style: TextStyle(fontSize: 16, color: Colors.white54)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 56,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final w in _open)
                            _WindowChip(
                              key: ValueKey(w.hwnd),
                              window: w,
                              node: _winNodeFor(w.hwnd),
                              onOpen: () => OpenWindows.instance.switchTo(w.hwnd),
                              onClose: () {
                                OpenWindows.instance.close(w.hwnd);
                                Future.delayed(const Duration(milliseconds: 600), _refreshWindows);
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Expanded(
                    child: !_loaded
                        ? const Center(child: CircularProgressIndicator())
                        : FocusTraversalGroup(
                            policy: ReadingOrderTraversalPolicy(),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(8),
                              child: Wrap(
                                spacing: 24,
                                runSpacing: 24,
                                children: [
                                  for (final t in _tiles)
                                    _TileCard(
                                      tile: t,
                                      node: _nodeFor(t),
                                      onOpen: () => _launch(t),
                                      onOptions: () => _edit(t),
                                    ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  const Text(
                    'A / Enter / click: open     Start / right-click / F2: edit tile (or close an open app)     B / Esc: power menu',
                    style: TextStyle(color: Colors.white38, fontSize: 15),
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

class _HideBarIntent extends Intent {
  const _HideBarIntent();
}

class _BarItem extends StatefulWidget {
  const _BarItem({
    super.key,
    this.icon,
    this.letter,
    required this.color,
    required this.label,
    required this.onTap,
    required this.onFocusLabel,
    this.autofocus = false,
  });
  final IconData? icon;
  final String? letter;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final void Function(String) onFocusLabel;
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
            child: AnimatedScale(
              scale: active ? 1.1 : 1.0,
              duration: const Duration(milliseconds: 100),
              child: Container(
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
                child: widget.icon != null
                    ? Icon(widget.icon, size: 30)
                    : Text(widget.letter ?? '?',
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PowerIntent extends Intent {
  const _PowerIntent();
}

class _WindowChip extends StatefulWidget {
  const _WindowChip({
    super.key,
    required this.window,
    required this.node,
    required this.onOpen,
    required this.onClose,
  });
  final OpenWindow window;
  final FocusNode node;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  State<_WindowChip> createState() => _WindowChipState();
}

class _WindowChipState extends State<_WindowChip> {
  bool _focused = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = _focused || _hover;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Focus(
        focusNode: widget.node,
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) {
            Scrollable.ensureVisible(context,
                duration: const Duration(milliseconds: 150), alignment: 0.5);
          }
        },
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          final k = e.logicalKey;
          if (k == LogicalKeyboardKey.enter ||
              k == LogicalKeyboardKey.numpadEnter ||
              k == LogicalKeyboardKey.select ||
              k == LogicalKeyboardKey.space) {
            widget.onOpen();
            return KeyEventResult.handled;
          }
          if (k == LogicalKeyboardKey.mediaPlayPause ||
              k == LogicalKeyboardKey.contextMenu ||
              k == LogicalKeyboardKey.f2) {
            widget.onClose();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onOpen,
            onSecondaryTap: widget.onClose,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? const Color(0xFF2B3550) : const Color(0xFF1A2030),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: _focused ? Colors.white : Colors.white12,
                  width: _focused ? 3 : 1,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.window_rounded, size: 22),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(widget.window.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label, style: const TextStyle(fontSize: 18)),
      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18)),
    );
  }
}

class _TileCard extends StatefulWidget {
  const _TileCard({
    required this.tile,
    required this.node,
    required this.onOpen,
    required this.onOptions,
  });
  final ShellTile tile;
  final FocusNode node;
  final VoidCallback onOpen;
  final VoidCallback onOptions;

  @override
  State<_TileCard> createState() => _TileCardState();
}

class _TileCardState extends State<_TileCard> {
  bool _focused = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tile;
    final color = kTileColors[t.color.clamp(0, kTileColors.length - 1)];
    final active = _focused || _hover;
    return Focus(
      focusNode: widget.node,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (f) {
          Scrollable.ensureVisible(context,
              duration: const Duration(milliseconds: 150), alignment: 0.5);
        }
      },
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter ||
            k == LogicalKeyboardKey.select ||
            k == LogicalKeyboardKey.space) {
          widget.onOpen();
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.mediaPlayPause ||
            k == LogicalKeyboardKey.contextMenu ||
            k == LogicalKeyboardKey.f2) {
          widget.onOptions();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: () {
            widget.node.requestFocus();
            widget.onOpen();
          },
          onSecondaryTap: widget.onOptions,
          onLongPress: widget.onOptions,
          child: AnimatedScale(
            scale: active ? 1.06 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: Container(
              width: 240,
              height: 170,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: [color, color.withValues(alpha: 0.65)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: _focused ? Colors.white : Colors.transparent,
                  width: 4,
                ),
                boxShadow: active
                    ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 24)]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(kTileIcons[t.icon] ?? Icons.apps_rounded, size: 52),
                  Text(t.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
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

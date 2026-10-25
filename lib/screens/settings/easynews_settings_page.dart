import 'package:flutter/material.dart';

import '../../services/easynews_service.dart';
import '../../theme/app_theme_scope.dart';
import '../../widgets/tv_text_field.dart';
import 'widgets/settings_widgets.dart';

/// Usenet provider settings: the Easynews login used by the Usenet tab.
/// Pops with `true` when the login was removed.
class EasynewsSettingsPage extends StatefulWidget {
  const EasynewsSettingsPage({super.key});

  @override
  State<EasynewsSettingsPage> createState() => _EasynewsSettingsPageState();
}

class _EasynewsSettingsPageState extends State<EasynewsSettingsPage> {
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  final FocusNode _userFocus = FocusNode(debugLabel: 'easynews-user');
  final FocusNode _passFocus = FocusNode(debugLabel: 'easynews-pass');
  bool _loading = true;
  bool _saving = false;
  bool _configured = false;
  String _savedUser = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final configured = await EasynewsService.instance.isConfigured();
    final name = await EasynewsService.instance.savedUsername();
    if (!mounted) return;
    setState(() {
      _configured = configured;
      _savedUser = name;
      _loading = false;
    });
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    final t = AppThemeScope.of(context).settings;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: error ? t.danger : null),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final problem = await EasynewsService.instance.verifyAndSave(
      _user.text,
      _pass.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (problem != null) {
      _snack(problem, error: true);
      return;
    }
    _pass.clear();
    await _load();
    _snack('Easynews connected');
  }

  Future<void> _logout() async {
    await EasynewsService.instance.clear();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Usenet',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return SettingsPageScaffold(
      title: 'Usenet',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsPageHeader(
                  icon: Icons.newspaper_rounded,
                  title: 'Usenet (Easynews)',
                  subtitle: _configured
                      ? 'Connected as $_savedUser'
                      : 'Use your own Easynews account to search and stream',
                ),
                const SizedBox(height: 20),
                Text(
                  _configured
                      ? 'Enter a new login to replace the saved one.'
                      : 'Sign in with the username and password of your '
                            'Easynews account. The Usenet tab then searches '
                            'Easynews like its website does, and plays what '
                            'you pick.',
                  style: TextStyle(fontSize: 13, height: 1.45, color: t.dim),
                ),
                const SizedBox(height: 16),
                TvTextField(
                  controller: _user,
                  focusNode: _userFocus,
                  labelText: 'Easynews username',
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _passFocus.requestFocus(),
                ),
                const SizedBox(height: 12),
                TvTextField(
                  controller: _pass,
                  focusNode: _passFocus,
                  labelText: 'Easynews password',
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login_rounded),
                      label: Text(_saving ? 'Checking…' : 'Connect'),
                    ),
                    if (_configured) ...[
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Remove login'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Your login is stored only on this computer and is sent '
                  'only to Easynews.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: t.dim),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

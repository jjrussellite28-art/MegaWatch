import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:megawatch/screens/settings/app_theme_page.dart';
import 'package:megawatch/services/storage_service.dart';
import 'package:megawatch/theme/app_theme.dart';
import 'package:megawatch/theme/app_theme_scope.dart';

void main() {
  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      home: AppThemeScope(theme: AppThemes.legacy, child: const AppThemePage()),
    ));
    await t.pump();
  }

  tearDown(() => StorageService.detailPageStyleCached =
      StorageService.kDetailPageStyleDefault);

  testWidgets('warns when Classic is the details layout', (tester) async {
    SharedPreferences.setMockInitialValues({});
    StorageService.detailPageStyleCached = 'classic';
    await pump(tester);
    expect(find.textContaining('keeps its own look'), findsOneWidget);
  });

  testWidgets('silent under a themed layout', (tester) async {
    SharedPreferences.setMockInitialValues({});
    StorageService.detailPageStyleCached = 'console';
    await pump(tester);
    expect(find.textContaining('keeps its own look'), findsNothing);
  });
}

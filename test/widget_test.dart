import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbury/data/app_settings.dart';
import 'package:wattbury/data/energy_source.dart';
import 'package:wattbury/data/live_controller.dart';
import 'package:wattbury/theme/tokens.dart';
import 'package:wattbury/ui/shell.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  testWidgets('dashboard shows demo values and switches tabs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    final live = LiveController(DemoSource(clock: () => DateTime(2026, 10, 24, 12)));
    await tester.runAsync(live.start);
    await tester.binding.setSurfaceSize(const Size(393, 852));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Shell(live: live, settings: settings, account: null, onSignOut: () {}),
      ),
    );
    await tester.pump();

    expect(find.text('Solar'), findsWidgets);
    expect(find.text('Batterie'), findsOneWidget);
    expect(find.textContaining('Demo'), findsOneWidget);
    expect(find.text('68%'), findsOneWidget);

    await tester.tap(find.text('Einstellungen').last);
    await tester.pump();
    expect(find.text('Geräte am Hauskraftwerk'), findsOneWidget);

    live.dispose();
  });
}

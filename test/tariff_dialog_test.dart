import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbury/data/app_settings.dart';
import 'package:wattbury/data/energy_source.dart';
import 'package:wattbury/data/live_controller.dart';
import 'package:wattbury/theme/tokens.dart';
import 'package:wattbury/ui/settings/settings_page.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  testWidgets('entering a tariff closes the dialog without errors and stores the value', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    final live = LiveController(DemoSource());
    await tester.binding.setSurfaceSize(const Size(393, 2600));
    // Same structure as the app: the whole MaterialApp listens to the settings.
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: settings,
        builder: (context, _) => MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: SettingsPage(
              live: live,
              settings: settings,
              credentials: null,
              onSignOut: () {},
              onEditConnection: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Ändern').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '31,2');
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(settings.priceCt, 31.2);
    expect(find.text('31,20 ct/kWh'), findsOneWidget);
    live.dispose();
  });
}

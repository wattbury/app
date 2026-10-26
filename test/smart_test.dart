import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbury/data/energy_source.dart';
import 'package:wattbury/theme/tokens.dart';
import 'package:wattbury/ui/smart/smart_page.dart';

void main() {
  testWidgets('a change is sent only after confirming and is read back', (tester) async {
    final demo = DemoSource();
    await tester.binding.setSurfaceSize(const Size(393, 2000));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: SmartPage(source: demo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Keine Änderungen'), findsOneWidget);

    // PowerSave is the third switch (after "Leistung begrenzen" and "Wetterabhängiges Laden").
    await tester.tap(find.byType(Switch).at(2));
    await tester.pump();
    expect(find.text('Änderungen übernehmen'), findsOneWidget);
    expect((await demo.powerSettings()).powerSaveEnabled, isFalse, reason: 'nothing sent yet');

    await tester.tap(find.text('Änderungen übernehmen'));
    await tester.pumpAndSettle();
    expect(find.text('• PowerSave: an'), findsOneWidget);
    await tester.tap(find.text('Senden'));
    await tester.pumpAndSettle();

    expect((await demo.powerSettings()).powerSaveEnabled, isTrue);
    expect(find.text('Übernommen und zurückgelesen ✓'), findsOneWidget);
    expect(find.text('Keine Änderungen'), findsOneWidget);
  });
}

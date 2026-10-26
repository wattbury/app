import 'package:flutter_test/flutter_test.dart';
import 'package:openrscp/openrscp.dart';
import 'package:wattbury/data/tariff.dart';

void main() {
  test('costs and savings of a period', () {
    final s = DbSummary(
      start: DateTime(2026, 10, 1),
      span: const Duration(days: 7),
      solarWh: 118000,
      houseWh: 74000,
      gridPurchaseWh: 4400,
      gridFeedInWh: 50200,
      batteryInWh: 0,
      batteryOutWh: 0,
      autarkyPct: 94,
      consumedProductionPct: 56,
      socPct: 0,
    );
    final c = Costs.of(s, priceCt: 31.2, feedInCt: 8.1);
    expect(c.purchaseEur, closeTo(1.37, 0.01));
    expect(c.feedInEur, closeTo(4.07, 0.01));
    expect(c.savingsEur, closeTo((74 - 4.4) * 0.312 + 4.07, 0.01));
  });
}

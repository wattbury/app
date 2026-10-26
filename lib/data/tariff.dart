import 'package:openrscp/openrscp.dart';

/// Money for a period from its energy totals and the user's tariff (ct/kWh).
class Costs {
  /// Paid for energy from the grid.
  final double purchaseEur;

  /// Earned for energy sent to the grid.
  final double feedInEur;

  /// Saved compared with buying all consumption from the grid: self-consumed energy at the
  /// purchase price plus the feed-in revenue.
  final double savingsEur;

  const Costs({required this.purchaseEur, required this.feedInEur, required this.savingsEur});

  static Costs of(DbSummary s, {required double priceCt, required double feedInCt}) {
    final selfUsedKwh = ((s.houseWh - s.gridPurchaseWh) / 1000).clamp(0, double.infinity);
    final purchase = s.gridPurchaseWh / 1000 * priceCt / 100;
    final feedIn = s.gridFeedInWh / 1000 * feedInCt / 100;
    return Costs(purchaseEur: purchase, feedInEur: feedIn, savingsEur: selfUsedKwh * priceCt / 100 + feedIn);
  }
}

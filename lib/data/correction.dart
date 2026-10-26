/// Learned forecast correction: compares what the forecast promised with what the unit measured,
/// per hour of the day, over a rolling window. The factor catches shading at certain hours,
/// soiling, ageing and losses the simple power model does not know.
library;

/// Measured and forecast energy of one past day, per hour (Wh), and which hours count.
class DayRecord {
  final DateTime day;
  final List<double> actualWh, forecastWh;

  /// False for hours with curtailment (feed-in at the limit), so the unit could not deliver what the sun offered.
  final List<bool> valid;

  /// Set when the whole day must not count, e.g. snow or an outage.
  final String? excluded;

  const DayRecord({
    required this.day,
    required this.actualWh,
    required this.forecastWh,
    required this.valid,
    this.excluded,
  });

  double get actualTotal => actualWh.fold(0, (a, b) => a + b);
  double get forecastTotal => forecastWh.fold(0, (a, b) => a + b);

  Map<String, Object?> toJson() => {
    'day': day.toIso8601String().substring(0, 10),
    'a': [for (final v in actualWh) v.round()],
    'f': [for (final v in forecastWh) v.round()],
    'v': [for (final v in valid) v ? 1 : 0],
    'x': excluded,
  };

  static DayRecord fromJson(Map<String, dynamic> j) => DayRecord(
    day: DateTime.parse(j['day'] as String),
    actualWh: [for (final v in j['a'] as List) (v as num).toDouble()],
    forecastWh: [for (final v in j['f'] as List) (v as num).toDouble()],
    valid: [for (final v in j['v'] as List) v == 1],
    excluded: j['x'] as String?,
  );

  /// Builds a record from 15-minute values: [actualWh], [forecastWh] and [feedInWh] per slot of the day.
  /// Hours where the feed-in reached [feedLimitW] (minus 3 %) are marked invalid. The day is
  /// excluded when almost nothing came although much was forecast (snow on the modules, outage).
  static DayRecord fromSlots({
    required DateTime day,
    required List<double> actualWh,
    required List<double> forecastWh,
    required List<double> feedInWh,
    required List<DateTime> slotStarts,
    required double kwp,
    int? feedLimitW,
  }) {
    final a = List<double>.filled(24, 0), f = List<double>.filled(24, 0);
    final v = List<bool>.filled(24, true);
    for (var i = 0; i < slotStarts.length; i++) {
      final h = slotStarts[i].hour;
      a[h] += i < actualWh.length ? actualWh[i] : 0;
      f[h] += i < forecastWh.length ? forecastWh[i] : 0;
      final feedW = (i < feedInWh.length ? feedInWh[i] : 0) * 4;
      if (feedLimitW != null && feedLimitW > 0 && feedW >= feedLimitW * 0.97) v[h] = false;
    }
    final at = a.fold<double>(0, (x, y) => x + y), ft = f.fold<double>(0, (x, y) => x + y);
    String? excluded;
    if (ft > kwp * 1000 && at < ft * 0.1) excluded = 'Schnee oder Ausfall';
    return DayRecord(day: day, actualWh: a, forecastWh: f, valid: v, excluded: excluded);
  }
}

class Correction {
  /// Factor per hour of the day (measured ÷ forecast); 1.0 where there is not enough data.
  final List<double> hourly;

  /// Overall factor over all counted hours.
  final double overall;

  /// Days that counted, days left out entirely, and days with at least one curtailed hour.
  final int days, excludedDays, curtailedDays;

  /// Mean absolute deviation of the daily total, without and with correction (fraction, 0.17 = 17 %).
  final double? rawError, correctedError;

  const Correction({
    required this.hourly,
    required this.overall,
    required this.days,
    required this.excludedDays,
    required this.curtailedDays,
    this.rawError,
    this.correctedError,
  });

  static const minDays = 7, window = 30;
  static final none = Correction(hourly: List.filled(24, 1), overall: 1, days: 0, excludedDays: 0, curtailedDays: 0);

  /// Enough data to apply the factor.
  bool get ready => days >= minDays;

  double factorAt(DateTime t) => ready ? hourly[t.hour] : 1;

  /// Ratio of sums per hour over the last [window] days; weighting by energy comes from summing.
  /// Hours with little forecast energy keep 1.0, and factors stay between 0.5 and 1.5.
  static Correction compute(List<DayRecord> records, {DateTime? today}) {
    final now = today ?? DateTime.now();
    final from = DateTime(now.year, now.month, now.day - window);
    final inWindow = records.where(
      (r) => !r.day.isBefore(from) && r.day.isBefore(DateTime(now.year, now.month, now.day)),
    );
    final counted = inWindow.where((r) => r.excluded == null).toList();
    final excludedDays = inWindow.length - counted.length;
    final a = List<double>.filled(24, 0), f = List<double>.filled(24, 0);
    var curtailed = 0;
    for (final r in counted) {
      if (r.valid.contains(false)) curtailed++;
      for (var h = 0; h < 24; h++) {
        if (!r.valid[h]) continue;
        a[h] += r.actualWh[h];
        f[h] += r.forecastWh[h];
      }
    }
    final totalF = f.fold<double>(0, (x, y) => x + y), totalA = a.fold<double>(0, (x, y) => x + y);
    // An hour needs at least 2 % of the forecast energy to get its own factor; the rest is noise.
    final hourly = [
      for (var h = 0; h < 24; h++) f[h] > totalF * 0.02 && f[h] > 0 ? (a[h] / f[h]).clamp(0.5, 1.5) : 1.0,
    ];
    final overall = totalF > 0 ? (totalA / totalF).clamp(0.5, 1.5) : 1.0;
    double? rawErr, corrErr;
    final daysForError = counted.where((r) => r.actualTotal > 500).toList();
    if (daysForError.isNotEmpty) {
      double err(DayRecord r, bool corrected) {
        var fc = 0.0;
        for (var h = 0; h < 24; h++) {
          fc += r.forecastWh[h] * (corrected ? hourly[h] : 1);
        }
        return (fc - r.actualTotal).abs() / r.actualTotal;
      }

      rawErr = daysForError.fold<double>(0, (x, r) => x + err(r, false)) / daysForError.length;
      corrErr = daysForError.fold<double>(0, (x, r) => x + err(r, true)) / daysForError.length;
    }
    return Correction(
      hourly: hourly,
      overall: overall.toDouble(),
      days: counted.length,
      excludedDays: excludedDays,
      curtailedDays: curtailed,
      rawError: rawErr,
      correctedError: corrErr,
    );
  }
}

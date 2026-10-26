import 'package:intl/intl.dart';

/// German number formatting with a fixed number of decimals ("3,42").
String fmt(double v, [int decimals = 1]) =>
    NumberFormat.decimalPatternDigits(locale: 'de_DE', decimalDigits: decimals).format(v);

/// A power value split into number and unit: below 1 kW in W, from 1 kW on in kW with two decimals.
({String value, String unit}) power(num w) {
  final a = w.abs();
  if (a < 1000) return (value: fmt(a.toDouble(), 0), unit: 'W');
  return (value: fmt(a / 1000, 2), unit: 'kW');
}

/// Energy in kWh from Wh.
String kwh(double wh, [int decimals = 1]) => fmt(wh / 1000, decimals);

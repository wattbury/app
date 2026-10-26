import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plant.dart';

enum WallboxMode { auto, show, hide }

/// Non-secret preferences. Credentials are in [CredentialStore], not here.
class AppSettings extends ChangeNotifier {
  final SharedPreferences _p;
  AppSettings(this._p);

  static Future<AppSettings> load() async => AppSettings(await SharedPreferences.getInstance());

  ThemeMode get themeMode => ThemeMode.values.byName(_p.getString('themeMode') ?? 'system');
  set themeMode(ThemeMode m) => _put('themeMode', m.name);

  WallboxMode get wallboxMode => WallboxMode.values.byName(_p.getString('wallboxMode') ?? 'auto');
  set wallboxMode(WallboxMode m) => _put('wallboxMode', m.name);

  /// Refresh interval choices in seconds. One second only locally; the portal relay is shared
  /// infrastructure and should not be polled that often.
  static const localIntervals = [1, 5, 10, 30, 60];
  static const portalIntervals = [5, 10, 30, 60];

  int get localIntervalS => _pick(_p.getInt('localIntervalS'), localIntervals, 1);
  set localIntervalS(int v) => _putInt('localIntervalS', v);

  int get portalIntervalS => _pick(_p.getInt('portalIntervalS'), portalIntervals, 5);
  set portalIntervalS(int v) => _putInt('portalIntervalS', v);

  static int _pick(int? v, List<int> allowed, int fallback) => allowed.contains(v) ? v! : fallback;

  void _putInt(String k, int v) {
    _p.setInt(k, v);
    notifyListeners();
  }

  /// Roof faces and location for the forecast. Not secret, so it lives here and not in the keychain.
  PlantConfig get plant {
    final raw = _p.getString('plant');
    if (raw == null) return const PlantConfig();
    try {
      return PlantConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const PlantConfig();
    }
  }

  set plant(PlantConfig c) => _put('plant', jsonEncode(c.toJson()));

  /// Forecast provider: 'om' (Open-Meteo, default) or 'sc' (Solcast with own key).
  String get forecastProvider => _p.getString('forecastProvider') == 'sc' ? 'sc' : 'om';
  set forecastProvider(String v) => _put('forecastProvider', v);

  /// Solcast resource id per tracker ("pvi-index" → id). Not secret; the API key is in the keychain.
  Map<String, String> get solcastSites {
    final raw = _p.getString('solcastSites');
    if (raw == null) return const {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return const {};
    }
  }

  set solcastSites(Map<String, String> m) => _put('solcastSites', jsonEncode(m));

  /// Apply the learned forecast correction (on by default).
  bool get correctionEnabled => _p.getBool('correctionEnabled') ?? true;
  set correctionEnabled(bool v) {
    _p.setBool('correctionEnabled', v);
    notifyListeners();
  }

  /// Raw storage for larger app data such as the forecast archive; does not notify listeners.
  String? readRaw(String key) => _p.getString(key);
  Future<void> writeRaw(String key, String value) => _p.setString(key, value);
  Future<void> removeRaw(String key) => _p.remove(key);

  /// True while the user looks at sample data instead of a real system.
  bool get demo => _p.getBool('demo') ?? false;
  set demo(bool v) {
    _p.setBool('demo', v);
    notifyListeners();
  }

  void _put(String k, String v) {
    _p.setString(k, v);
    notifyListeners();
  }
}

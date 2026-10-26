import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wattbury/data/app_settings.dart';

void main() {
  test('refresh intervals default and reject values outside the allowed stops', () async {
    SharedPreferences.setMockInitialValues({'portalIntervalS': 1, 'localIntervalS': 7});
    final s = await AppSettings.load();
    expect(s.portalIntervalS, 5, reason: '1 s is only allowed locally');
    expect(s.localIntervalS, 1);
    s.localIntervalS = 30;
    s.portalIntervalS = 60;
    expect(s.localIntervalS, 30);
    expect(s.portalIntervalS, 60);
  });
}

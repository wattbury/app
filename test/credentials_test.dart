import 'package:flutter_test/flutter_test.dart';
import 'package:wattbury/data/credentials.dart';

void main() {
  test('portal-only login keeps no plain password', () {
    final c = Credentials.create(username: 'u', password: 'secret', serial: 'S10-1');
    expect(c.password, isNull);
    expect(c.passwordMd5, '5ebe2294ecd0e0f08eab7690d2a6ee69');
    expect(c.hasPortal, isTrue);
    expect(c.hasLocal, isFalse);
  });

  test('local login keeps the plain password and survives JSON', () {
    final c = Credentials.create(
      username: 'u',
      password: 'secret',
      local: const LocalConfig(host: '192.168.1.2', rscpPassword: 'k'),
    ).withSerial('S10-123');
    final back = Credentials.fromJson(c.toJson());
    expect(back.password, 'secret');
    expect(back.local!.port, 5033);
    expect(back.serial, 'S10-123');
    expect(back.hasLocal && back.hasPortal, isTrue);
  });
}

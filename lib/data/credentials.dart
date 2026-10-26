import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Login for the E3/DC portal tunnel. The password is kept only as its MD5 hash, which is what
/// the relay expects; the plain password never leaves the setup screen.
class PortalCredentials {
  final String username, passwordMd5, serial;
  const PortalCredentials({required this.username, required this.passwordMd5, required this.serial});
}

/// Credentials live in the platform keychain (iOS Keychain, libsecret on Linux), never in plain files.
class CredentialStore {
  static const _user = 'portal.username', _pass = 'portal.passwordMd5', _serial = 'portal.serial';
  final FlutterSecureStorage _s;
  CredentialStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();

  Future<PortalCredentials?> load() async {
    final u = await _s.read(key: _user), p = await _s.read(key: _pass), sn = await _s.read(key: _serial);
    if (u == null || p == null || sn == null) return null;
    return PortalCredentials(username: u, passwordMd5: p, serial: sn);
  }

  Future<void> save(PortalCredentials c) async {
    await _s.write(key: _user, value: c.username);
    await _s.write(key: _pass, value: c.passwordMd5);
    await _s.write(key: _serial, value: c.serial);
  }

  Future<void> clear() async {
    for (final k in [_user, _pass, _serial]) {
      await _s.delete(key: k);
    }
  }
}

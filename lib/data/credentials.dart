import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Direct RSCP in the home network.
class LocalConfig {
  final String host;

  /// Always 5033, the RSCP port of the unit.
  final int port;

  /// "RSCP password" set on the unit (Personalisieren › Benutzerprofil); the encryption key.
  final String rscpPassword;
  const LocalConfig({required this.host, this.port = 5033, required this.rscpPassword});

  Map<String, Object> toJson() => {'host': host, 'port': port, 'rscpPassword': rscpPassword};
  static LocalConfig fromJson(Map<String, dynamic> j) =>
      LocalConfig(host: j['host'] as String, rscpPassword: j['rscpPassword'] as String);
}

/// Everything needed to reach the unit. The portal login is always required: the tunnel sends it as
/// MD5, the local connection in plain text inside the encrypted channel. That is why the plain
/// password is kept as well when a local connection is configured.
class Credentials {
  final String username, passwordMd5;
  final String? password;

  /// Serial with or without the "S10-" prefix; needed for the portal tunnel. Read from the unit when
  /// a local connection is set up.
  final String? serial;
  final LocalConfig? local;

  const Credentials({required this.username, required this.passwordMd5, this.password, this.serial, this.local});

  factory Credentials.create({
    required String username,
    required String password,
    String? serial,
    LocalConfig? local,
  }) => Credentials(
    username: username,
    passwordMd5: md5.convert(utf8.encode(password)).toString(),
    password: local == null ? null : password,
    serial: serial,
    local: local,
  );

  bool get hasPortal => serial != null && serial!.isNotEmpty;
  bool get hasLocal => local != null && password != null;

  Credentials withSerial(String s) =>
      Credentials(username: username, passwordMd5: passwordMd5, password: password, serial: s, local: local);

  Map<String, Object?> toJson() => {
    'username': username,
    'passwordMd5': passwordMd5,
    'password': password,
    'serial': serial,
    'local': local?.toJson(),
  };

  static Credentials fromJson(Map<String, dynamic> j) => Credentials(
    username: j['username'] as String,
    passwordMd5: j['passwordMd5'] as String,
    password: j['password'] as String?,
    serial: j['serial'] as String?,
    local: j['local'] == null ? null : LocalConfig.fromJson(j['local'] as Map<String, dynamic>),
  );
}

/// Credentials live in the platform keychain (iOS Keychain, libsecret on Linux), never in plain files.
class CredentialStore {
  static const _key = 'connection';
  // Keys of the first version, which only knew the portal tunnel.
  static const _oldUser = 'portal.username', _oldPass = 'portal.passwordMd5', _oldSerial = 'portal.serial';
  final FlutterSecureStorage _s;
  CredentialStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();

  Future<Credentials?> load() async {
    final raw = await _s.read(key: _key);
    if (raw != null) return Credentials.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    final u = await _s.read(key: _oldUser), p = await _s.read(key: _oldPass), sn = await _s.read(key: _oldSerial);
    if (u == null || p == null || sn == null) return null;
    return Credentials(username: u, passwordMd5: p, serial: sn);
  }

  Future<void> save(Credentials c) async {
    await _s.write(key: _key, value: jsonEncode(c.toJson()));
    for (final k in [_oldUser, _oldPass, _oldSerial]) {
      await _s.delete(key: k);
    }
  }

  Future<void> clear() async {
    for (final k in [_key, _oldUser, _oldPass, _oldSerial]) {
      await _s.delete(key: k);
    }
  }
}

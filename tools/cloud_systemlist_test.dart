// ignore_for_file: avoid_print
// Checks whether the E3/DC cloud API lists the account's systems, so the app could fill in the serial
// number after the portal login. Read-only: one login and one list request, nothing is stored.
// Usage: E3DC_USER=... E3DC_PASS=... dart run tools/cloud_systemlist_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

final api = Uri.parse('https://api.e3dc.com');

/// Replaces long token-like strings so the output can be shared.
String redact(String s) =>
    s.replaceAllMapped(RegExp(r'[A-Za-z0-9_\-]{30,}(\.[A-Za-z0-9_\-]+){0,2}'), (_) => '<redacted>');

Future<(int, Map<String, String>, String)> call(
  HttpClient http,
  String method,
  String path, {
  Map<String, String>? form,
  String? auth,
}) async {
  final req = await http.openUrl(method, api.resolve(path));
  if (auth != null) req.headers.set('authorization', auth);
  if (form != null) {
    req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
    req.write(
      form.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&'),
    );
  }
  final res = await req.close();
  final headers = <String, String>{};
  res.headers.forEach((k, v) => headers[k] = v.join(', '));
  return (res.statusCode, headers, await res.transform(utf8.decoder).join());
}

/// Finds a JWT in the login answer: body field, plain body or a header.
String? findToken(Map<String, String> headers, String body) {
  final jwt = RegExp(r'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+');
  final inBody = jwt.firstMatch(body)?.group(0);
  if (inBody != null) return inBody;
  for (final v in headers.values) {
    final m = jwt.firstMatch(v)?.group(0);
    if (m != null) return m;
  }
  return null;
}

Future<void> main() async {
  final env = Platform.environment;
  final user = env['E3DC_USER'], pass = env['E3DC_PASS'];
  if (user == null || pass == null) {
    stderr.writeln('Set E3DC_USER and E3DC_PASS.');
    exit(2);
  }
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final (st, hd, body) = await call(
      http,
      'POST',
      '/api/auth/',
      form: {'user': user, 'password': md5.convert(utf8.encode(pass)).toString()},
    );
    print('auth: HTTP $st');
    print('auth headers: ${hd.keys.join(', ')}');
    print('auth body: ${redact(body)}');
    final token = findToken(hd, body);
    if (token == null) {
      print('no token found in the login answer; stopping');
      return;
    }
    for (final auth in [token, 'Bearer $token']) {
      final (st2, _, body2) = await call(http, 'GET', '/api/systemList/', auth: auth);
      print('systemList (${auth.startsWith('Bearer') ? 'Bearer' : 'raw token'}): HTTP $st2');
      print(redact(body2));
      if (st2 == 200) break;
    }
  } finally {
    http.close(force: true);
  }
}

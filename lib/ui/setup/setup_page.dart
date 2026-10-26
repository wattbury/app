import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../../data/credentials.dart';
import '../../data/energy_source.dart';
import '../../theme/tokens.dart';
import '../widgets/cards.dart';

/// Connection wizard, step 1: portal tunnel login. Local RSCP follows in phase 3.
class SetupPage extends StatefulWidget {
  /// Called with verified credentials; the caller stores them and switches to the dashboard.
  final Future<void> Function(PortalCredentials) onConnected;
  final VoidCallback onDemo;

  /// Problem found at start-up, e.g. an unreachable keychain.
  final String? notice;
  const SetupPage({super.key, required this.onConnected, required this.onDemo, this.notice});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _user = TextEditingController(), _pass = TextEditingController(), _serial = TextEditingController();
  bool _busy = false, _hide = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_user, _pass, _serial]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _connect() async {
    final user = _user.text.trim(), pass = _pass.text, serial = _serial.text.trim();
    if (user.isEmpty || pass.isEmpty || serial.isEmpty) {
      setState(() => _error = 'Bitte alle drei Felder ausfüllen.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final creds = PortalCredentials(
      username: user,
      passwordMd5: md5.convert(utf8.encode(pass)).toString(),
      serial: serial,
    );
    final source = PortalSource(creds);
    try {
      await source.connect();
      await source.systemInfo();
    } catch (e) {
      await source.close();
      if (mounted) {
        setState(() {
          _error = 'Verbindung fehlgeschlagen: $e';
          _busy = false;
        });
      }
      return;
    }
    await source.close();
    try {
      await widget.onConnected(creds);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Verbunden, aber die Zugangsdaten ließen sich nicht im Schlüsselbund speichern: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.wb;
    InputDecoration deco(String label, {String? hint, Widget? suffix}) => InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: suffix,
      filled: true,
      fillColor: c.appBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.sep),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c.sep),
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('Verbindung einrichten', style: sora(26, weight: 700, color: c.fg)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                'Wattbury verbindet sich direkt mit deinem Hauskraftwerk. Die Zugangsdaten bleiben im Schlüsselbund dieses Geräts.',
                style: TextStyle(fontSize: 13, color: c.muted),
              ),
            ),
            if (widget.notice != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                child: Text(widget.notice!, style: TextStyle(fontSize: 12, color: c.crit)),
              ),
            const SizedBox(height: 12),
            WhiteCard(
              title: 'Über das E3/DC-Portal',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 4),
                  Text('Funktioniert überall, auch unterwegs.', style: TextStyle(fontSize: 12, color: c.muted)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _user,
                    decoration: deco('Portal-Benutzer', hint: 'name@beispiel.de'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _pass,
                    obscureText: _hide,
                    decoration: deco(
                      'Portal-Passwort',
                      suffix: IconButton(
                        icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _hide = !_hide),
                        tooltip: _hide ? 'Passwort zeigen' : 'Passwort verbergen',
                      ),
                    ),
                    autofillHints: const [AutofillHints.password],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _serial,
                    decoration: deco('Seriennummer', hint: 'S10-… (Typenschild oder my.e3dc.com)'),
                    onSubmitted: (_) => _connect(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: TextStyle(fontSize: 13, color: c.crit)),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _connect,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Verbinden', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            WhiteCard(
              title: 'Lokal im WLAN',
              trailing: 'folgt',
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Direkt per RSCP mit IP-Adresse und RSCP-Passwort, schneller und ohne E3/DC-Server. Kommt mit der nächsten Ausbaustufe.',
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _busy ? null : widget.onDemo,
              child: const Text('Erst mal mit Beispieldaten ansehen'),
            ),
          ],
        ),
      ),
    );
  }
}

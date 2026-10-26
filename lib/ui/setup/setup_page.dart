import 'package:flutter/material.dart';

import '../../data/credentials.dart';
import '../../data/energy_source.dart';
import '../../theme/tokens.dart';
import '../widgets/cards.dart';

/// Connection wizard: portal login (always), local RSCP (optional) and the serial for the portal
/// tunnel. With a local connection the serial is read from the unit, so nobody has to type it.
class SetupPage extends StatefulWidget {
  /// Called with verified credentials; the caller stores them and switches to the dashboard.
  final Future<void> Function(Credentials) onConnected;
  final VoidCallback onDemo;

  /// Existing settings when the user edits the connection; passwords are not prefilled.
  final Credentials? initial;
  final VoidCallback? onCancel;

  /// Problem found at start-up, e.g. an unreachable keychain.
  final String? notice;
  const SetupPage({
    super.key,
    required this.onConnected,
    required this.onDemo,
    this.initial,
    this.onCancel,
    this.notice,
  });

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  late final _user = TextEditingController(text: widget.initial?.username);
  final _pass = TextEditingController();
  late final _serial = TextEditingController(text: widget.initial?.serial);
  late final _host = TextEditingController(text: widget.initial?.local?.host);
  late final _rscp = TextEditingController(text: widget.initial?.local?.rscpPassword);
  bool _busy = false, _hide = true;
  String? _error, _status;

  @override
  void dispose() {
    for (final c in [_user, _pass, _serial, _host, _rscp]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _connect() async {
    final user = _user.text.trim(), pass = _pass.text, host = _host.text.trim(), rscp = _rscp.text;
    var serial = _serial.text.trim();
    String? problem;
    if (user.isEmpty || pass.isEmpty) {
      problem = 'Bitte Portal-Benutzer und Passwort eingeben.';
    } else if (host.isEmpty != rscp.isEmpty) {
      problem = 'Für die lokale Verbindung braucht es IP-Adresse und RSCP-Passwort.';
    } else if (host.isEmpty && serial.isEmpty) {
      problem = 'Bitte die Seriennummer eingeben oder die lokale Verbindung einrichten.';
    }
    setState(() {
      _error = problem;
      _status = null;
    });
    if (problem != null) return;

    setState(() => _busy = true);
    final local = host.isEmpty ? null : LocalConfig(host: host, rscpPassword: rscp);
    var creds = Credentials.create(
      username: user,
      password: pass,
      serial: serial.isEmpty ? null : serial,
      local: local,
    );

    Future<String?> test(RscpSource s, String what) async {
      setState(() => _status = '$what wird geprüft …');
      try {
        await s.connect();
        return (await s.systemInfo()).serial;
      } catch (e) {
        if (mounted) setState(() => _error = '$what: ${_explain(e)}');
        return null;
      } finally {
        await s.close();
      }
    }

    if (local != null) {
      final sn = await test(RscpSource.local(creds), 'Lokale Verbindung');
      if (sn == null) return _done();
      if (serial.isEmpty && sn.isNotEmpty) {
        serial = sn;
        _serial.text = sn;
        creds = creds.withSerial(sn);
      }
    } else if (await test(RscpSource.portal(creds), 'Portal-Verbindung') == null) {
      return _done();
    }

    try {
      await widget.onConnected(creds);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Verbunden, aber die Zugangsdaten ließen sich nicht im Schlüsselbund speichern: $e');
      }
    }
    _done();
  }

  void _done() {
    if (mounted) {
      setState(() {
        _busy = false;
        _status = null;
      });
    }
  }

  static String _explain(Object e) {
    final s = e.toString();
    if (s.contains('RSCP password wrong')) return 'keine Antwort auf die Anmeldung. Stimmt das RSCP-Passwort?';
    if (s.contains('login rejected')) return 'Anmeldung abgelehnt. Stimmen Portal-Benutzer und Passwort?';
    if (s.contains('SocketException') || s.contains('Connection refused') || s.contains('timed out')) {
      return 'Hauskraftwerk nicht erreichbar. Stimmt die IP-Adresse, und ist das Gerät im selben Netz?';
    }
    return s;
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
    Widget hint(String s) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Text(s, style: TextStyle(fontSize: 12, color: c.muted)),
    );
    const gap = SizedBox(height: 10);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
          children: [
            if (widget.onCancel != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : widget.onCancel,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Zurück'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('Verbindung einrichten', style: sora(26, weight: 700, color: c.fg)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                'Wattbury verbindet sich direkt mit deinem Hauskraftwerk: zu Hause im WLAN, unterwegs über das E3/DC-Portal. '
                'Die Zugangsdaten bleiben im Schlüsselbund dieses Geräts.',
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
              title: 'E3/DC-Login',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hint('Wie im Portal und in der E3/DC-App. Wird für beide Verbindungsarten gebraucht.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _user,
                    decoration: deco('Portal-Benutzer', hint: 'name@beispiel.de'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                  ),
                  gap,
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
                ],
              ),
            ),
            gap,
            WhiteCard(
              title: 'Zu Hause im WLAN',
              trailing: 'empfohlen',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hint('Direkt per RSCP, jede Sekunde neue Werte, ohne E3/DC-Server. Liest auch die Seriennummer aus.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _host,
                    decoration: deco('IP-Adresse des Hauskraftwerks', hint: '192.168.178.40'),
                    keyboardType: TextInputType.url,
                  ),
                  gap,
                  TextField(controller: _rscp, obscureText: _hide, decoration: deco('RSCP-Passwort')),
                  hint('Am Display des Hauskraftwerks unter Personalisieren › Benutzerprofil festlegen.'),
                ],
              ),
            ),
            gap,
            WhiteCard(
              title: 'Unterwegs über das Portal',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hint(
                    'Funktioniert überall. Braucht die Seriennummer, die mit der lokalen Verbindung automatisch kommt.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _serial,
                    decoration: deco('Seriennummer', hint: 'S10-…'),
                    onSubmitted: (_) => _connect(),
                  ),
                  hint(
                    'Steht im Portal my.e3dc.com, im Display des Hauskraftwerks und auf dem Typenschild. '
                    'Leer lassen, wenn oben die lokale Verbindung eingetragen ist.',
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(_error!, style: TextStyle(fontSize: 13, color: c.crit)),
              ),
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
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                        if (_status != null) ...[const SizedBox(width: 10), Text(_status!)],
                      ],
                    )
                  : const Text('Verbinden', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            if (widget.onCancel == null) ...[
              gap,
              TextButton(
                onPressed: _busy ? null : widget.onDemo,
                child: const Text('Erst mal mit Beispieldaten ansehen'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

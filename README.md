# Wattbury

Open-Source-App für E3/DC Hauskraftwerke (S10-Familie). Live-Werte, Energiefluss, Verlauf und Smart-Funktionen direkt vom Gerät, im WLAN per RSCP und unterwegs über den Portal-Tunnel. Keine eigene Cloud, keine Zugangsdaten außerhalb des Geräts.

Status: erste lauffähige App (Flutter, Ziel iOS, entwickelt und getestet unter Linux): Verbindung über den Portal-Tunnel, Energiemonitor mit Live-Werten, Einstellungen, Demo-Modus.

- [docs/01-rahmenbedingungen.md](docs/01-rahmenbedingungen.md) – Datenquellen, Technik, Apple-Konto, offene Entscheidungen
- [docs/02-architektur.md](docs/02-architektur.md) – App direkt am Hauskraftwerk, optionale Bridge, Roadmap
- [docs/03-funktionsumfang.md](docs/03-funktionsumfang.md) – Screens, Funktionen, MVP, Farbwelt „Signal“
- [docs/04-portal-tunnel.md](docs/04-portal-tunnel.md) – RSCP über das E3/DC-Portal, Testergebnisse
- [design/clickdummy.html](design/clickdummy.html) – interaktiver Click-Dummy (im Browser öffnen)
- [tools/portal-tunnel-test.py](tools/portal-tunnel-test.py) – Lese-Test der Portal-Verbindung mit python-e3dc

Das Protokoll steckt im eigenständigen Paket [wattbury/openrscp](https://github.com/wattbury/openrscp).

## Entwickeln

```bash
flutter pub get
flutter run -d linux
```

Unter Linux braucht der Schlüsselbund `libsecret-1-dev` zum Bauen und einen laufenden Secret Service (z. B. `gnome-keyring`) zur Laufzeit. Ohne Zugangsdaten zeigt „Erst mal mit Beispieldaten ansehen“ einen Demo-Modus.

Für lokale Arbeit am Protokoll-Paket daneben auschecken und eine `pubspec_overrides.yaml` anlegen (nicht versioniert):

```yaml
dependency_overrides:
  openrscp:
    path: ../openrscp
```

## Web-App (PWA)

```bash
flutter run -d web-server --web-port 8080
```

Im Browser gibt es nur den Portal-Tunnel, denn Browser können keine TCP-Verbindung zum Hauskraftwerk öffnen. Benachrichtigungen erscheinen nur als Banner, solange die Seite offen ist. Die Zugangsdaten liegen verschlüsselt im Browser, das setzt HTTPS voraus (oder `localhost`).

Jeder Push auf `main` baut die PWA und lädt sie per FTPS auf wattbury.de hoch ([deploy-web.yml](.github/workflows/deploy-web.yml), Secrets `FTP_SERVER`, `FTP_USERNAME`, `FTP_PASSWORD`). HTTPS-Weiterleitung, Content-Security-Policy und Cache-Regeln stehen in [web/.htaccess](web/.htaccess).

## Hinweis

Wattbury ist nicht mit E3/DC oder HagerEnergy GmbH verbunden. „E3/DC“ ist eine Marke ihres Inhabers.

## Lizenz

MIT, siehe [LICENSE](LICENSE).

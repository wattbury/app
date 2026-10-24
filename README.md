# Wattbury

Open-Source-App für E3/DC Hauskraftwerke (S10-Familie). Live-Werte, Energiefluss, Verlauf und Smart-Funktionen direkt vom Gerät, im WLAN per RSCP und unterwegs über den Portal-Tunnel. Keine eigene Cloud, keine Zugangsdaten außerhalb des Geräts.

Status: Konzept und Click-Dummy fertig, App in Entwicklung (Flutter, Ziel iOS, Android läuft mit).

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

Für lokale Arbeit am Protokoll-Paket daneben auschecken und eine `pubspec_overrides.yaml` anlegen (nicht versioniert):

```yaml
dependency_overrides:
  openrscp:
    path: ../openrscp
```

## Hinweis

Wattbury ist nicht mit E3/DC oder HagerEnergy GmbH verbunden. „E3/DC“ ist eine Marke ihres Inhabers.

## Lizenz

MIT, siehe [LICENSE](LICENSE).

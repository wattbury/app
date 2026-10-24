# 04 · RSCP über das E3/DC-Portal („Tunnel“)

Stand: 24.10.2026. Anlass: my4E bietet seit Version 2.18.1 (Juni 2026) eine „RSCP-Tunnelverbindung über das E3/DC-Portal“ ohne lokale IP oder VPN. Geprüft wurde, wie das funktioniert und ob wir es selbst nutzen können.

## Ergebnis in einem Satz

Das E3/DC-Portal betreibt ein **Websocket-Relay** unter `wss://s10.e3dc.com/ws`, das RSCP-Frames mit Portal-Login und Seriennummer an das eigene Hauskraftwerk durchreicht. Es ist undokumentiert, aber seit Jahren in `python-e3dc` nachgebaut und Stand Juni/Juli 2026 funktionsfähig. Mit hoher Wahrscheinlichkeit nutzt my4E genau dieses Relay.

## Verifizierte Fakten

| | |
|---|---|
| Endpunkt | `wss://s10.e3dc.com/ws` (AWS, antwortet am 24.10.2026 mit HTTP 400 auf einen unvollständigen Handshake, d. h. der Dienst ist erreichbar) |
| Zugangsdaten | Portal-Benutzer, **MD5** des Portal-Passworts, Seriennummer mit Präfix `S10-`. **Kein RSCP-Passwort, kein Cloud-Registry-Key.** Klartext-Passwörter werden seit Juli 2026 abgewiesen. |
| Verschlüsselung | nur TLS; die lokale Rijndael-256-Verschlüsselung entfällt |
| Ablauf | Verbinden → Server `RSCP_REQ_SET_PROTOCOL_VERSION` (muss gespiegelt werden, seit 2026) → `SERVER_REGISTER_CONNECTION` → Client `SERVER_CONNECTION_REGISTERED` → Server fragt `INFO_*` ab, Client antwortet mit Pseudo-Geräteinfo → Client `SERVER_REQ_NEW_VIRTUAL_CONNECTION` (User, MD5-Passwort, Seriennummer, `SERVER_TYPE=4`) → Server liefert virtuelle Verbindungs-ID (−1 = Login falsch) → danach jeder RSCP-Frame in `SERVER_REQ_RSCP_CMD` verpackt; regelmäßig `SERVER_REQ_PING` / `SERVER_PING`. Seit 2026 kompakter 8-Byte-Frame-Header statt 18 Byte. |
| Lesen | Dieselben Tags wie lokal (`EMS_REQ_POWER_*`, `BAT_*`, `PVI_*`, `WB_*`, `DB_*`); `python-e3dc` nutzt im Web-Modus denselben Code wie lokal |
| Schreiben | Technisch werden die Frames durchgereicht; welche Berechtigungsstufe (authLevel) die virtuelle Verbindung hat, ist nicht dokumentiert. Muss am eigenen Gerät getestet werden. |
| Referenzimplementierung | `python-e3dc` **GitHub-Stand** (PyPI 0.10.0 fehlt der Juni-2026-Fix), Datei `e3dc/_e3dc_rscp_web.py`, ca. 430 Zeilen. Stolperfalle: Der Parameter `isPasswordMd5` im Hauptkonstruktor ist invertiert; `False` sendet Klartext. Der `_rscpLib`-Debug-Logger gibt Passwörter im Klartext aus. |
| Stabilität | Drei Protokolländerungen durch E3/DC in 2024–2026 (Pfad `/ws/`→`/ws`, Protokollversion + kompakter Header, MD5-Pflicht). Jede hat die Community-Bibliothek für Wochen bis Monate gebrochen. |
| Rechtliches | Die RSCP-Spezifikation trägt eine Vertraulichkeitsklausel; das Relay ist kein dokumentiertes Angebot. Nutzung nur für die eigene Anlage mit eigenem Login. |

Was my4E dazu dokumentiert: Zugangsdaten „Portal-Login + Seriennummer“, Reihenfolge „lokal RSCP → Tunnel → Cloud-Datenschnittstelle“, Verfügbarkeit „abhängig von E3/DC-System, Netzwerk und Portal-Verfügbarkeit“. Keine Angaben zu Intervall oder Steuerfunktionen über den Tunnel. Quellen: App-Store-Versionshistorie 2.18.1/2.18.5, Wissensdatenbank Artikel 124, Beta-Formular.

Quellen (Protokoll): https://python-e3dc.readthedocs.io/en/latest/_modules/e3dc/_e3dc_rscp_web.html · https://github.com/fsantini/python-e3dc/pull/142 · https://github.com/fsantini/python-e3dc/issues/143 · https://github.com/fsantini/python-e3dc/issues/106

## Testergebnis 24.10.2026 (eigene Anlage)

| | |
|---|---|
| Verbindungsaufbau | 1,0 s bis zur virtuellen Verbindung (Protokollversion 2, Registrierung, Geräteabfrage, Login) |
| Berechtigung | `virtAuthLevel=10` = **USER**, dieselbe Stufe wie ein lokaler Login mit Portal-Benutzer. Lese- und Benutzer-Setter sollten damit möglich sein; Setter noch nicht getestet. |
| Live-Abfrage | 1,0–1,2 s pro vollständigem `poll()` (mehrere EMS-Tags), damit 1-s-Intervall wie lokal |
| Systeminfo | S10E, Firmware S10_2026_027, 10,74 kWp, 13,1 kWh, max. Laden/Entladen 4.500 W, keine Abregelung |
| Werte | Autarkie, Eigenverbrauch, SOC, Leistungen Haus/Batterie/Solar/Netz/Wallbox/Zusatzquelle, Zeitstempel der Anlage |
| Batterie (`BAT_*`) | 0,5 s · 4 Module (ATL3_3), ASOC 92,7 %, 906 Zyklen, je Modul Strom, Kapazität, Temperaturgrenzen, Firmware |
| Wechselrichter (`PVI_*`) | 0,9 s · 3 Phasen, 2 Strings, Phasenwerte (P, U, I, S, Q), Energiezähler, Netzstatus |
| Leistungseinstellungen | 0,1 s · max. Laden/Entladen 1.500 W (Limits nicht aktiv), PowerSave an, wetterabhängiges Laden aus |
| Wallbox (`WB_*`) | 0,2 s · praktisch leer (`appSoftware: null`), **vermutlich keine Wallbox installiert** |
| DB Tageswert (`DB_REQ_HISTORY_DATA_DAY`) | **0,1 s** · Solar 18,75 kWh, Verbrauch 19,11 kWh, Netzbezug 7,58, Einspeisung 1,36, Batterie laden 10,84, entladen 6,46, Autarkie 60 %, Eigenverbrauch 89 %. Achtung Benennung: `DB_GRID_POWER_OUT` ist der **Bezug**, `DB_GRID_POWER_IN` die **Einspeisung** (Sicht des Netzes); python-e3dc dokumentiert das verdreht. |

Fazit: Alle Lesepfade funktionieren über den Tunnel, die Datenbank des S10 antwortet schnell genug, um Diagramme direkt daraus zu füllen. Zusatzquellen sind nicht vorhanden (`externalSourceAvailable: 0`).

Stolperfallen, die beim Test aufgefallen sind: PyPI-Version 0.10.0 kann das Relay-Protokoll nicht (GitHub-Stand nötig); `isPasswordMd5=False` sendet Klartext und wird abgelehnt; der `_rscpLib`-Debug-Logger schreibt Passwörter ins Log.

### Zweiter Test mit der eigenen Dart-Implementierung (openrscp, 24.10.2026, 22:42)

| | python-e3dc | openrscp |
|---|---|---|
| Verbindungsaufbau | 1,0 s | **0,39 s** |
| Live-Abfrage (10 EMS-Werte) | 1,0–1,2 s | **51–68 ms** |
| Systeminfo, Einstellungen, Tagesbilanz | ok | ok |

Der Unterschied kommt daher, dass openrscp alle zehn Live-Tags in **einem** Frame schickt, python-e3dc dagegen jedes Tag einzeln mit eigenem Rundlauf über das Relay. Ein 1-s-Intervall erzeugt damit nur etwa 5 % Auslastung der Verbindung. Gemessen: Produktionsdatum KW29 2022, Abregelung bei 100 % / 10.740 W (keine Begrenzung), Tagesbilanz bis 22:42 Solar 18,75 kWh, Haus 21,03 kWh, Bezug 7,66 kWh, Einspeisung 1,43 kWh, Autarkie 64 %.

### Anlagendaten per RSCP (`openrscp` `example/system_probe.dart`, 25.10.2026)

| Bereich | Ergebnis |
|---|---|
| Spitzenleistung | `EMS_INSTALLED_PEAK_POWER` 10.740 W |
| Systemkennwerte (`EMS_REQ_GET_SYS_SPECS`) | Batteriekapazität 13.107 Wh, max. AC 12.000 W, Laden/Entladen max. 4.500 W, empfohlene Mindestgrenzen 2.200 / 1.100 W, Hybridmodus ja; `maxPvPower` nicht verfügbar |
| Wechselrichter | 2 DC-Eingänge (Tracker), 3 Phasen, max. 4.000 VA je Phase. `PVI_USED_STRING_COUNT` meldet **1**, obwohl beide belegt sind |
| Tracker 1 | Leistung, Spannung, Strom live; max. 6.000 W; Lebenszeit-Ertrag 30.882 kWh; trägt zwei parallele Strings |
| Tracker 2 | nachts 93 V Restspannung; max. 6.000 W; Lebenszeit-Ertrag 1.121 kWh (später nachgerüstet) |
| Batterie | 4 Module, Nennkapazität 256 Ah, nutzbar 202,8 Ah |
| Anlagenadresse (`INFO_REQ_GET_FACILITY`) | Postleitzahl, Ort, Land, Name, Straße, Hausnummer, Telefon und E-Mail vorhanden. Die App nutzt nur Postleitzahl, Ort und Land. |

Folgerungen: Anzahl der Strings, Spitzenleistung, Batterie und Wechselrichter kommen aus dem S10. Ausrichtung, Neigung und kWp je String sowie der genaue Standort sind manuell. Eine Aufteilung der kWp nach Lebenszeit-Ertrag scheidet aus: Die Anteile von 96,5 % zu 3,5 % spiegeln nur wider, dass Tracker 2 später dazukam. Belegte Tracker erkennt `openrscp` `pvTrackers()` an Messwerten (Ertrag, Leistung oder mindestens 20 V), nicht am gemeldeten Zähler. Parallele Strings an einem Tracker sieht das S10 nicht; sie werden im Schritt „Anlage“ als Module × Wp eingetragen.

## Selbst testen

Im Projekt liegt ein reines Lese-Skript, das die Tunnelverbindung mit deinen Portal-Zugangsdaten aufbaut und Live-Werte, Systeminfo, Batterie, PV, Leistungseinstellungen, Wallbox und einen DB-Tageswert abfragt:

```bash
E3DC_USER='portal@mail' E3DC_PASS='portal-passwort' E3DC_SN='S10-1234567890' .venv/bin/python tools/portal-tunnel-test.py
```

Die Seriennummer steht auf dem Typenschild, im S10-Menü und im Portal. Das Skript speichert nichts und sendet keine Setter.

## Konsequenz für die Architektur

Der Tunnel ändert die Transportfrage, nicht die Rollenverteilung:

| | **Bridge zu Hause** (lokales RSCP) | **Bridge mit Portal-Tunnel** (kann irgendwo laufen) | **App direkt an den Tunnel** (my4E-Weg) |
|---|---|---|---|
| Hardware zu Hause | nötig (Pi/NAS) | nicht nötig; läuft auch auf einem eigenen VPS | keine |
| Unterwegs | VPN (Tailscale) | direkt | direkt |
| Verschlüsselung | Rijndael-256 selbst implementieren (Go-Lib vorhanden) | TLS + RSCP-TLV, einfacher | TLS + RSCP-TLV in Swift/TS selbst bauen |
| Abhängigkeit von E3/DC-Infrastruktur | keine | hoch, undokumentiert | hoch, undokumentiert |
| Bei Protokolländerung anpassen | nichts | nur die Bridge | App-Update nötig |
| Verlauf, Benachrichtigungen, Prognose | ja | ja | nein (kein 24/7-Prozess) |
| Steuerung | sicher | zu testen | zu testen |

**Empfehlung:** Bridge beibehalten, aber den RSCP-Transport austauschbar machen: `local` (TCP 5033 + Rijndael) und `portal` (Websocket-Relay). Die App spricht weiter nur mit der Bridge. Reihenfolge:

1. Tunnel mit dem Skript testen (Lesen, Latenz, und einmal einen harmlosen Setter wie die Notstromreserve auf den aktuellen Wert, um die Berechtigung zu prüfen).
2. Funktioniert er, kann die Bridge zunächst **ohne Hardware zu Hause** auf einem beliebigen Rechner laufen, z. B. dem Entwicklungsrechner oder einem kleinen VPS, mit dem Tunnel als Transport. Ein Pi zu Hause bleibt der robustere Endzustand, weil er E3/DC-Änderungen gegenüber unempfindlich ist.
3. Die Bridge wechselt automatisch: lokal, wenn erreichbar, sonst Tunnel. Beim Tunnel gilt ein schonenderes Intervall (2–5 s statt 1 s), weil die Last über E3/DC-Server läuft.

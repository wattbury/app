# 01 · Rahmenbedingungen

Stand: 24.10.2026

## Ausgangslage

- Hauskraftwerk **E3/DC S10E** im Keller, erreichbar im Heimnetz per **RSCP** (Port 5033).
- Cloud-Konto auf **my.e3dc.com**; dort lässt sich ein *Cloud-Registry-Key* erzeugen (Dashboard › Rechteverwaltung › Cloud-Registry-Key).
- Bisher genutzte App: **my4E** (Totalidea Software, iOS only). Premium steigt auf **29,99 €/Jahr** (2,99 €/Monat), Begründung des Entwicklers: die neue E3/DC-Datenschnittstelle kostet pro Anlage und Monat.
- Ziel: eigene App im Stil der **kommenden my4E-Version** (Vorschau https://info.my4e.de/vorschau.html), ohne laufende Kosten, ohne Fremd-Backend für Zugangsdaten.

## Was die Datenquellen hergeben

| | **RSCP lokal** | **E3/DC Cloud-API** (api.e3dc.com) |
|---|---|---|
| Zugang | IP des S10 + Portal-Benutzer/-Passwort + RSCP-Passwort (am S10: Personalisieren › Benutzerprofil) | `POST /api/auth` mit Benutzer + **MD5** des Portal-Passworts → JWT; Anlage per Seriennummer + Cloud-Registry-Key registrieren |
| Richtung | **lesen und schreiben** | **nur lesen** |
| Live-Auflösung | ~1 s (Polling) | 15 s, Daten kommen über den Upload des S10 (Verzögerung Minuten möglich) |
| Verlauf | DB-Abfragen Tag/Woche/Monat/Jahr; langsam, CPU-lastig auf dem S10 | 15-Minuten-Zeilen (`historyvalues`, `powermetervalues`, `wallboxHistory`); Aggregation selbst machen |
| Details | PVI je String, BAT je Modul (SOH, Temp, Zyklen), PM je Phase, EMS-Status, Notstrom, Wallbox | Leistung je Tracker/Phase, SOC, Wallbox-Leistung, Stammdaten (`systemProperties`), Einspeisebegrenzung |
| Steuerung | Lade-/Entladeleistung, Sperrzeiten, Notstromreserve, Wallbox (Sonnen-/Mischmodus, Phasen, Strom, Start/Stop), manuelles Laden | keine |
| Erreichbarkeit | nur im selben Subnetz (VPN nötig für unterwegs) | überall |
| Verlässlichkeit | stabil seit 2015, mehrere Open-Source-Implementierungen | undokumentiert („Cloud2Cloud“-Schnittstelle), Auth 2024 still geändert (Test 26.10.2026: `POST /api/auth` mit Portal-Login + MD5 liefert 403, daher auch keine `systemList` zum automatischen Auslesen der Seriennummer, siehe `tools/cloud_systemlist_test.dart`), my4E meldet Oktober 2026 unzuverlässige Datendienste |
| Verschlüsselung | Rijndael **256-Bit-Block** (kein Standard-AES), Key = RSCP-Passwort mit 0xFF auf 32 Byte aufgefüllt | TLS |

Die Swagger-Spezifikation der Cloud-API liegt unter [`reference/e3dc-cloud-api-swagger.json`](reference/e3dc-cloud-api-swagger.json).

**Konsequenz:** RSCP ist die Primärquelle (Live, Verlauf, Steuerung). Die Cloud-API ist höchstens ein Fallback für unterwegs ohne VPN, nur lesend, und sollte nicht tragend sein.

## Technische Rahmenbedingungen der Entwicklung

- Entwicklungsrechner: **WSL2 / Linux** mit Node 25, Bun, Python 3.11, Go 1.23. **Kein Xcode, kein macOS, kein Docker.**
- Für eine native iOS-App ist ein Mac (oder ein macOS-Runner in GitHub Actions / Xcode Cloud, 25 h/Monat kostenlos) zum Bauen und Signieren nötig.
- Verteilung auf das eigene iPhone:
  - Ohne Apple Developer Program: kostenloses Signieren, App läuft **7 Tage**, dann neu installieren. Keine Push-Benachrichtigungen, keine Widgets-Einschränkung, aber unpraktisch.
  - Mit **Apple Developer Program (99 €/Jahr)**: TestFlight (90 Tage, automatisch erneuerbar), Push, Widgets, Watch. Das ist mehr als my4E Premium, aber deckt beliebig viele eigene Apps.
- iOS-Apps dürfen im Hintergrund nicht dauerhaft pollen. **Benachrichtigungen** (SOC niedrig, Netzbezug hoch, Anlage offline) brauchen daher einen Dienst zu Hause, der 24/7 läuft.
- Für RSCP in Swift gibt es **keine fertige Bibliothek**; Rijndael-256 müsste selbst implementiert werden. In Go (`spali/go-rscp`), Python (`fsantini/python-e3dc`) und C++ (`pvtom/rscp2mqtt`) gibt es gepflegte Implementierungen.

## Optionen für die App-Technologie

| Option | Widgets / Watch / Live Activities | Build-Umgebung | Verteilung | Bewertung |
|---|---|---|---|---|
| **A · SwiftUI nativ** | ja, alles | Mac oder Cloud-CI | TestFlight / Sideload | Beste Nutzererfahrung, Vorbild my4E ist nativ. Höchster Einstiegsaufwand ohne Mac. |
| **B · Flutter / React Native / Capacitor** | nur mit nativen Erweiterungen | Mac trotzdem für iOS-Build nötig | wie A | Kein Vorteil gegenüber A bei nur einer Zielplattform. |
| **C · PWA (Web-App, „Zum Home-Bildschirm“)** | keine Widgets, keine Watch; Web-Push ab iOS 16.4 | direkt hier in WSL | kein App Store, kein Apple-Konto | Sofort baubar, 0 € Kosten, Click-Dummy ist schon Web. Fühlt sich weniger nach „echter App“ an. |

**Entscheidung (24.10.2026):** **Flutter-App** (Entwicklung in WSL als Linux-Fenster und auf Android, iOS-Builds über GitHub Actions auf macOS-Runnern, öffentliches Repo), die direkt mit dem Hauskraftwerk spricht (lokal und über den Portal-Tunnel, siehe [04-portal-tunnel](04-portal-tunnel.md)). Eine Bridge ist nur ein späteres, optionales Modul für Benachrichtigungen und Langzeitverlauf. Eine Web-App scheidet aus, weil sie kein rohes TCP sprechen kann.

## Apple-Konto: kostenlos oder Developer Program?

Zum Bauen ist in jedem Fall ein Mac mit Xcode nötig (oder ein macOS-Runner in der Cloud). Für das Installieren auf dem eigenen iPhone gibt es zwei Wege:

| | **Kostenlos** (Apple-ID, „Personal Team“) | **Apple Developer Program** (99 €/Jahr) |
|---|---|---|
| App auf dem eigenen iPhone | ja, über Xcode per Kabel/WLAN | ja, zusätzlich über TestFlight |
| Gültigkeit der Signatur | **7 Tage**, danach erneut aus Xcode installieren (oder AltStore/SideStore mit AltServer auf Windows/Mac im selben WLAN, das automatisch nachsigniert) | TestFlight-Build 90 Tage, Ad-hoc-Profil 1 Jahr |
| Gleichzeitig installierte eigene Apps | max. 3, max. 10 App-IDs pro Woche | unbegrenzt |
| Push-Benachrichtigungen (APNs) | **nein** | ja |
| Widgets, Watch-App | technisch möglich, aber App-Groups und weitere Capabilities sind beim Personal Team eingeschränkt; im Einzelfall zu prüfen | ja |
| iCloud, Sign in with Apple, Background-Modi | eingeschränkt bzw. nein | ja |
| Cloud-Builds (GitHub Actions, Xcode Cloud) mit Signierung | praktisch nicht, da keine Zertifikate/Profile außerhalb von Xcode | ja |

**Antwort auf die Frage:** Nein, für den Start auf dem eigenen Gerät ist das Developer Program nicht zwingend. Man bezahlt den kostenlosen Weg mit dem wöchentlichen Neusignieren und dem Verzicht auf Push. Sobald Benachrichtigungen, Widgets ohne Bastelei, TestFlight oder Cloud-Builds gewünscht sind, wird das Konto nötig. Empfehlung: Phase 2 und 3 kostenlos starten, das Konto erst kaufen, wenn Push oder Widgets anstehen.

## Fernzugriff (unterwegs)

| Variante | Aufwand | Sicherheit | Bemerkung |
|---|---|---|---|
| **Tailscale / WireGuard** zur Bridge | gering | sehr gut (kein offener Port) | Empfehlung. Tailscale-App auf dem iPhone, Bridge im Tailnet. |
| Reverse-Proxy mit HTTPS + Token | mittel | gut, wenn sauber | Offener Port 443 zu Hause nötig (DynDNS). |
| E3/DC Cloud-API als Fallback | gering | ok | Nur lesend, 15 s/15 min, unzuverlässig. Optional. |

## Nicht-funktionale Anforderungen

- **Zugangsdaten** (Portal-Login, RSCP-Passwort) liegen nur auf der Bridge (Konfigurationsdatei mit restriktiven Rechten) bzw. im iOS-Schlüsselbund. Kein Fremdserver.
- **Genau eine RSCP-Sitzung** von der Bridge zum S10 (Keep-Alive), alle Clients hängen an der Bridge. Ein hartes Limit ist nicht dokumentiert, aber mehrere Poller belasten das S10 unnötig.
- **Verlaufsdaten** speichert die Bridge selbst (SQLite), in 10-s-Auflösung für 7 Tage und 15-min-Aggregaten dauerhaft. DB-Abfragen am S10 nur zum Nachladen der Historie vor Inbetriebnahme der Bridge.
- **Setter** werden immer zurückgelesen und erst dann als übernommen angezeigt. `EMS_REQ_SET_POWER` ist nicht persistent und wird deshalb bewusst nicht als Dauerfunktion angeboten.
- Laufende Kosten: 0 € (plus optional Apple Developer Program).

## Offene Entscheidungen

| # | Frage | Empfehlung |
|---|---|---|
| 1 | Gibt es zu Hause einen Rechner, der 24/7 läuft (Raspberry Pi, NAS, Home Assistant)? | Erst relevant, wenn die optionale Bridge gebaut wird. |
| 2 | Steht ein Mac zur Verfügung? | **Offen, entscheidend.** Ohne Mac: macOS-Runner in GitHub Actions oder Xcode Cloud, dann ist das Developer Program praktisch Pflicht. |
| 3 | Fernzugriff | Erledigt: Portal-Tunnel, kein VPN nötig. |
| 4 | Wird Home Assistant / MQTT bereits genutzt? | Dann Bridge zusätzlich als MQTT-Publisher; sonst weglassen. |
| 5 | Wallbox, externe Zähler, Smart-Home-Geräte am S10 vorhanden? | Bestimmt, welche Karten im Dashboard real befüllt werden. |
| 6 | Dynamischer Stromtarif (Tibber, aWATTar)? | Bestimmt, ob die Börsenpreis-Karte gebraucht wird. |
| 7 | Welche my4E-Funktionen werden wirklich genutzt? | MVP entsprechend schneiden (siehe 03-funktionsumfang). |

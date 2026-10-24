# 03 · Funktionsumfang und Screens

Orientierung: my4E Premium und die kommende my4E-Version (Vorschau Oktober 2026). Spalte „Quelle“ nennt den RSCP-Bereich bzw. Cloud-Endpunkt, Spalte „Phase“ die Roadmap-Phase aus [02-architektur](02-architektur.md).

## Screens

### 1 · Energiemonitor (Dashboard)

Vertikal gestapelte Farbkarten, frei sortier- und ausblendbar, eigenes Layout für iPhone und iPad. Farblogik aus der my4E-Vorschau: Schieferblau = Prognose/Information, Weinrot = Verbrauch/Batterie/Wallbox, Grün = Netz, Orange = Solar.

| Karte | Inhalt | Quelle | Phase |
|---|---|---|---|
| Solar + Prognose | Karussell: Produktion (gesamt, je Tracker, heute kWh) · Ertrag je kWp · Tracker-Details. Darunter Prognose heute/morgen mit Fortschrittsbalken, Wetter-Chip, Buttons Diagramm/Analyse | EMS_POWER_PV, PVI; forecast.solar | 1–2 |
| Batterie | Ring mit SOC und kWh, Lade-/Entladeleistung, „voll/leer gegen“, Autarkie heute, heute geladen/entladen. **Tippen öffnet ein Overlay auf der Karte** mit Temperatur, Batteriezustand (SOH) und den Buttons Statistik & Info sowie Smart-Funktionen | EMS, BAT, DB | 1–2 |
| Netz | Leistung mit Richtung, heute Bezug/Einspeisung | EMS_POWER_GRID, PM | 1 |
| Haus | Leistung, heute Direkt/Gesamt | EMS_POWER_HOME | 1 |
| Wallbox | Leistung gesamt/solar, Solaranteil, heute geladen Netz/Solar, Button Steuerung. **Nur sichtbar, wenn das System eine Wallbox meldet** (`WB_DEVICE_STATE` verbunden oder App-Software-Version, `openrscp` `detectWallboxes()`); gilt für Dashboard, Energiefluss, Smart-Funktionen und Sheets. Einstellung „Geräte am Hauskraftwerk“: Automatisch / Anzeigen / Ausblenden. Bei der eigenen Anlage wird keine gemeldet. | WB | 2 |
| Ext. Verbrauch / Ext. Quellen | Leistung, heute, Geräteliste | PM, EMS_POWER_ADD | 2 |
| Börsenstrompreise | aktuelle/nächste Stunde, Tagestief, Details | Tibber/aWATTar | 4 |
| Monatsstatistik | Pastell-KPIs (Autarkie, Direktverbrauch, Solar, Netzbezug, Einspeisung), Tagesproduktion als Mini-Balken mit Ø/Max | Bridge-Store | 2 |
| Toolbar (schwebend) | Monitor · Diagramme · Energiefluss · Smart-Funktionen · Zeitstempel/Verbindung | | 3 |

### 2 · Diagramme

| Funktion | Phase |
|---|---|
| Zeitraum Tag / Woche / Monat / Jahr / frei, Blättern ‹ › | 3 |
| Gestapelte Balken: Quellen oben (Solar, Netzbezug, Batterie entladen), Senken unten (Verbrauch, Einspeisung, Batterie laden), Wallbox optional | 3 |
| Autarkie-Linie, Legende zum Ausblenden, Tooltip | 3 |
| Bilanz-KPIs und Kosten (Einspeisevergütung, Bezugskosten, Ersparnis) | 3 |
| Energiefluss (Chord) je Zeitraum, Heatmap Stunde × Tag, Vorjahresvergleich, Donuts | 4 |
| Export CSV / PDF / Bild | 4 |

### 3 · Energiefluss (live)

Das Hauskraftwerk (S10 E) ist der Mittelpunkt, an dem alle Teilnehmer hängen: Solar oben, Batterie unten, Netz links, Haus rechts, Wallbox unten rechts (nur wenn vorhanden). Jeder Knoten ist eine kleine Karte in seiner Farbe mit Icon, Wert und Zustand. Jede Leitung hat genau einen Wert und eine Richtung; wandernde Pfeile in der Farbe des Teilnehmers zeigen die Richtung, ihre Geschwindigkeit die Leistung. Ruhende Leitungen bleiben als graue Spur. Darüber ein Satz, der den Zustand erklärt. „Heute“ als zwei Bilanzbalken (wohin die Sonne ging, woher der Verbrauch kam), dazu Autarkie, Eigenverbrauch, „Batterie voll um“ und Phasenwerte. Entschieden aus vier Varianten, siehe [design/energiefluss-varianten.html](../design/energiefluss-varianten.html). Phase 3.

### 4 · Smart-Funktionen (nur mit RSCP)

| Funktion | RSCP | Phase |
|---|---|---|
| Sperrzeiten (Lade-/Entladesperre, Wochentage, Zeitspanne, ein/aus) | EMS_IDLE_PERIODS (nur eine Version nutzen) | 4 |
| Max. Lade-/Entladeleistung, wetterabhängiges Laden, PowerSave | EMS_REQ_SET_POWER_SETTINGS | 4 |
| Notstromreserve in % / kWh | EP | 4 |
| Manuelles Laden (Wh), 1× pro Tag begrenzt | EMS_REQ_START_MANUAL_CHARGE | später |
| Übernehmen-Button, Rücklesen, Änderungsprotokoll | | 4 |

### 5 · Wallbox-Steuerung (Sheet)

Sonnen-/Mischmodus, 1/3 Phasen/Auto, Ladestrom 6–32 A, Priorität Wallbox/Hauskraftwerk, Batterie-Entladung in die Wallbox bis min. SOC, Laden starten/stoppen, Status. Phase 4.

### 6 · Systemstatistik & Info (Sheet)

Tabs Systeminfo (Seriennummer, Firmware, Module), Batterie-Details (SOH, Zyklen, Temperaturen, Module), Energiefluss seit Inbetriebnahme (Solar je Tracker, Verbrauch, Eigenstrom, Direktverbrauch, Batterie, Einspeisung), Berechnungen (Durchschnitte). Phase 2–3.

### 7 · Einstellungen

Verbindung (Lokal, Bridge, Cloud-Fallback, Assistent), Dashboard-Sortierung, Anlage (kWp, kWh, Ausrichtungen), Tarif und Kosten, Benachrichtigungen, Widgets und Watch, Über. Phase 3–4.

### 8 · Benachrichtigungen (Bridge)

SOC unter x %, Netzbezug über x kW für n Minuten, Anlage offline, Temperatur, Wallbox fertig. Versand per ntfy (Stufe 1) oder APNs (Stufe 2). Phase 4.

### 9 · Widgets, Watch (nur nativ)

Home-Screen „Energiefluss“, „Tagesdiagramm“, Lock-Screen „SOC“, StandBy; Watch-App „Jetzt“ mit 2×2 Kacheln (SOC, PV, Verbrauch, Netz) und Komplikationen. Phase 5.

## MVP-Schnitt

**Muss (Phase 1–3):** Energiemonitor mit Solar/Batterie/Netz/Haus/Monatsstatistik, Diagramme Tag–Jahr, Energiefluss live, Verbindung über Bridge im LAN.

**Soll (Phase 4):** Smart-Funktionen, Wallbox, Benachrichtigungen, Tailscale, Prognose, Kosten.

**Kann (Phase 5):** native App, Widgets, Watch, Börsenpreise, Chord/Heatmap, Export, Cloud-Fallback.

## Was wir bewusst anders machen als my4E

- Verlauf in Sekunden-Auflösung aus eigener Speicherung statt 15-Minuten-Cloud-Daten.
- Benachrichtigungen ohne Fremdserver (Bridge zu Hause).
- Keine Abo-Logik, keine Werbe-Hinweise.
- Setter werden zurückgelesen und protokolliert.

## Zwei Gestaltungsvarianten

| | **Variante A** ([clickdummy.html](../design/clickdummy.html)) | **Variante B** ([clickdummy-b.html](../design/clickdummy-b.html)) |
|---|---|---|
| Vorbild | Struktur wie das neue my4E-Dashboard, eigene Palette und Formen (Fase, Sonnenbogen, Ring, Wasserzeichen) | eigenständig |
| Fläche | Vollfarbige Karten in einer gedeckten, persönlichen Farbwelt (siehe unten) mit halbtransparenten Unterkacheln | Ruhige Papierfläche, Hairlines, Farbe nur in Datenmarken |
| Hero | Solarkarte mit Tracker-Werten + Prognose | Ein großer Wert + Satz, dann der Energiefluss kompakt (Quellen links, Verwendung rechts) |
| Messgrößen | Je Größe eine Karte, Autarkie/Eigenverbrauch nur einmal in „Heute“ | Liste mit 24-h-Sparkline je Zeile |
| Navigation | Schwebende Toolbar unten, Einstellungen über Kopfzeile | Klassische Tab-Leiste mit fünf Einträgen |
| Steuerung | Eigener Bereich mit Slidern, großer Übernehmen-Button | Listen mit Steppern/Schaltern, „Übernehmen“ erscheint in der Kopfzeile bei Änderung |
| Typografie | Sora für Zahlen und Titel, iOS-System für Text | Figtree für Werte, IBM Plex Mono für Meta-Zeilen |
| Stärke | Vertraut, sehr viel Information auf einen Blick | Ruhig, schnell erfassbar, gut für Dark Mode und Widgets |

## Farbwelt „Signal“ (festgelegt)

Kräftige Flächenfarben nach RAL-Signal- und Verkehrsfarben, weiße Schrift auf allen Karten. Die Diagrammserien gehören zu denselben Farbfamilien und sind mit dem Paletten-Validator auf Farbfehlsichtigkeit, Kontrast und Unterscheidbarkeit geprüft (hell und dunkel).

| Rolle | Farbe | Hell | Dunkel |
|---|---|---|---|
| Solar | Signalgelb (RAL 1003, leicht vertieft) | `#e69500` → `#f5ab00` | `#d99400` → `#e5a600` |
| Batterie | Signalgrün (RAL 6032) | `#237f52` | `#1c6642` |
| Haus | Verkehrsrot (RAL 3020) | `#c1121c` | `#9e0f17` |
| Netz | Signalblau (RAL 5005) | `#1f4e8c` | `#1a4075` |
| Wallbox | Signalviolett (RAL 4008) | `#924e7d` | `#773f66` |
| Information | Anthrazitgrau (RAL 7016) | `#383e42` | `#2b3034` |

| Diagrammserie | Hell | Dunkel |
|---|---|---|
| Solar | `#9e7a23` | `#98741a` |
| Netzbezug | `#36a3c8` | `#299abe` |
| Batterie entladen | `#8d6cc2` | `#8766bb` |
| Verbrauch | `#c15c67` | `#ba5661` |
| Einspeisung | `#547ecd` | `#4e78c7` |
| Batterie laden | `#539344` | `#4d8c3e` |

Die Alternativen „Alpen“ und „Bauhaus“ wurden verworfen.

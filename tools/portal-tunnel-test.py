#!/usr/bin/env python3
"""Testet die RSCP-Verbindung über das E3/DC-Portal (Websocket-Relay wss://s10.e3dc.com/ws).

Aufruf:
  E3DC_USER='portal@mail' E3DC_PASS='portal-passwort' E3DC_SN='S10-1234567890' .venv/bin/python tools/portal-tunnel-test.py

Es werden nur Lesebefehle geschickt (Live-Werte, Systeminfo, Batterie, Wallbox-Status, ein DB-Tageswert).
Zugangsdaten werden nicht gespeichert. Das Portal-Passwort wird von der Bibliothek als MD5 übertragen.
"""
import os, sys, time, json, traceback
from datetime import datetime

try:
    from e3dc import E3DC
    import e3dc._e3dc_rscp_web as _web
except ImportError:
    sys.exit("pye3dc fehlt: .venv/bin/pip install 'git+https://github.com/fsantini/python-e3dc.git'")

# Das Portal-Relay verlangt seit Juni 2026 das Spiegeln von RSCP_REQ_SET_PROTOCOL_VERSION.
# Die PyPI-Version 0.10.0 kann das nicht und läuft in einen Timeout. Nur der GitHub-Stand funktioniert.
import inspect as _inspect
if "SET_PROTOCOL_VERSION" not in _inspect.getsource(_web):
    sys.exit("Installierte pye3dc-Version ist zu alt für das Portal-Relay (fehlender Protokoll-Fix).\n"
             "Bitte ausführen:  .venv/bin/pip install --force-reinstall 'git+https://github.com/fsantini/python-e3dc.git'")

import logging
logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(name)s: %(message)s")
logging.getLogger("e3dc._e3dc_rscp_web").setLevel(logging.DEBUG)   # Handshake-Schritte
logging.getLogger("e3dc._rscpLib").setLevel(logging.WARNING)       # NICHT auf DEBUG: gibt Passwörter im Klartext aus

user, pw, sn = os.environ.get("E3DC_USER"), os.environ.get("E3DC_PASS"), os.environ.get("E3DC_SN")
if not (user and pw and sn):
    sys.exit("Bitte E3DC_USER, E3DC_PASS und E3DC_SN als Umgebungsvariablen setzen.")
if not sn.upper().startswith("S10-"):
    sn = "S10-" + sn

def step(name, fn):
    t = time.time()
    try:
        res = fn()
        print(f"[OK ] {name} ({time.time()-t:.2f}s)")
        print("      " + json.dumps(res, default=str, ensure_ascii=False)[:600])
        return res
    except Exception as e:
        print(f"[ERR] {name}: {type(e).__name__}: {e}")
        return None

print(f"Verbinde über Portal-Tunnel als {user}, Anlage {sn} ...")
t0 = time.time()
try:
    # Achtung, Bibliotheksfehler: isPasswordMd5=False würde das Passwort im Klartext senden (Relay lehnt ab, Status 16).
    # Ohne den Parameter wird das Klartext-Passwort korrekt als MD5 übertragen.
    e3 = E3DC(E3DC.CONNECT_WEB, username=user, password=pw, serialNumber=sn)
except Exception:
    traceback.print_exc()
    sys.exit("Verbindung fehlgeschlagen. Siehe Debug-Zeilen oben: 'Authentication failed' = Passwort/Seriennummer, 'Connection timed out' ohne 'Initial connection registered' = Relay-Protokoll geändert.")
print(f"Verbunden nach {time.time()-t0:.2f}s")

step("Systeminfo (INFO_*)", lambda: e3.get_system_info(keepAlive=True))
for i in range(3):
    step(f"Live-Werte #{i+1} (EMS_REQ_POWER_*)", lambda: e3.poll(keepAlive=True))
    time.sleep(2)
step("Batterie (BAT_*)", lambda: e3.get_battery_data(keepAlive=True))
step("PV-Wechselrichter (PVI_*)", lambda: e3.get_pvi_data(keepAlive=True))
step("Leistungseinstellungen (EMS_REQ_GET_POWER_SETTINGS)", lambda: e3.get_power_settings(keepAlive=True))
step("Wallbox (WB_*)", lambda: e3.get_wallbox_data(keepAlive=True))
step("DB Tageswerte gestern", lambda: e3.get_db_data(startDate=datetime.now().date(), timespan="DAY", keepAlive=True))
try:
    e3.disconnect()
except Exception:
    pass
print("Fertig. Bitte die Ausgabe (ohne Zugangsdaten) weitergeben.")

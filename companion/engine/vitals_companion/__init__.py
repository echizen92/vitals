"""Vitals Mac companion capture engine.

Reads what an iPhone cannot report about itself (battery temperature, per-process CPU, syslog, crash
reports, sysdiagnose) over USB or Wi-Fi using pymobiledevice3, and writes a capture bundle whose JSON uses
the same report schema as the Vitals iOS app (Docs/report-schema.md), so the phone can import it.

GPL-3.0-or-later, because pymobiledevice3 is GPL-3.0.
"""

__version__ = "0.1.0"
GENERATOR = "vitals-companion " + __version__

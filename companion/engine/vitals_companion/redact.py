"""Redaction of device identifiers (plan section 4b): UDID and serial number never leave the Mac in a
capture, a report, a note or a printed command. Raw files kept beside the capture are redacted too."""

import re

ID_KEYS = {"UniqueDeviceID", "UDID", "udid", "SerialNumber", "Serial", "serialNumber", "ecid", "ECID",
           "UniqueChipID", "WiFiAddress", "BluetoothAddress", "EthernetAddress", "MLBSerialNumber",
           "InternationalMobileEquipmentIdentity", "InternationalMobileEquipmentIdentity2", "MobileEquipmentIdentifier",
           "IntegratedCircuitCardIdentity", "PhoneNumber", "identifier", "Identifier", "deviceIdentifier",
           "serialNumber", "ecid"}

# 40-hex legacy UDID; 8-hex dash 16-hex modern UDID; MAC addresses.
PATTERNS = [
    re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{16}\b"),
    re.compile(r"\b[0-9a-fA-F]{40}\b"),
    re.compile(r"\b(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b"),
]


def redact_text(s, extra=()):
    for v in extra:
        if v and len(str(v)) >= 6:
            # Whole tokens only, so a value never eats part of an ordinary word.
            s = re.sub(r"(?<![0-9A-Za-z])" + re.escape(str(v)) + r"(?![0-9A-Za-z])", "[redacted]", s)
    for p in PATTERNS:
        s = p.sub("[redacted]", s)
    return s


def collect_ids(obj, found=None):
    """Values of identifier keys anywhere in obj, so they can be scrubbed from free text too."""
    found = set() if found is None else found
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in ID_KEYS and isinstance(v, (str, int)):
                found.add(str(v))
            else:
                collect_ids(v, found)
    elif isinstance(obj, list):
        for v in obj:
            collect_ids(v, found)
    return found


def redact(obj, extra=()):
    if isinstance(obj, dict):
        return {k: ("[redacted]" if k in ID_KEYS else redact(v, extra)) for k, v in obj.items()}
    if isinstance(obj, list):
        return [redact(v, extra) for v in obj]
    if isinstance(obj, str):
        return redact_text(obj, extra)
    return obj

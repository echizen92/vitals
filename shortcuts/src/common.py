"""Shared bits for the Vitals Relief shortcuts. Compiled with unqforge (MIT), pinned in ../build.sh.

Action identifiers and parameter names come from unqforge's catalogue as read on 2026-11-15 and are
UNVERIFIED on iOS 27.2 until the signed files are run on the Duo (Docs/needs-device.md). Every shortcut
ends by opening Vitals' x-success URL only when Vitals launched it (the URL scheme handles that), so the
app can measure before and after.
"""
from unqforge import *  # noqa: F401,F403  (SC and helpers)

LOW_POWER = "is.workflow.actions.lowpowermode.set"
BRIGHTNESS = "is.workflow.actions.setbrightness"
ALWAYS_ON = "is.workflow.actions.display.always-on.set"
REBOOT = "is.workflow.actions.reboot"
ASK_MENU = "is.workflow.actions.choosefrommenu"
ALERT = "is.workflow.actions.alert"


def new():
    return SC()  # noqa: F405

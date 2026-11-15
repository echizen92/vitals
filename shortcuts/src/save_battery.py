"""Vitals Save battery: Low Power Mode on and screen to 40 %.
Run with the text "undo" as input (Vitals' Undo button): Low Power Mode off."""
import sys
from common import new_with_undo, LOW_POWER, BRIGHTNESS, SHORTCUT_INPUT, UNDO

s = new_with_undo()
with s.if_(SHORTCUT_INPUT, "==", UNDO) as branch:
    s.action(LOW_POWER, OnValue=False)
    branch.otherwise()
    s.action(LOW_POWER, OnValue=True)
    s.action(BRIGHTNESS, WFBrightness=0.4)
s.dump(sys.argv[1])

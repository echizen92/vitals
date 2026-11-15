"""Vitals Cool down: Low Power Mode on, screen to 30 %, Always On display off.
Effect: less work for the processor and the display, the two biggest heat sources you control.
Run with the text "undo" as input (Vitals' Undo button): Low Power Mode off, Always On on. Brightness is not
restored to an exact earlier value; auto-brightness, or the person, sets it."""
import sys
from common import new_with_undo, LOW_POWER, BRIGHTNESS, ALWAYS_ON, SHORTCUT_INPUT, UNDO

s = new_with_undo()
with s.if_(SHORTCUT_INPUT, "==", UNDO) as branch:
    s.action(LOW_POWER, OnValue=False)
    s.action(ALWAYS_ON, OnValue=1)
    branch.otherwise()
    s.action(LOW_POWER, OnValue=True)
    s.action(BRIGHTNESS, WFBrightness=0.3)
    s.action(ALWAYS_ON, OnValue=0)
s.dump(sys.argv[1])

"""Vitals Cool down: Low Power Mode on, screen to 30 %, Always On display off.
Effect: less work for the processor and the display, the two biggest heat sources you control.
Undo: Vitals Undo Cool down."""
import sys
from common import new, LOW_POWER, BRIGHTNESS, ALWAYS_ON

s = new()
s.action(LOW_POWER, OnValue=True)
s.action(BRIGHTNESS, WFBrightness=0.3)
s.action(ALWAYS_ON, OnValue=0)
s.dump(sys.argv[1])

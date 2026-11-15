"""Vitals Save battery: Low Power Mode on and screen to 40 %. Undo: Vitals Undo Save battery."""
import sys
from common import new, LOW_POWER, BRIGHTNESS

s = new()
s.action(LOW_POWER, OnValue=True)
s.action(BRIGHTNESS, WFBrightness=0.4)
s.dump(sys.argv[1])

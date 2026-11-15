"""Vitals Undo Save battery: Low Power Mode off."""
import sys
from common import new, LOW_POWER

s = new()
s.action(LOW_POWER, OnValue=False)
s.dump(sys.argv[1])

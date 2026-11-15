"""Vitals Undo Cool down: Low Power Mode off, Always On display on.
Brightness is not restored to an exact earlier value (Shortcuts cannot read it back reliably across runs);
auto-brightness, or the person, sets it."""
import sys
from common import new, LOW_POWER, ALWAYS_ON

s = new()
s.action(LOW_POWER, OnValue=False)
s.action(ALWAYS_ON, OnValue=1)
s.dump(sys.argv[1])

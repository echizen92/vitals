"""Vitals Restart: asks first, then restarts. Apps cannot restart an iPhone; Shortcuts can.
The restart is what stopped the stuck iCloud sync on the Duo (2026-11-15). No undo (nothing to undo)."""
import sys
from common import new, REBOOT

s = new()
# The system shows its own confirmation for Restart; Vitals' detail screen explains it beforehand.
s.action(REBOOT, WFShutdownMode="Restart")
s.dump(sys.argv[1])

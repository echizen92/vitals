# Fixtures

All files here are **synthetic**, written by hand to match Apple's documented formats (crash JSON, jetsam)
and community descriptions of undocumented ones (cpu_resource, wakeups, hang, panic, analytics keys).
Times are around 2027-01-15 08:00 UTC (`t0` in the tests). Replace or supplement with redacted real files
from the iPhone Duo once available (Docs/needs-device.md).

`sysdiagnose_2027.01.15_synthetic.tar.gz` was built with macOS `tar czf` from a temporary tree holding three of the
.ips files above, the analytics file, 300 KB of random bytes standing in for a power log, and one entry with a path
longer than 100 characters (exercises extended tar headers). A real sysdiagnose is several hundred MB.

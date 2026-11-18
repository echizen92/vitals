"""Make the bundled Python's command scripts relocatable.

pip writes the absolute path of the interpreter it ran with into each script in bin/ (a one-line #! line, or the
two-line sh launcher when the path has spaces). Rewrite both forms to the sh launcher that runs the python3 next
to the script, so the app works wherever it is copied. Usage: python3 relocate_scripts.py BIN_DIR
"""
import os
import sys

LAUNCHER = b"#!/bin/sh\n'''exec' \"$(dirname \"$0\")/python3\" \"$0\" \"$@\"\n' '''\n"


def main(bin_dir):
    changed = 0
    for name in sorted(os.listdir(bin_dir)):
        path = os.path.join(bin_dir, name)
        if os.path.islink(path) or not os.path.isfile(path):
            continue
        data = open(path, "rb").read()
        if not data.startswith(b"#!"):
            continue
        lines = data.split(b"\n")
        if lines[0].startswith(b"#!/bin/sh") and len(lines) > 2 and lines[1].startswith(b"'''exec'"):
            body = b"\n".join(lines[3:])           # pip's sh launcher: three lines, then the Python code
        elif b"python" in lines[0]:
            body = b"\n".join(lines[1:])           # a plain #!/abs/path/python3 line
        else:
            continue
        with open(path, "wb") as f:
            f.write(LAUNCHER + body)
        changed += 1
    print("relocated %d scripts" % changed)


if __name__ == "__main__":
    main(sys.argv[1])

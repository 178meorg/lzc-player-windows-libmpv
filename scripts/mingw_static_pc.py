"""Repair explicit shared GCC dependencies in a static MinGW build prefix."""

from pathlib import Path
import re
import sys


LIBRARY_FIELD = re.compile(r"(?m)^(Libs(?:\.private)?:[^\r\n]*)")
SHARED_GCC = re.compile(r"(?<!\S)(?:-lgcc_s|-l:libgcc_s\.a)(?!\S)")


def normalize_metadata(text):
    return LIBRARY_FIELD.sub(
        lambda match: SHARED_GCC.sub("-lgcc -lgcc_eh", match.group()), text
    )


def normalize_prefix(prefix):
    changed = []
    for directory in (prefix / "lib/pkgconfig", prefix / "share/pkgconfig"):
        for path in sorted(directory.glob("*.pc")):
            original = path.read_bytes()
            updated = normalize_metadata(original.decode("utf-8")).encode("utf-8")
            if updated != original:
                path.write_bytes(updated)
                changed.append(path)
    return changed


if __name__ == "__main__":
    for path in normalize_prefix(Path(sys.argv[1])):
        print(f"Static GCC pkg-config metadata: {path}")

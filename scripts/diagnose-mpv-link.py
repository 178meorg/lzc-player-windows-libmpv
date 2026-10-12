"""Explain external GCC runtime imports using the actual Meson link inputs."""

import json
from pathlib import Path
import re
import subprocess
import sys


def output(*args):
    return subprocess.check_output(args, text=True, errors="replace")


build_dir = Path(sys.argv[1])
targets = json.loads(output("meson", "introspect", "--targets", str(build_dir)))
target = next(target for target in targets if any(
    Path(name).name.lower() == "libmpv-2.dll" for name in target["filename"]
))
parameters = [arg for group in target["target_sources"] if "linker" in group
              for arg in group["parameters"]]
print("=== libmpv link inputs ===", flush=True)
print("\n".join(parameters), flush=True)

print("=== GCC search paths ===", flush=True)
print(output("cc", "-print-search-dirs"), flush=True)
for library in ("libgcc.a", "libgcc_eh.a", "libgcc_s.a", "libstdc++.a"):
    print(f"{library}: {output('cc', '-print-file-name=' + library).strip()}",
          flush=True)

print("=== Static pkg-config dependencies ===", flush=True)
for library in ("libavcodec", "libavfilter", "libplacebo", "dovi", "rubberband"):
    result = subprocess.run(["pkg-config", "--static", "--libs", library],
                            text=True, capture_output=True)
    print(f"{library}: {result.stdout.strip()} {result.stderr.strip()}", flush=True)

dll = Path(target["filename"][0])
if dll.is_file():
    print("=== GCC runtime import table ===", flush=True)
    imports = output("objdump", "-p", str(dll))
    for section in re.split(r"(?=\s+DLL Name:)", imports):
        if re.match(r"\s+DLL Name: libgcc", section, re.I):
            print(section.split("\n\n", 1)[0], flush=True)

print("=== GCC runtime symbols in input archives ===", flush=True)
pattern = re.compile(r"(?:__imp_)?(?:_Unwind_|__gxx_personality|__gcc_personality|"
                     r"__register_frame|__deregister_frame|__[a-z]*ti[234])")
archives = set()
for arg in parameters:
    if not arg.endswith(".a"):
        continue
    path = Path(arg)
    if not path.is_absolute():
        path = build_dir / path
    if path.is_file():
        archives.add(str(path))
archives = sorted(archives)
for archive in archives:
    result = subprocess.run(["nm", "-A", "-g", "--no-sort", archive],
                            text=True, capture_output=True, errors="replace")
    for line in result.stdout.splitlines():
        if pattern.search(line):
            print(line, flush=True)
    if result.returncode:
        print(result.stderr, flush=True)

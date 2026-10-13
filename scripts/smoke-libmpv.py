"""Windows package smoke test, using only Python's standard library.

Run with native 64-bit Python:
    python scripts/smoke-libmpv.py path/to/libmpv-2.dll

Uses deterministic YUV420 video and PCM audio, with null outputs and software
decoding. This checks the playback pipeline, not GPU rendering or codec coverage.
The worker runs in a subprocess so DLL crashes and hangs fail the test.
"""

import argparse
import ctypes as C
import locale
import math
import os
from pathlib import Path
import struct
import subprocess
import sys
import time
import wave


class Event(C.Structure):
    _fields_ = [("event_id", C.c_int), ("error", C.c_int),
                ("reply_userdata", C.c_uint64), ("data", C.c_void_p)]


class EndFile(C.Structure):
    # Only the initial fields of mpv_event_end_file are needed.
    _fields_ = [("reason", C.c_int), ("error", C.c_int)]


def create_samples(directory):
    video = directory / "video.y4m"
    with video.open("wb") as stream:
        stream.write(b"YUV4MPEG2 W64 H48 F25:1 Ip A1:1 C420jpeg\n")
        for frame in range(25):
            stream.write(b"FRAME\n")
            stream.write(bytes([16 + frame * 8]) * (64 * 48))
            stream.write(bytes([128]) * (64 * 48 // 2))
    audio = directory / "audio.wav"
    with wave.open(str(audio), "wb") as stream:
        stream.setparams((1, 2, 48000, 0, "NONE", "not compressed"))
        stream.writeframes(b"".join(
            struct.pack("<h", int(8000 * math.sin(2 * math.pi * 440 * n / 48000)))
            for n in range(48000)
        ))
    return video, audio


def run_worker(dll, directory):
    locale.setlocale(locale.LC_NUMERIC, "C")
    if C.sizeof(C.c_void_p) != 8:
        raise RuntimeError("Requires 64-bit Python")
    # CDLL's default Windows loader flags search the DLL directory and system
    # directories, rather than relying on the build environment's PATH.
    with os.add_dll_directory(str(dll.parent)):
        lib = C.CDLL(str(dll))

        def bind(name, restype, *argtypes):
            fn = getattr(lib, name)
            fn.restype, fn.argtypes = restype, list(argtypes)
            return fn

        version = bind("mpv_client_api_version", C.c_ulong)
        create = bind("mpv_create", C.c_void_p)
        initialize = bind("mpv_initialize", C.c_int, C.c_void_p)
        option = bind("mpv_set_option_string", C.c_int,
                      C.c_void_p, C.c_char_p, C.c_char_p)
        command = bind("mpv_command", C.c_int,
                       C.c_void_p, C.POINTER(C.c_char_p))
        wait = bind("mpv_wait_event", C.POINTER(Event), C.c_void_p, C.c_double)
        get = bind("mpv_get_property", C.c_int,
                   C.c_void_p, C.c_char_p, C.c_int, C.c_void_p)
        error = bind("mpv_error_string", C.c_char_p, C.c_int)
        destroy = bind("mpv_terminate_destroy", None, C.c_void_p)

        def check(result, operation):
            if result < 0:
                raise RuntimeError(f"{operation}: {error(result).decode()}")

        api = version()
        print(f"PASS: loaded {dll}; API {api >> 16}.{api & 0xffff}", flush=True)
        for sample in create_samples(directory):
            handle = create()
            if not handle:
                raise RuntimeError("mpv_create failed")
            try:
                for name, value in {
                    "config": "no", "load-scripts": "no", "ytdl": "no",
                    "vo": "null", "ao": "null", "hwdec": "no",
                    "video-sync": "audio", "idle": "yes",
                    "log-file": str(directory / f"{sample.stem}-mpv.log"),
                    "msg-level": "all=v",
                }.items():
                    check(option(handle, name.encode(), value.encode("utf-8")), name)
                check(initialize(handle), "mpv_initialize")
                args = (C.c_char_p * 3)(b"loadfile", str(sample).encode("utf-8"), None)
                check(command(handle, args), "loadfile")
                loaded, progressed = False, False
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline:
                    event = wait(handle, 0.05).contents
                    if event.event_id == 8:  # MPV_EVENT_FILE_LOADED
                        loaded = True
                    elif event.event_id == 7:  # MPV_EVENT_END_FILE
                        end = C.cast(event.data, C.POINTER(EndFile)).contents
                        check(end.error, "playback")
                        if end.reason != 0:  # MPV_END_FILE_REASON_EOF
                            raise RuntimeError(f"Unexpected end-file reason: {end.reason}")
                        if not loaded or not progressed:
                            raise RuntimeError("Reached EOF without loading and playback progress")
                        print(f"PASS: {sample.name} loaded, played, reached EOF", flush=True)
                        break
                    elif event.event_id in (1, 24):  # shutdown / queue overflow
                        raise RuntimeError(f"Unexpected mpv event: {event.event_id}")
                    position = C.c_double()
                    if get(handle, b"time-pos", 5, C.byref(position)) >= 0:
                        progressed |= position.value >= 0.2
                else:
                    raise TimeoutError(f"Playback timed out: {sample.name}")
            finally:
                destroy(handle)
        print("PASS: libmpv smoke test completed and handles destroyed", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dll", type=Path)
    parser.add_argument("--output-dir", type=Path, default=Path("smoke-results"))
    parser.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if sys.platform != "win32":
        parser.error("This test must run on Windows")
    dll, directory = args.dll.resolve(), args.output_dir.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    if args.worker:
        run_worker(dll, directory)
        return 0
    with (directory / "smoke-test.log").open("w", encoding="utf-8") as log:
        try:
            result = subprocess.run(
                [sys.executable, "-u", str(Path(__file__).resolve()), str(dll),
                 "--output-dir", str(directory), "--worker"],
                stdout=log, stderr=subprocess.STDOUT, timeout=60,
            )
            code = result.returncode
        except subprocess.TimeoutExpired:
            log.write("FAIL: worker exceeded 60 seconds (including initialization/cleanup)\n")
            code = 1
    print((directory / "smoke-test.log").read_text(encoding="utf-8"), end="")
    if code:
        print(f"FAIL: libmpv worker exit code {code}", file=sys.stderr)
    return 1 if code else 0


if __name__ == "__main__":
    sys.exit(main())

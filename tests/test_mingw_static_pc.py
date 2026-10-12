from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import unittest

from scripts.mingw_static_pc import normalize_metadata, normalize_prefix


class MetadataTests(unittest.TestCase):
    def test_only_rewrites_complete_library_flags(self):
        original = (
            "Description: uses -lgcc_s\n"
            "Libs: -lx265 -lgcc_s -lgcc\n"
            "Libs.private: -lstdc++ -l:libgcc_s.a -lgcc_s_other\n"
            "Cflags: -DNAME=-lgcc_s\n"
        )
        self.assertEqual(normalize_metadata(original), (
            "Description: uses -lgcc_s\n"
            "Libs: -lx265 -lgcc -lgcc_eh -lgcc\n"
            "Libs.private: -lstdc++ -lgcc -lgcc_eh -lgcc_s_other\n"
            "Cflags: -DNAME=-lgcc_s\n"
        ))

    def test_preserves_crlf_and_is_idempotent(self):
        original = "Libs: -lx265\r\nLibs.private: -lgcc_s\r\n"
        fixed = normalize_metadata(original)
        self.assertEqual(fixed, "Libs: -lx265\r\nLibs.private: -lgcc -lgcc_eh\r\n")
        self.assertEqual(normalize_metadata(fixed), fixed)

    def test_repairs_both_metadata_directories_without_touching_archives(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = Path(directory)
            paths = [prefix / "lib/pkgconfig/x265.pc",
                     prefix / "share/pkgconfig/libavcodec.pc"]
            for path in paths:
                path.parent.mkdir(parents=True)
                path.write_bytes(b"Libs.private: -lgcc_s\r\n")
            archive = prefix / "lib/libx265.a"
            archive.write_bytes(b"archive must remain unchanged")
            self.assertEqual(normalize_prefix(prefix), paths)
            self.assertEqual(normalize_prefix(prefix), [])
            self.assertEqual(archive.read_bytes(), b"archive must remain unchanged")


@unittest.skipUnless(all(shutil.which(tool) for tool in (
    "meson", "ninja", "pkg-config", "x86_64-w64-mingw32-gcc",
    "x86_64-w64-mingw32-g++", "x86_64-w64-mingw32-ar",
    "x86_64-w64-mingw32-objdump",
)), "requires a MinGW cross toolchain and Meson")
class LinkRegressionTests(unittest.TestCase):
    def test_explicit_shared_gcc_overrides_static_flags_until_metadata_is_repaired(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pc_dir = root / "lib/pkgconfig"
            pc_dir.mkdir(parents=True)
            (pc_dir / "x265.pc").write_text(
                "Name: x265\nDescription: shared GCC regression fixture\n"
                f"Version: 4.1\nLibs: -L{root.as_posix()} -lexception\n"
                "Libs.private: -lstdc++ -lgcc_s -lgcc\n"
            )
            # FFmpeg records x265's flags directly in its own .pc files.
            (pc_dir / "libavcodec.pc").write_text(
                "Name: libavcodec\nDescription: cached FFmpeg metadata fixture\n"
                f"Version: 63.1.101\nLibs: -L{root.as_posix()} -lexception\n"
                "Libs.private: -lstdc++ -lgcc_s -lgcc\n"
            )
            (root / "meson.build").write_text(
                "project('gcc-runtime-regression', 'c')\n"
                "shared_library('probe', 'probe.c', name_prefix: '', "
                "dependencies: dependency('libavcodec', static: true))\n"
            )
            (root / "probe.c").write_text(
                "extern int throw_and_catch(int);\n"
                "__declspec(dllexport) unsigned __int128 divide("
                "unsigned __int128 a, unsigned __int128 b) "
                "{ return a / b + throw_and_catch(0); }\n"
            )
            (root / "exception.cpp").write_text(
                '#include <stdexcept>\n'
                'extern "C" int throw_and_catch(int value) {\n'
                'try { throw std::runtime_error("probe"); }\n'
                'catch (const std::runtime_error&) { return value; } }\n'
            )
            cross_file = root / "cross.ini"
            cross_file.write_text(
                "[binaries]\n"
                "c = 'x86_64-w64-mingw32-gcc'\n"
                "pkg-config = 'pkg-config'\n"
                "[host_machine]\n"
                "system = 'windows'\ncpu_family = 'x86_64'\n"
                "cpu = 'x86_64'\nendian = 'little'\n"
            )
            env = dict(os.environ, PKG_CONFIG_LIBDIR=str(pc_dir), PKG_CONFIG_PATH="")

            def run(*command):
                return subprocess.check_output(command, cwd=root, env=env,
                                               text=True, stderr=subprocess.STDOUT)

            def build(name):
                build_dir = root / name
                run("meson", "setup", str(build_dir), "--cross-file", str(cross_file),
                    "-Dc_link_args=-static -static-libgcc -static-libstdc++",
                    "-Db_lto=true")
                run("meson", "compile", "-C", str(build_dir))
                targets = json.loads(run("meson", "introspect", "--targets", str(build_dir)))
                target = next(target for target in targets if target["name"] == "probe")
                parameters = [arg for group in target["target_sources"] if "linker" in group
                              for arg in group["parameters"]]
                imports = run("x86_64-w64-mingw32-objdump", "-p", target["filename"][0])
                return parameters, imports

            run("x86_64-w64-mingw32-g++", "-c", "exception.cpp", "-o", "exception.o")
            run("x86_64-w64-mingw32-ar", "rcs", "libexception.a", "exception.o")
            before_args, before_imports = build("before")
            self.assertTrue(any("libgcc_s.a" in arg or arg == "-lgcc_s"
                                for arg in before_args))
            self.assertIn("DLL Name: libgcc_s_seh-1.dll", before_imports)
            self.assertEqual(len(normalize_prefix(root)), 2)
            after_args, after_imports = build("after")
            self.assertFalse(any("libgcc_s.a" in arg or arg == "-lgcc_s"
                                 for arg in after_args))
            self.assertNotIn("DLL Name: libgcc_s_seh-1.dll", after_imports)


if __name__ == "__main__":
    unittest.main()

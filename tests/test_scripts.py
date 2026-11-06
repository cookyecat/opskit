"""Portable smoke tests for UtiScripts (safe: no actual firewall changes)."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def shell_script(name, *args, env=None):
    return subprocess.run(
        ["bash", str(ROOT / name), *map(str, args)],
        capture_output=True, text=True, timeout=12, env=env,
    )


class ShellSyntaxTests(unittest.TestCase):
    def test_shell_syntax(self):
        for name in (
            "watchit.sh", "ipeye.sh", "opencv.sh",
            "setup_one_arm_nat_and_portmap.sh"
        ):
            with self.subTest(name=name):
                result = subprocess.run(
                    ["bash", "-n", str(ROOT / name)],
                    capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)


class IPChangeTests(unittest.TestCase):
    def test_initial_unchanged_changed_and_invalid(self):
        with tempfile.TemporaryDirectory() as folder:
            state = Path(folder) / "state"
            cmd = ("--state-file", str(state), "--ip")
            self.assertIn(
                "Initialized:", shell_script("ipeye.sh", *cmd, "192.0.2.1").stdout
            )
            self.assertIn(
                "Unchanged:", shell_script("ipeye.sh", *cmd, "192.0.2.1").stdout
            )
            self.assertIn(
                "Changed:", shell_script("ipeye.sh", *cmd, "192.0.2.2").stdout
            )
            self.assertEqual(state.read_text().strip(), "192.0.2.2")
            failed = shell_script("ipeye.sh", *cmd, "999.0.0.1")
            self.assertNotEqual(failed.returncode, 0)
            self.assertEqual(state.read_text().strip(), "192.0.2.2")


class ProcessWatchTests(unittest.TestCase):
    def test_wait_and_forward_command_args(self):
        process = subprocess.Popen(["sleep", "1"])
        try:
            result = shell_script(
                "watchit.sh", "--interval", "1", str(process.pid),
                "echo", "spaced argument"
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("spaced argument", result.stdout)
        finally:
            process.wait(timeout=5)

    def test_nonexistent_pid_is_not_executed(self):
        result = shell_script("watchit.sh", "99999999", "echo", "NOT_SAFE")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("NOT_SAFE", result.stdout)


class OpenCVTests(unittest.TestCase):
    def test_compiler_flags_and_filenames_with_spaces(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            bindir = base / "bin"
            bindir.mkdir()
            pkg = bindir / "pkg-config"
            pkg.write_text(
                '#!/bin/sh\n'
                'case "$1" in\n'
                '  --exists) [ "$2" = opencv4 ];;\n'
                '  --cflags) echo -I/mock/include;;\n'
                '  --libs) echo -lopencv_core;;\n'
                'esac\n'
            )
            compiler = bindir / "fake-compiler"
            compiler.write_text(
                '#!/bin/sh\nprintf "<%s>\\n" "$@" > "$COMPILER_LOG"\n'
            )
            pkg.chmod(0o755)
            compiler.chmod(0o755)
            source = base / "input with spaces.cpp"
            source.write_text("int main() { return 0; }\n")
            target = base / "output with spaces"
            logfile = base / "args.txt"
            env = dict(
                os.environ,
                PATH=str(bindir) + os.pathsep + os.environ.get("PATH", ""),
                CXX=str(compiler),
                COMPILER_LOG=str(logfile),
            )
            result = shell_script(
                "opencv.sh", str(source), str(target), env=env
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            flags = logfile.read_text()
            self.assertIn("-std=c++17", flags)
            self.assertIn(str(source), flags)
            self.assertIn(str(target), flags)
            self.assertIn("-lopencv_core", flags)


class NetworkSafetyTests(unittest.TestCase):
    def test_firewall_dry_run_only_prints_configuration(self):
        result = shell_script(
            "setup_one_arm_nat_and_portmap.sh", "--dry-run"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("no firewall", result.stdout.lower())
        self.assertIn("SSH DNAT mappings: disabled", result.stdout)


class TunnelStatusTests(unittest.TestCase):
    def test_aligned_columns(self):
        spec = importlib.util.spec_from_file_location(
            "tunnel_status", ROOT / "tunnels-status.py"
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        rows = [
            {"PID": "12", "Health": "1234", "Tunnel ID": "tunnel_abc",
             "MCP target": "http://localhost:1000/mcp", "Ready": "yes",
             "Control plane": "polling"},
            {"PID": "12345", "Health": "99", "Tunnel ID": "tunnel_xxyyzz",
             "MCP target": "http://localhost:10000/sub/mcp", "Ready": "no",
             "Control plane": "disconnected"},
        ]
        fields = ("PID", "Health", "Tunnel ID", "MCP target",
                  "Ready", "Control plane")
        lines = list(module.table_lines(rows, fields))
        self.assertEqual(len(lines), 4)
        self.assertEqual(len(lines[1]), len(lines[0]))
        self.assertEqual(len(lines[2]), len(lines[0]))
        self.assertEqual(len(lines[3]), len(lines[0]))


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Inspect local tunnel-client processes, Tunnel IDs, MCP targets and health.

macOS (ps + lsof); Python 3 standard library. Profiles containing YAML (rather
than JSON) additionally require PyYAML. Read-only; no API keys are displayed.
"""

import argparse
import json
import re
import shlex
import shutil
import subprocess
import urllib.request
from pathlib import Path


def run(*args):
    try:
        return subprocess.check_output(
            args, text=True, stderr=subprocess.DEVNULL
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def option(args, name):
    for i, arg in enumerate(args):
        if arg == "--" + name and i + 1 < len(args):
            return args[i + 1]
        if arg.startswith("--" + name + "="):
            return arg.split("=", 1)[1]
    return None


def load_profile(args):
    name = option(args, "profile")
    if not name:
        return {}
    base = Path(option(args, "profile-dir") or
                (Path.home() / ".config/tunnel-client")).expanduser()
    for extension in (".yaml", ".yml", ".json"):
        path = base / (name + extension)
        try:
            source = path.read_text(encoding="utf-8")
        except OSError:
            continue
        try:
            value = json.loads(source)
        except ValueError:
            try:
                import yaml  # optional; only needed for actual YAML profiles
                value = yaml.safe_load(source)
            except Exception:
                continue
        return value if isinstance(value, dict) else {}
    return {}


def mcp_target(args, profile):
    direct = option(args, "mcp.server-url") or option(args, "mcp-server-url")
    if direct:
        return direct
    mcp = profile.get("mcp") or {}
    urls = mcp.get("server_urls") or []
    if isinstance(urls, list):
        for item in urls:
            if isinstance(item, dict) and item.get("channel", "main") == "main":
                return str(item.get("url") or "?")
    return str(mcp.get("server_url") or option(args, "mcp.command") or "?")


def health_port(pid, args, profile):
    output = run("lsof", "-nP", "-a", "-p", str(pid),
                 "-iTCP", "-sTCP:LISTEN")
    ports = re.findall(
        r"(?:127[.]0[.]0[.]1|\[::1\]|\*):([0-9]+)\s+\(LISTEN\)",
        output,
    )
    preferred = option(args, "health.listen-addr")
    if not preferred:
        preferred = (profile.get("health") or {}).get("listen_addr")
    if preferred:
        match = re.search(r":([0-9]+)$", str(preferred))
        if match and match.group(1) in ports:
            return match.group(1)
    return ports[0] if ports else "?"


def health_status(port):
    if port == "?":
        return "?", "?"
    # Bypass HTTP_PROXY; query only the loopback health endpoint.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(
            "http://127.0.0.1:{}/health?details=true".format(port),
            timeout=2,
        ) as response:
            info = json.load(response)
        ready = info.get("ready")
        state = (info.get("components") or {}).get(
            "control-plane", {}
        ).get("state") or "?"
        return ("yes" if ready is True else "no" if ready is False else "?",
                str(state))
    except (OSError, ValueError, TypeError, KeyError):
        return "?", "?"


def discover():
    rows = []
    for line in run("ps", "-axo", "pid=,comm=").splitlines():
        match = re.match(r"\s*([0-9]+)\s+(.+)", line)
        if not match or Path(match.group(2).strip()).name != "tunnel-client":
            continue
        pid = int(match.group(1))
        raw_command = run("ps", "-ww", "-p", str(pid), "-o", "command=")
        try:
            args = shlex.split(raw_command)
        except ValueError:
            args = raw_command.split()
        profile = load_profile(args)
        tunnel = (option(args, "control-plane.tunnel-id") or
                  (profile.get("control_plane") or {}).get("tunnel_id") or "?")
        target = mcp_target(args, profile)
        port = health_port(pid, args, profile)
        ready, control = health_status(port)
        rows.append({
            "PID": str(pid),
            "Health": port,
            "Tunnel ID": str(tunnel),
            "MCP target": target,
            "Ready": ready,
            "Control plane": control,
        })
    return sorted(rows, key=lambda row: int(row["PID"]))


def table_lines(rows, fields):
    widths = {key: max(len(key), *(len(row[key]) for row in rows))
              for key in fields}
    def format_row(row):
        return "  ".join(row[key].ljust(widths[key]) for key in fields).rstrip()
    yield format_row({key: key for key in fields})
    yield "  ".join("-" * widths[key] for key in fields)
    for row in rows:
        yield format_row(row)


def main():
    parser = argparse.ArgumentParser(
        description="List locally running tunnel-client instances and MCP routing."
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--wide", action="store_true",
                      help="Always print a single-row table (requires a wide terminal).")
    mode.add_argument("--compact", action="store_true",
                      help="Put the MCP target on a separate indented line.")
    parser.add_argument("--json", action="store_true",
                        help="Print machine-readable JSON instead.")
    args = parser.parse_args()
    rows = discover()

    if args.json:
        print(json.dumps(rows, indent=2, ensure_ascii=False))
        return
    if not rows:
        print("No running tunnel-client processes found.")
        return

    wide_fields = ("PID", "Health", "Tunnel ID", "MCP target",
                   "Ready", "Control plane")
    full_width = max(len(line) for line in table_lines(rows, wide_fields))
    compact = args.compact or (
        not args.wide and full_width > shutil.get_terminal_size((120, 24)).columns
    )
    if not compact:
        print("\n".join(table_lines(rows, wide_fields)))
        return

    fields = ("PID", "Health", "Ready", "Control plane", "Tunnel ID")
    lines = list(table_lines(rows, fields))
    print(lines[0])
    print(lines[1])
    for row, line in zip(rows, lines[2:]):
        print(line)
        print(" " * 2 + "MCP: " + row["MCP target"])


if __name__ == "__main__":
    main()

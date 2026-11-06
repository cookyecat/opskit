Some useful scripts and utils in Linux.

For example. You can use `watchit.sh` to monitor a process. Once the process finished, run another command.
```
./watchit.sh ProcessID "command you want to run"

./watchit.sh 558855 "python main.py"
```

## tunnel-client status (macOS)

[`tunnels-status.py`](./tunnels-status.py) lists all running `tunnel-client` instances and prints their PID, local health port, Tunnel ID, MCP forwarding target, readiness, and control-plane state.

```bash
python3 tunnels-status.py             # Auto: aligned table or compact layout
python3 tunnels-status.py --wide      # Always one row per tunnel (wide terminals)
python3 tunnels-status.py --compact   # MCP target on a second line
python3 tunnels-status.py --json      # Machine-readable output
```

Requirements: macOS, Python 3, and the built-in `ps` and `lsof` commands. No third-party Python dependencies are needed for command-line arguments or JSON-formatted tunnel-client profiles. For profiles written in YAML syntax, install `PyYAML` (`python3 -m pip install PyYAML`).

The script is read-only. It queries each instance's loopback `/health?details=true` endpoint and does not print process arguments, credentials, or API keys. `Ready=yes` and `Control plane=polling` indicate local readiness/control-plane activity; they **do not prove** that the downstream MCP service has completed an authenticated tool call.

"""User-facing `phasorctl` command line API."""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from .client import request, stream_events


def _json(value: Any) -> None:
    print(json.dumps(value, ensure_ascii=False, indent=2))


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="phasorctl", description="Talk to Phasor services")
    commands = root.add_subparsers(dest="group", required=True)
    commands.add_parser("ping")
    commands.add_parser("snapshot")
    settings = commands.add_parser("settings").add_subparsers(dest="action", required=True)
    settings.add_parser("get")
    settings.add_parser("toggle")
    watch = commands.add_parser("watch")
    watch.add_argument("--events", action="store_true")
    rpc = commands.add_parser("rpc")
    rpc.add_argument("method")
    rpc.add_argument("params", nargs="?", default="{}")

    launcher = commands.add_parser("launcher").add_subparsers(dest="action", required=True)
    launcher.add_parser("toggle")
    command_palette = commands.add_parser("commands").add_subparsers(dest="action", required=True)
    command_palette.add_parser("toggle")

    plugins = commands.add_parser("plugins").add_subparsers(dest="action", required=True)
    plugins.add_parser("list").add_argument("--json", action="store_true")
    for action in ("enable", "disable"):
        sub = plugins.add_parser(action)
        sub.add_argument("id")
    approve = plugins.add_parser("approve")
    approve.add_argument("id")
    approve.add_argument("--grant", action="append", default=[])
    failure = plugins.add_parser("failure")
    failure.add_argument("id")
    failure.add_argument("message")
    call = plugins.add_parser("call")
    call.add_argument("id")
    call.add_argument("method")
    call.add_argument("params", nargs="?", default="{}")

    apps = commands.add_parser("apps").add_subparsers(dest="action", required=True)
    search_apps = apps.add_parser("search")
    search_apps.add_argument("query", nargs="?", default="")
    search_apps.add_argument("--limit", type=int, default=50)

    files = commands.add_parser("files").add_subparsers(dest="action", required=True)
    search_files = files.add_parser("search")
    search_files.add_argument("query", nargs="?", default="")
    search_files.add_argument("--limit", type=int, default=60)
    files.add_parser("status")
    for action in ("open", "reveal", "trash", "copy", "share"):
        sub = files.add_parser(action)
        sub.add_argument("path")
    rename_file = files.add_parser("rename")
    rename_file.add_argument("path")
    rename_file.add_argument("name")

    spaces = commands.add_parser("spaces").add_subparsers(dest="action", required=True)
    spaces.add_parser("list")
    for action in ("switch", "move-window"):
        sub = spaces.add_parser(action)
        sub.add_argument("id")
    for action in ("previous", "next"):
        sub = spaces.add_parser(action)
        sub.add_argument("--move", action="store_true")

    windows = commands.add_parser("windows").add_subparsers(dest="action", required=True)
    windows.add_parser("list")
    for action in ("focus", "close", "toggle-tiling", "always-on-top", "maximize", "fullscreen", "minimize"):
        sub = windows.add_parser(action)
        if action in {"focus", "close", "toggle-tiling", "always-on-top"}:
            sub.add_argument("id")
        else:
            sub.add_argument("id", nargs="?")
    clipboard = commands.add_parser("clipboard").add_subparsers(dest="action", required=True)
    clipboard.add_parser("toggle")
    clipboard.add_parser("history")
    copy = clipboard.add_parser("copy")
    copy.add_argument("text")
    restore = clipboard.add_parser("restore")
    restore.add_argument("id")

    audio = commands.add_parser("audio").add_subparsers(dest="action", required=True)
    audio.add_parser("status")
    volume = audio.add_parser("volume")
    volume.add_argument("value", type=float)
    audio.add_parser("mute")

    network = commands.add_parser("network").add_subparsers(dest="action", required=True)
    network.add_parser("status")
    wifi = network.add_parser("wifi")
    wifi.add_argument("state", choices=("on", "off"))

    bluetooth = commands.add_parser("bluetooth").add_subparsers(dest="action", required=True)
    bluetooth.add_parser("status")
    power = bluetooth.add_parser("power")
    power.add_argument("state", choices=("on", "off"))

    brightness = commands.add_parser("brightness").add_subparsers(dest="action", required=True)
    brightness.add_parser("status")
    brightness_set = brightness.add_parser("set")
    brightness_set.add_argument("percent", type=float)

    notifications = commands.add_parser("notifications").add_subparsers(dest="action", required=True)
    notifications.add_parser("status")
    notifications.add_parser("toggle")
    dnd = notifications.add_parser("dnd")
    dnd.add_argument("state", choices=("on", "off"))

    screenshot = commands.add_parser("screenshot").add_subparsers(dest="action", required=True)
    capture = screenshot.add_parser("capture")
    capture.add_argument("--copy", action="store_true")
    return root


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        result: Any
        if args.group == "ping":
            result = request("health")
        elif args.group == "snapshot":
            result = request("snapshot")
        elif args.group == "settings":
            result = request("settings.get" if args.action == "get" else "settings.toggle")
        elif args.group == "watch":
            if not args.events:
                raise ValueError("Use --events to subscribe")
            for event in stream_events():
                print(json.dumps(event, ensure_ascii=False), flush=True)
            return 0
        elif args.group == "rpc":
            result = request(args.method, json.loads(args.params))
        elif args.group == "launcher":
            result = request("launcher.toggle")
        elif args.group == "commands":
            result = request("commands.toggle")
        elif args.group == "plugins":
            if args.action == "list":
                result = request("plugins.list")
            elif args.action == "enable":
                result = request("plugins.enable", {"id": args.id})
            elif args.action == "disable":
                result = request("plugins.disable", {"id": args.id})
            elif args.action == "approve":
                result = request("plugins.approve", {"id": args.id, "capabilities": args.grant})
            elif args.action == "failure":
                result = request("plugins.report-failure", {"id": args.id, "message": args.message})
            else:
                # A plugin call is routed through a dedicated service boundary.
                params = json.loads(args.params)
                result = request("plugin.call", {"id": args.id, "method": args.method, "params": params})
        elif args.group == "apps":
            result = request("apps.search", {"query": args.query, "limit": args.limit})
        elif args.group == "files":
            if args.action == "search":
                result = request("files.search", {"query": args.query, "limit": args.limit})
            elif args.action == "status":
                result = request("files.status")
            elif args.action == "rename":
                result = request("files.rename", {"path": args.path, "name": args.name})
            else:
                result = request(f"files.{args.action}", {"path": args.path})
        elif args.group == "spaces":
            if args.action == "list":
                result = request("spaces.list")
            elif args.action in {"switch", "move-window"}:
                result = request("spaces.move_window" if args.action == "move-window" else "spaces.switch", {"id": args.id})
            else:
                result = request(f"spaces.{args.action}", {"move": args.move})
        elif args.group == "windows":
            if args.action == "list":
                result = request("windows.list")
            else:
                method = args.action.replace("-", "_")
                params = {"id": args.id} if args.id is not None else {}
                result = request(f"windows.{method}", params)
        elif args.group == "clipboard":
            if args.action == "toggle":
                result = request("clipboard.toggle")
            elif args.action == "history":
                result = request("clipboard.history")
            elif args.action == "restore":
                result = request("clipboard.restore", {"id": args.id})
            else:
                result = request("clipboard.copy", {"text": args.text})
        elif args.group == "audio":
            if args.action == "status":
                result = request("audio.get_volume")
            elif args.action == "volume":
                result = request("audio.set_volume", {"value": args.value})
            else:
                result = request("audio.toggle_mute")
        elif args.group == "network":
            result = request("network.status" if args.action == "status" else "network.set_wifi", {} if args.action == "status" else {"enabled": args.state == "on"})
        elif args.group == "bluetooth":
            result = request("bluetooth.status" if args.action == "status" else "bluetooth.set_power", {} if args.action == "status" else {"enabled": args.state == "on"})
        elif args.group == "brightness":
            result = request("brightness.status" if args.action == "status" else "brightness.set", {} if args.action == "status" else {"percent": args.percent})
        elif args.group == "notifications":
            if args.action == "status":
                result = request("notifications.status")
            elif args.action == "toggle":
                result = request("notifications.toggle")
            else:
                result = request("notifications.set_dnd", {"enabled": args.state == "on"})
        elif args.group == "screenshot":
            result = request("screenshots.capture", {"copyToClipboard": args.copy})
        else:
            raise ValueError("Unsupported command")
        _json(result)
        return 0
    except (OSError, RuntimeError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"phasorctl: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

"""Client for Phasor's per-user Unix-domain JSONL API."""

from __future__ import annotations

import json
import socket
from typing import Any, Iterator

from .config import runtime_home


def socket_path() -> str:
    return str(runtime_home() / "phasor.sock")


def request(method: str, params: dict[str, Any] | None = None, timeout: float = 5.0) -> Any:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        sock.connect(socket_path())
        sock.sendall((json.dumps({"method": method, "params": params or {}}) + "\n").encode("utf-8"))
        stream = sock.makefile("rb")
        line = stream.readline()
        if not line:
            raise RuntimeError("Phasor core closed the connection without a response")
        response = json.loads(line)
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"Could not contact Phasor core at {socket_path()}: {exc}") from exc
    finally:
        sock.close()
    if not response.get("ok"):
        raise RuntimeError(str(response.get("error", "Phasor core request failed")))
    return response.get("result")


def stream_events(timeout: float = 90.0) -> Iterator[dict[str, Any]]:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    sock.connect(socket_path())
    sock.sendall(b'{"method":"subscribe","params":{}}\n')
    stream = sock.makefile("rb")
    try:
        acknowledgement = stream.readline()
        if not acknowledgement:
            raise RuntimeError("Phasor core did not acknowledge event subscription")
        response = json.loads(acknowledgement)
        if not response.get("ok"):
            raise RuntimeError(str(response.get("error", "Subscription failed")))
        while True:
            line = stream.readline()
            if not line:
                return
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue
    finally:
        sock.close()

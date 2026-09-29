"""Per-user service daemon with a local JSONL-over-Unix-socket protocol."""

from __future__ import annotations

import json
import logging
import os
import queue
import signal
import socket
import socketserver
import threading
from pathlib import Path
from typing import Any

from .client import socket_path
from .config import runtime_home, state_home
from .events import EventBus
from .services import Services

LOG = logging.getLogger("phasor.core")


class CoreServer(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: str, services: Services, events: EventBus) -> None:
        self.services = services
        self.events = events
        super().__init__(address, CoreRequestHandler)


class CoreRequestHandler(socketserver.StreamRequestHandler):
    server: CoreServer

    def handle(self) -> None:
        while True:
            line = self.rfile.readline()
            if not line:
                return
            try:
                request = json.loads(line)
                method = str(request.get("method", ""))
                params = request.get("params", {})
                if not isinstance(params, dict):
                    raise ValueError("params must be a JSON object")
                if method == "subscribe":
                    self._subscribe()
                    return
                result = self.server.services.invoke(method, params)
                self._send({"ok": True, "result": result})
            except Exception as exc:
                LOG.warning("Request failed: %s", exc)
                self._send({"ok": False, "error": str(exc)})

    def _subscribe(self) -> None:
        subscriber = self.server.events.subscribe()
        self._send({"ok": True, "result": {"subscribed": True}})
        self._send({"type": "snapshot", "data": self.server.services.snapshot()})
        try:
            while True:
                try:
                    event = subscriber.get(timeout=30)
                except queue.Empty:
                    event = {"type": "heartbeat"}
                self._send(event)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            self.server.events.unsubscribe(subscriber)

    def _send(self, value: dict[str, Any]) -> None:
        self.wfile.write((json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8"))
        self.wfile.flush()


def _configure_logging() -> None:
    directory = state_home()
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    logging.basicConfig(
        level=os.environ.get("PHASOR_LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        handlers=[logging.FileHandler(directory / "core.log"), logging.StreamHandler()],
    )


def main() -> int:
    _configure_logging()
    path = Path(socket_path())
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        os.chmod(path.parent, 0o700)
    except OSError:
        pass
    if path.exists():
        # A live core is reused. Otherwise remove the stale socket left after a crash.
        try:
            from .client import request
            request("health", timeout=0.3)
            LOG.info("Phasor core is already running")
            return 0
        except Exception:
            try:
                path.unlink()
            except OSError as exc:
                LOG.error("Cannot remove stale core socket %s: %s", path, exc)
                return 1
    events = EventBus()
    services = Services(events.publish)
    server = CoreServer(str(path), services, events)
    os.chmod(path, 0o600)
    stopping = threading.Event()

    def stop(_signum: int, _frame: Any) -> None:
        if not stopping.is_set():
            stopping.set()
            threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    def poll() -> None:
        previous = None
        while not stopping.wait(0.8):
            try:
                state = services.refresh()
                if state != previous:
                    previous = state
            except Exception:
                LOG.exception("Mango state refresh failed")

    poller = threading.Thread(target=poll, name="phasor-mango-poller", daemon=True)
    poller.start()
    LOG.info("Phasor core listening at %s", path)
    try:
        server.serve_forever(poll_interval=0.25)
    finally:
        stopping.set()
        services.close()
        server.server_close()
        try:
            path.unlink(missing_ok=True)
        except OSError:
            pass
        LOG.info("Phasor core stopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

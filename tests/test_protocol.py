import os
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

from phasor_core.client import request
from phasor_core.daemon import CoreServer
from phasor_core.events import EventBus
from phasor_core.config import runtime_home


class FakeServices:
    def invoke(self, method, params):
        if method == "health":
            return {"ok": True, "apiVersion": 1}
        return {"method": method, "params": params}

    def snapshot(self):
        return {"available": True, "windows": [], "spaces": []}


class JsonlProtocolTests(unittest.TestCase):
    def test_unix_socket_request_round_trip(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"XDG_RUNTIME_DIR": directory}):
            path = Path(runtime_home()) / "phasor.sock"
            path.parent.mkdir(mode=0o700)
            server = CoreServer(str(path), FakeServices(), EventBus())
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                response = request("health", timeout=1)
                self.assertEqual(response, {"ok": True, "apiVersion": 1})
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main()

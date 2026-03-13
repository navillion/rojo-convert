from __future__ import annotations

import argparse
import json
import traceback
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from exporter.writer import ExportError, ExportWriter


class ExportServer(ThreadingHTTPServer):
    exporter: ExportWriter


class ExportRequestHandler(BaseHTTPRequestHandler):
    server_version = "RojoConvert/1.0"

    def do_GET(self) -> None:  # noqa: N802
        if self.path != "/health":
            self._send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "Not found."})
            return

        self._send_json(HTTPStatus.OK, {"ok": True})

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/export":
            self._send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "Not found."})
            return

        try:
            payload = self._read_json_body()
            result = self.server.exporter.export(payload)
        except ExportError as exc:
            self._send_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return
        except json.JSONDecodeError:
            self._send_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": "Request body was not valid JSON."})
            return
        except Exception as exc:  # pragma: no cover - defensive error handling
            traceback.print_exc()
            self._send_json(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                {"ok": False, "error": f"Unhandled exporter error: {exc}"},
            )
            return

        self._send_json(HTTPStatus.OK, result)

    def log_message(self, format_string: str, *args: Any) -> None:
        return

    def _read_json_body(self) -> dict[str, Any]:
        content_length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(content_length)
        decoded = json.loads(body.decode("utf-8"))
        if not isinstance(decoded, dict):
            raise ExportError("Request body must be a JSON object.")
        return decoded

    def _send_json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
        encoded = json.dumps(payload).encode("utf-8")
        self.send_response(status.value)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the Rojo-convert localhost export service.")
    parser.add_argument("--host", default="127.0.0.1", help="Host interface to bind. Default: 127.0.0.1")
    parser.add_argument("--port", type=int, default=34873, help="TCP port to listen on. Default: 34873")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("exports"),
        help="Directory where exported Rojo trees should be written. Default: ./exports",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    server = ExportServer((args.host, args.port), ExportRequestHandler)
    server.exporter = ExportWriter(args.output)

    print(f"Rojo-convert exporter listening on http://{args.host}:{args.port}")
    print(f"Writing exports to {server.exporter.output_root}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down exporter.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()


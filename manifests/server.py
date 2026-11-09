import json
import sqlite3
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


DATABASE = "/data/test.sqlite3"


class Handler(BaseHTTPRequestHandler):
    def respond(self, status, payload=None):
        body = b"" if payload is None else json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def body(self):
        length = int(self.headers.get("Content-Length", "0"))
        if not 0 < length <= 4096:
            raise ValueError("Request body must be between 1 and 4096 bytes")
        payload = json.loads(self.rfile.read(length))
        if not isinstance(payload, dict) or not isinstance(payload.get("value"), str):
            raise ValueError("Expected an object with a string value")
        return payload

    def handle_request(self):
        path = urlsplit(self.path).path
        if self.command == "GET" and path == "/healthz":
            with sqlite3.connect(DATABASE, timeout=5) as database:
                database.execute("SELECT 1")
            self.respond(200, {"status": "ok"})
            return
        if self.command == "POST" and path == "/items":
            payload = self.body()
            item_id = payload.get("id")
            if not isinstance(item_id, str) or not item_id:
                raise ValueError("Expected a non-empty string id")
            with sqlite3.connect(DATABASE, timeout=5) as database:
                database.execute(
                    "INSERT INTO items (id, value) VALUES (?, ?)",
                    (item_id, payload["value"]),
                )
            self.respond(201, {"id": item_id, "value": payload["value"]})
            return
        if not path.startswith("/items/") or not path[len("/items/"):]:
            self.respond(404, {"error": "Not found"})
            return
        item_id = path[len("/items/"):]
        with sqlite3.connect(DATABASE, timeout=5) as database:
            if self.command == "GET":
                row = database.execute(
                    "SELECT value FROM items WHERE id = ?", (item_id,)
                ).fetchone()
                if row is None:
                    self.respond(404, {"error": "Not found"})
                else:
                    self.respond(200, {"id": item_id, "value": row[0]})
            elif self.command == "PUT":
                payload = self.body()
                cursor = database.execute(
                    "UPDATE items SET value = ? WHERE id = ?",
                    (payload["value"], item_id),
                )
                database.commit()
                if cursor.rowcount == 0:
                    self.respond(404, {"error": "Not found"})
                else:
                    self.respond(200, {"id": item_id, "value": payload["value"]})
            elif self.command == "DELETE":
                cursor = database.execute("DELETE FROM items WHERE id = ?", (item_id,))
                database.commit()
                if cursor.rowcount == 0:
                    self.respond(404, {"error": "Not found"})
                else:
                    self.respond(204)

    def dispatch(self):
        try:
            self.handle_request()
        except ValueError as error:
            self.log_error("Invalid request: %s", error)
            self.respond(400, {"error": str(error)})
        except sqlite3.IntegrityError as error:
            self.log_error("Conflict: %s", error)
            self.respond(409, {"error": "Record already exists"})
        except sqlite3.OperationalError as error:
            self.log_error("Database operation failed: %s", error)
            self.respond(503, {"error": "Database unavailable"})

    do_GET = dispatch
    do_POST = dispatch
    do_PUT = dispatch
    do_DELETE = dispatch


if __name__ == "__main__":
    with sqlite3.connect(DATABASE) as database:
        database.execute("PRAGMA journal_mode=WAL")
        database.execute(
            "CREATE TABLE IF NOT EXISTS items (id TEXT PRIMARY KEY, value TEXT NOT NULL)"
        )
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()

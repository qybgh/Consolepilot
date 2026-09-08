#!/usr/bin/env python3
import argparse
import http.server
import time


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/stream":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        for value in ["你", "好", " 🌏"]:
            self.wfile.write((f"data: {value}\n\n").encode("utf-8"))
            self.wfile.flush()
            time.sleep(self.server.interval)
        if not self.server.cut:
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()

    def log_message(self, *_args):
        return


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=18765)
    parser.add_argument("--interval", type=float, default=0.05)
    parser.add_argument("--cut", action="store_true")
    args = parser.parse_args()
    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.interval = args.interval
    server.cut = args.cut
    print(f"mock SSE listening on 127.0.0.1:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()

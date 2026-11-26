import builtins;

import http.server;

import threading;

import urllib.parse;

import webbrowser;

def loopback_code(
    auth_url: str, state: str, signer: str, service: str, servers: any, port: int, error_keys: any
) -> builtins.dict | None {
    result: builtins.dict = {};
    done = threading.Event();
    page = f"<h2>Sellbird is connected to {service}.</h2>You can close this tab.".encode();
    class Handler(http.server.BaseHTTPRequestHandler) {
        def do_GET {
            query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query);
            if query.get("state", [""])[0] != state {
                self.send_response(400);
                self.end_headers();
                return;
            }
            result["code"] = query.get("code", [""])[0];
            result["error"] = next((query[k][0] for k in error_keys if query.get(k)), None) or "";
            self.send_response(200);
            self.send_header("Content-Type", "text/html");
            self.end_headers();
            self.wfile.write(page);
            done.set();
        }

        def log_message(*args: any) {}
    }
    bound: list[any] = [];
    for (server_class, host) in servers {
        try {
            bound.append(server_class((host, port), Handler));
        } except OSError {
            if not bound {
                raise;
            }
        }
    }
    for server in bound {
        threading.Thread(target=server.serve_forever, daemon=True).start();
    }
    print(f"\n  Opening browser for {signer} sign-in...\n  {auth_url}\n");
    webbrowser.open(auth_url);
    finished = done.wait(timeout=300);
    for server in bound {
        server.shutdown();
        server.server_close();
    }
    if not finished {
        print("  Timed out waiting for the browser round-trip.");
        return None;
    }
    if result.get("error") or not result.get("code") {
        print(f"  Authorization failed: {result.get('error') or 'no code returned'}");
        return None;
    }
    return result;
}

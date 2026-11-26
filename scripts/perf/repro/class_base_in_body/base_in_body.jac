def serve {
    import http.server;
    class Handler(http.server.BaseHTTPRequestHandler) {}
    print(Handler.__name__);
}

with entry {
    serve();
}

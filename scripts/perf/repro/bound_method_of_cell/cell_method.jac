import json;

with entry {
    rows: any = json.loads("[{\"a\": 1, \"b\": 2}]");
    for r in rows {
        print([r.get(k) for k in ("a", "b")]);
        print([v for v in map(r.get, ("a", "b"))]);
    }
}

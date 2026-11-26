graph layers {
    layer all { *; }
}

graph spaces {
    space py: cpython { entry decorated_glob; }
    app repro { run py; }
}

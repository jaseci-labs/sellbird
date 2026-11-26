graph layers {
    layer all { *; }
}

graph spaces {
    space py: cpython { entry base_in_body; }
    app repro { run py; }
}

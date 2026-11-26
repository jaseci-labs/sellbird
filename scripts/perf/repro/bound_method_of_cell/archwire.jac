graph layers {
    layer all { *; }
}

graph spaces {
    space py: cpython { entry cell_method; }
    app repro { run py; }
}

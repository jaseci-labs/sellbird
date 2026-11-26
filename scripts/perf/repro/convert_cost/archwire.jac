graph layers {
    layer all { *; }
}

graph spaces {
    space py: cpython { entry convert_cost; }
    app repro { run py; }
}

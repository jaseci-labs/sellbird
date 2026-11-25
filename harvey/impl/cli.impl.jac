impl _find_sellbird -> any {
    try {
        import sellbird;
    } except ModuleNotFoundError {
        checkout: any = Path(__file__).resolve().parent.parent;
        if (checkout / "sellbird" / "__init__.py").is_file() {
            sys.path.insert(0, `str(checkout));
        }
    }
}

impl main -> any {
    print(NOTICE, file=sys.stderr);
    _find_sellbird();
    import from sellbird.cli { main as sellbird_main }
    sys.argv[0] = "sellbird";
    return sellbird_main();
}

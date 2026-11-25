import sys;
import from pathlib { Path }

def _find_sellbird {
    try {
        import sellbird;
    } except ModuleNotFoundError {
        checkout = Path(__file__).resolve().parent.parent;
        if (checkout / "sellbird" / "__init__.py").is_file() {
            sys.path.insert(0, str(checkout));
        }
    }
}

def main -> any {
    print(NOTICE, file=sys.stderr);
    _find_sellbird();
    import from sellbird.cli { main as sellbird_main }
    sys.argv[0] = "sellbird";
    return sellbird_main();
}

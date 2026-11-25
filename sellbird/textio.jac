import locale;
import logging;
import sys;
import from pathlib { Path }

glob logger = logging.getLogger("sellbird.textio");

def read_user_text(path: any) -> str {
    data = Path(path).read_bytes();
    try {
        text = data.decode("utf-8-sig");
    } except UnicodeDecodeError {
        encoding = locale.getencoding();
        logger.warning(
            f"{path} isn't saved as UTF-8; read it as {encoding}. Re-save it as UTF-8 to keep characters like ★ or — intact.",
        );
        text = data.decode(encoding, errors="replace");
    }
    return text.replace("\r\n", "\n").replace("\r", "\n");
}

def utf8_stdio(*streams: any) {
    for stream in streams or (sys.stdout, sys.stderr) {
        try {
            stream.reconfigure(
                encoding="utf-8", errors="backslashreplace" if stream is sys.stderr else "replace"
            );
        } except (AttributeError, ValueError, OSError) {}
    }
}

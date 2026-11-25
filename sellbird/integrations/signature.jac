import hashlib;
import html;
import re;
import from dataclasses { dataclass }
import from email.message { EmailMessage }
import from pathlib { Path }

glob MAX_LOGO_BYTES = 100000,
     MAX_LOGO_PIXELS = 20000,
     _URL = re.compile("https?://[!#-;=?-~]+"),
     _URL_TRAILING = ".,;:!?)]}'",
     _MAGIC = (
         (b"\x89PNG\r\n\x1a\n", "image/png"),
         (b"\xff\xd8\xff", "image/jpeg"),
         (b"GIF87a", "image/gif"),
         (b"GIF89a", "image/gif"),
     );

class SignatureError(ValueError) {}

@dataclass(frozen=True)
class Signature {
    has data: bytes,
        mime: str,
        filename: str,
        content_id: str,
        width: int,
        height: int,
        alt: str,
        link: str,
        direction: str;
}

def _settings(config: any) -> any {
    return getattr(getattr(getattr(config, "channels", None), "email", None), "signature", None);
}

def load_signature(config: any) -> Signature | None {
    settings = _settings(config);
    logo = (getattr(settings, "logo", "") or "").strip();
    if not logo {
        return None;
    }
    try {
        path = Path(logo).expanduser();
        if not path.is_absolute() {
            path = PROJECT_ROOT / path;
        }
        size = path.stat().st_size;
        if size > MAX_LOGO_BYTES {
            raise SignatureError(
                f"logo {path.name} is {size // 1000} KB; keep it under {MAX_LOGO_BYTES // 1000} KB"
            );
        }
        data = path.read_bytes();
    } except FileNotFoundError {
        raise SignatureError(f"logo file not found: {path}") from None;
    } except (OSError, RuntimeError, ValueError) as e {
        raise SignatureError(f"logo file can't be read: {logo} ({e})") from None;
    }
    mime = _image_type(data);
    if not mime {
        raise SignatureError(f"logo {path.name} isn't a PNG, JPEG or GIF image");
    }
    width = int(getattr(settings, "width", 120) or 120);
    size_px = _image_size(data, mime);
    if not size_px or not all([0 < n and n <= MAX_LOGO_PIXELS for n in size_px]) {
        raise SignatureError(f"logo {path.name} is a damaged image");
    }
    company = getattr(getattr(config, "persona", None), "company", "") or "";
    return Signature(
        data=data,
        mime=mime,
        filename=path.name,
        content_id=f"logo-{hashlib.sha256(data).hexdigest()[:16]}",
        width=width,
        height=round(width * size_px[1] / size_px[0]),
        alt=(getattr(settings, "alt", "") or company or "logo").strip(),
        link=(getattr(settings, "link", "") or "").strip(),
        direction=(getattr(settings, "direction", "") or "auto").strip().lower(),
    );
}

def signature_problem(config: any) -> str {
    try {
        load_signature(config);
    } except SignatureError as e {
        return str(e);
    }
    return "";
}

def render_html(body: str, sig: Signature) -> str {
    paragraphs = [
        p
        for p in re.split("\\n[ \\t]*\\n", body.replace("\r\n", "\n").strip())
        if p.strip()
    ];
    text = "\n".join([f"<p style=\"margin:0 0 1em 0\">{_paragraph(p)}</p>" for p in paragraphs]);
    img = f"<img src=\"cid:{sig.content_id}\" width=\"{sig.width}\" height=\"{sig.height}\" alt=\"{html.escape(sig.alt)}\" style=\"display:block;border:0;width:{sig.width}px;height:auto\">";
    if sig.link {
        img = f"<a href=\"{html.escape(sig.link)}\">{img}</a>";
    }
    align = "right" if sig.direction == "rtl" else "left";
    direction = "dir=\"auto\""
        if sig.direction == "auto"
        else f"dir=\"{sig.direction}\" style=\"direction:{sig.direction};text-align:{align}\"";
    return f"<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"></head><body>\n<div {direction}>\n<div style=\"font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.5\">\n{text}\n<div style=\"margin-top:1.5em\">{img}</div>\n</div>\n</div>\n</body></html>\n";
}

def set_body(msg: EmailMessage, body: str, sig: Signature | None) {
    msg.set_content(body);
    if sig is None {
        return;
    }
    msg.add_alternative(render_html(body, sig), subtype="html");
    (maintype, subtype) = sig.mime.split("/") as any;
    msg.get_payload()[-1].add_related(
        sig.data,
        maintype=maintype,
        subtype=subtype,
        cid=f"<{sig.content_id}>",
        filename=sig.filename,
        disposition="inline",
    );
}

def _paragraph(text: str) -> str {
    out: list[str] = [];
    pos = 0;
    for m in _URL.finditer(text) {
        url = m.group(0).rstrip(_URL_TRAILING);
        if len(url) > len("https://") {
            out.append(html.escape(text[pos:m.start()], quote=False));
            out.append(f"<a href=\"{html.escape(url)}\">{html.escape(url, quote=False)}</a>");
            pos = m.start() + len(url);
        }
    }
    out.append(html.escape(text[pos:], quote=False));
    return "".join(out).replace("\n", "<br>\n");
}

def _image_type(data: bytes) -> str {
    return next((m for (magic, m) in _MAGIC if data.startswith(magic)), "");
}

def _image_size(data: bytes, mime: str) -> tuple[int, int] | None {
    if mime == "image/png" and len(data) >= 24 and data[12:16] == b"IHDR" {
        return (int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big"));
    }
    if mime == "image/gif" and len(data) >= 10 {
        return (int.from_bytes(data[6:8], "little"), int.from_bytes(data[8:10], "little"));
    }
    i = 2;
    while mime == "image/jpeg" and i + 9 < len(data) {
        if data[i] != 255 {
            return None;
        }
        marker = data[i + 1];
        if 192 <= marker and marker <= 207 and marker not in (196, 200, 204) {
            return (
                int.from_bytes(data[i + 7:i + 9], "big"),
                int.from_bytes(data[i + 5:i + 7], "big"),
            );
        }
        i += 2 + int.from_bytes(data[i + 2:i + 4], "big");
    }
    return None;
}

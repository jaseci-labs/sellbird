impl SignatureError.__repr__ -> str {
    return (getattr(builtins.super(SignatureError, self), "__repr__") as any)();
}

impl SignatureError.__eq__(other: any) -> bool {
    return self is other;
}

impl SignatureError.__hash__ -> int {
    return id(self);
}

impl _settings(config) -> any {
    email: any = getattr(getattr(config, "channels", None), "email", None);
    return getattr(email, "signature", None);
}

impl load_signature(config) -> Signature | None {
    settings: any = _settings(config);
    logo: any = (getattr(settings, "logo", "") or "").strip();
    if not logo {
        return None;
    }
    try {
        path: any = Path(logo).expanduser();
        if not path.is_absolute() {
            path = PROJECT_ROOT / path;
        }
        size: any = path.stat().st_size;
        if size > MAX_LOGO_BYTES {
            raise SignatureError(
                f"logo {path.name} is {size // 1000} KB; keep it under {MAX_LOGO_BYTES // 1000} KB"
            );
        }
        data: any = path.read_bytes();
    } except FileNotFoundError {
        raise SignatureError(f"logo file not found: {path}") from None;
    } except (OSError, RuntimeError, ValueError) as e {
        raise SignatureError(f"logo file can't be read: {logo} ({e})") from None;
    }
    mime: any = _image_type(data);
    if not mime {
        raise SignatureError(f"logo {path.name} isn't a PNG, JPEG or GIF image");
    }
    width: any = `int(getattr(settings, "width", 120) or 120);
    size_px: any = _image_size(data, mime);
    if not size_px
        or not all(operator.lt(0, n) and operator.le(n, MAX_LOGO_PIXELS) for n in size_px)
    {
        raise SignatureError(f"logo {path.name} is a damaged image");
    }
    height: any = round(width * size_px[1] / size_px[0]);
    company: any = getattr(getattr(config, "persona", None), "company", "") or "";
    return Signature(
        data=data,
        mime=mime,
        filename=path.name,
        content_id=f"logo-{hashlib.sha256(data).hexdigest()[:16]}",
        width=width,
        height=height,
        alt=(getattr(settings, "alt", "") or company or "logo").strip(),
        link=(getattr(settings, "link", "") or "").strip(),
        direction=(getattr(settings, "direction", "") or "auto").strip().lower(),
    );
}

impl signature_problem(config) -> builtins.str {
    try {
        load_signature(config);
    } except SignatureError as e {
        return `str(e);
    }
    return "";
}

impl render_html(body: builtins.str, sig: Signature) -> builtins.str {
    paragraphs: any = [
        p
        for p in re.split("\\n[ \\t]*\\n", body.replace("\r\n", "\n").strip())
        if p.strip()
    ];
    text: any = "\n".join(f"<p style=\"margin:0 0 1em 0\">{_paragraph(p)}</p>" for p in paragraphs);
    height: any = f" height=\"{sig.height}\"";
    img: any = f"<img src=\"cid:{sig.content_id}\" width=\"{sig.width}\"{height} alt=\"{html.escape(sig.alt)}\" style=\"display:block;border:0;width:{sig.width}px;height:auto\">";
    if sig.link {
        img = f"<a href=\"{html.escape(sig.link)}\">{img}</a>";
    }
    if sig.direction == "auto" {
        direction: any = "dir=\"auto\"";
    } else {
        align: any = "right" if sig.direction == "rtl" else "left";
        direction = f"dir=\"{sig.direction}\" style=\"direction:{sig.direction};text-align:{align}\"";
    }
    return f"<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"></head><body>\n<div {direction}>\n<div style=\"font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.5\">\n{text}\n<div style=\"margin-top:1.5em\">{img}</div>\n</div>\n</div>\n</body></html>\n";
}

impl set_body(msg: EmailMessage, body: builtins.str, sig: Signature | None) -> any {
    msg.set_content(body);
    if sig is None {
        return;
    }
    msg.add_alternative(render_html(body, sig), subtype="html");
    maintype: any;
    subtype: any;
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

impl _paragraph(text: builtins.str) -> builtins.str {
    out: any;
    pos: any;
    (out, pos) = ([], 0);
    for m in _URL.finditer(text) {
        url: any = m.group(0).rstrip(_URL_TRAILING);
        if len(url) <= len("https://") {
            continue;
        }
        out.append(html.escape(text[pos:m.start()], quote=False));
        out.append(f"<a href=\"{html.escape(url)}\">{html.escape(url, quote=False)}</a>");
        pos = m.start() + len(url);
    }
    out.append(html.escape(text[pos:], quote=False));
    return "".join(out).replace("\n", "<br>\n");
}

impl _image_type(data: builtins.bytes) -> builtins.str {
    if data.startswith(b"\x89PNG\r\n\x1a\n") {
        return "image/png";
    }
    if data.startswith(b"\xff\xd8\xff") {
        return "image/jpeg";
    }
    if data[:6] in (b"GIF87a", b"GIF89a") {
        return "image/gif";
    }
    return "";
}

impl _image_size(
    data: builtins.bytes, mime: builtins.str
) -> builtins.tuple[builtins.int, builtins.int] | None {
    if mime == "image/png" and len(data) >= 24 and data[12:16] == b"IHDR" {
        return (int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big"));
    }
    if mime == "image/gif" and len(data) >= 10 {
        return (int.from_bytes(data[6:8], "little"), int.from_bytes(data[8:10], "little"));
    }
    if mime == "image/jpeg" {
        i: any = 2;
        while i + 9 < len(data) {
            if data[i] != 255 {
                return None;
            }
            marker: any = data[i + 1];
            length: any = int.from_bytes(data[i + 2:i + 4], "big");
            if 192 <= marker <= 207 and marker not in (196, 200, 204) {
                return (
                    int.from_bytes(data[i + 7:i + 9], "big"),
                    int.from_bytes(data[i + 5:i + 7], "big"),
                );
            }
            i += 2 + length;
        }
    }
    return None;
}

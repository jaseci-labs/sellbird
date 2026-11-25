impl fence(text, source: builtins.str) -> builtins.str {
    import unicodedata;
    clean: any = _ZERO_WIDTH_RE.sub("", unicodedata.normalize("NFKC", `str(text or "")));
    clean = _TAG_RE.sub("[tag removed]", clean);
    label: any = re.sub("[^\\w ,.-]", "", source)[:40];
    return f"<untrusted source=\"{label}\">\n{clean}\n</untrusted>";
}

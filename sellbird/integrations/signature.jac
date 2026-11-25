"""A logo under every email the native providers send.

Off by default: email goes out as plain text. With
``channels.email.signature.logo`` set, Gmail, Microsoft 365 and SMTP send
each email as HTML, with the logo embedded in the message itself (an inline
``cid:`` image), so it shows without the recipient allowing remote images.
Gmail and SMTP also carry the same plain text as the HTML's alternative.

The words are the ones Sellbird wrote, unchanged: the HTML is that text,
escaped, with its paragraphs and line breaks kept and its web addresses made
clickable. The pre-send gate checks that text, so the only link the HTML adds
is the logo's own ``link``, which you set.

A logo that's missing, too big or not an image never lets an email go out
without it: the sender holds the outbox (``signature_problem``) and the
providers refuse to send (``SignatureError``).
"""

import builtins;

import operator;

import hashlib;

import html;

import re;

import from dataclasses { dataclass }

import from email.message { EmailMessage }

import from pathlib { Path }

glob MAX_LOGO_BYTES: any = 100000;

glob MAX_LOGO_PIXELS: any = 20000;

glob _URL: any = re.compile("https?://[!#-;=?-~]+");

glob _URL_TRAILING: any = ".,;:!?)]}'";

obj SignatureError(ValueError) {
    def __repr__ -> str;

    def __eq__(other: any) -> bool;

    def __hash__ -> int;
}

@dataclass(frozen=True)
class Signature {
    has data: builtins.bytes;

    has mime: builtins.str;

    has filename: builtins.str;

    has content_id: builtins.str;

    has width: builtins.int;

    has height: builtins.int;

    has alt: builtins.str;

    has link: builtins.str;

    has direction: builtins.str;
}

def _settings(config) -> any;

"""The configured signature, or None when there isn't one. Raises
    SignatureError when there is one but its logo can't be used."""
def load_signature(config) -> Signature | None;

"""Why the configured signature can't be used, or "" when it can (or
    when there's none)."""
def signature_problem(config) -> builtins.str;

"""The email as HTML: Sellbird's text, then the logo."""
def render_html(body: builtins.str, sig: Signature) -> builtins.str;

"""Plain text alone, or with a signature: plain text plus an HTML
    alternative that carries the logo as an inline image."""
def set_body(msg: EmailMessage, body: builtins.str, sig: Signature | None) -> any;

def _paragraph(text: builtins.str) -> builtins.str;

def _image_type(data: builtins.bytes) -> builtins.str;

"""(width, height) from the image's header, or None."""
def _image_size(
    data: builtins.bytes, mime: builtins.str
) -> builtins.tuple[builtins.int, builtins.int] | None;

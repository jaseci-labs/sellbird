"""Text files and console output, the same on every platform.

Sellbird reads and writes its files as UTF-8. Windows' default is the locale
code page (cp1252), so files saved there by an older Sellbird, or edited in a
Windows tool, may not be UTF-8: those are still read, with a warning.
"""

import builtins;

import locale;

import logging;

import sys;

import from pathlib { Path }

glob logger: any = logging.getLogger("sellbird.textio");

"""A file a person or an older Sellbird may have saved (sellbird.yaml, .env,
    skills, prompts): UTF-8, with or without a BOM, else the locale's code
    page. Line endings come back as 
, as text-mode reads give them.
    Raises what reading the file raises (FileNotFoundError...)."""
def read_user_text(path) -> builtins.str;

def _newlines(text: builtins.str) -> builtins.str;

"""Write output as UTF-8. On Windows, output going to a file or pipe (the
    dashboard's log of `sellbird run`) uses the locale code page, where "⚠" or
    "→" in a message would crash print(). stderr keeps backslash escapes, so
    odd bytes stay diagnosable."""
def utf8_stdio(*streams_) -> any;

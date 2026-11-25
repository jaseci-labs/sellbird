"""Hard style rules for every email Sellbird writes.

The writer prompt asks for these, and a model still slips. These checks are
code, so a slip never reaches a prospect: the Writer sends a failing draft
back for one rewrite and drops it if the rewrite fails too; the Sender holds
a failing email for review instead of sending it; the dashboard refuses an
edit that breaks them.

Two kinds of rule:

- **Always** (every email Sellbird writes, cold or reply): no em or en
  dashes or a spaced hyphen used as one, no exclamation marks, no
  formatting, none of the phrases that mark an email as AI-written or
  salesy.
- **Cold email shape** (Sellbird's built-in shape only; operator email
  rules replace it): a word cap per step, one question at most, and an
  opening that isn't about the sender.

Curly quotes, ellipsis characters and non-breaking spaces aren't errors a
rewrite should spend a model call on: ``tidy`` straightens them.
"""

import builtins;

import re;

glob FIRST_EMAIL_MAX_WORDS: any = 60;

glob FOLLOW_UP_MAX_WORDS: any = 50;

glob BREAKUP_MAX_WORDS: any = 30;

glob REPLY_MAX_WORDS: any = 120;

"""The cap for sequence step ``step`` (1-based)."""
def max_words(step: builtins.int) -> builtins.int;

glob _DASH_CHARS: any = "‒–—―−";

glob _SPACED_HYPHEN_RE: any = re.compile("(?<=\\S) +-{1,3} +(?=\\S)|(?<=\\w)--(?=\\w)");

glob _LIST_LINE_RE: any = re.compile("^\\s*(?:[-*•●▪]|\\d{1,2}[.)])\\s+\\S", re.MULTILINE);

glob _MARKDOWN_RE: any = re.compile(
    "\\*\\*[^*\\n]+\\*\\*|__[^_\\n]+__|^\\s*#{1,6}\\s", re.MULTILINE
);

glob AI_TELLS: any = (
    "hope this finds you",
    "hope this email finds you",
    "hope you're doing well",
    "hope you are doing well",
    "hope you're well",
    "hope all is well",
    "i know you're busy",
    "i know you are busy",
    "reaching out because",
    "i'm reaching out",
    "i am reaching out",
    "just wanted to",
    "wanted to reach out",
    "just following up",
    "just checking in",
    "following up on my",
    "circling back",
    "circle back",
    "touch base",
    "i'd love to",
    "i would love to",
    "in today's",
    "fast-paced",
    "picture this",
    "imagine if",
    "imagine a world",
    "what if i told you",
    "here's the thing",
    "here is the thing",
    "the truth is",
    "funny enough",
    "let that sink in",
    "worth a quick",
    "quick question",
    "no pressure",
    "no obligation",
    "no strings",
    "would you be open to",
    "let me know if you're interested",
    "let me know if you are interested",
    "are you the right person",
    "game-changer",
    "game changer",
    "gamechanger",
    "revolutionize",
    "revolutionise",
    "cutting-edge",
    "cutting edge",
    "next-level",
    "next level",
    "supercharge",
    "unlock",
    "unleash",
    "elevate",
    "empower",
    "seamless",
    "seamlessly",
    "leverage",
    "leveraging",
    "synergy",
    "synergies",
    "delve",
    "tapestry",
    "testament to",
    "robust",
    "crucial",
    "pivotal",
    "transformative",
    "transform your",
    "streamline",
    "pain point",
    "pain points",
    "best-in-class",
    "world-class",
    "low-hanging fruit",
    "move the needle",
    "at the end of the day",
    "a whole new level",
    "it's not about",
    "it is not about",
    "isn't about",
    "this isn't just",
    "it's not just",
    "it isn't just",
    "not just a",
);

glob _TELL_RES: any = `tuple(
    (phrase, re.compile("(?<![\\w-])" + re.escape(phrase).replace("'", "['’]") + "(?![\\w-])"))
    for phrase in AI_TELLS,
);

glob _NOT_ONLY_BUT_RE: any = re.compile(
    "\\bnot (?:only|just|merely) [^.?!\\n]{1,60}?\\bbut\\b", re.IGNORECASE
);

glob _GREETING_RE: any = re.compile(
    "^(?:hi|hey|hello|dear|good (?:morning|afternoon))\\b[^\\n]{0,40}$|^\\w[\\w .'-]{0,30},$",
    re.IGNORECASE,
);

glob _SELF_OPENING_RE: any = re.compile(
    "^(?:i|we|i'm|we're|i've|we've|i'd|we'd|my|our)\\b", re.IGNORECASE
);

glob _TIDY: any = str.maketrans({
    "‘": "'",
    "’": "'",
    "‚": "'",
    "‛": "'",
    "′": "'",
    "“": "\"",
    "”": "\"",
    "„": "\"",
    "″": "\"",
    " ": " ",
    " ": " ",
    " ": " ",
    " ": " ",
    "​": "",
    "⁠": "",
    "﻿": "",
});

glob _SIGN_OFF_RE: any = re.compile(
    "^(?:best|best wishes|thanks|thank you|thanks again|many thanks|cheers|regards|best regards|kind regards|warm regards|warmly|talk soon|speak soon|all the best|sincerely|take care)[,.]?$",
    re.IGNORECASE,
);

"""Straight quotes, plain spaces and "..." for what a model types fancy.

    Changes nothing a reader would call a different word, so it never needs
    a model call or a review."""
def tidy(text: builtins.str) -> builtins.str;

def words(text: builtins.str) -> builtins.int;

"""``text`` with each known name (company, person) blanked out, so a
    company called "Elevate Fitness" isn't an AI tell."""
def _blank(text: builtins.str, names) -> builtins.str;

"""The first line after any greeting ("Hi Sam," / "Sam,")."""
def _first_line(body: builtins.str) -> builtins.str;

"""Why this email breaks Sellbird's writing rules, or [] when it doesn't.

    kind: "cold" for a sequence email, "reply" for an answer to someone.
    step: the sequence step, for the word cap.
    names: the prospect's name, company and similar: text that is theirs, so
        it is never read as a tell.
    shape: False when the operator's own email rules set length and
        structure; the always-rules still apply.

    Each reason says what to change, in words a person editing the draft can
    act on.
    """
def style_problems(
    subject: builtins.str,
    body: builtins.str,
    *,
    kind: builtins.str = "cold",
    step: builtins.int = 1,
    names=(),
    shape: builtins.bool = True,
) -> builtins.list[builtins.str];

"""``body`` ending in the sender's first name on its own line, and no
    other sign-off.

    Models sign off three different ways in ten emails ("Best,", "Thanks,",
    none at all); one plain name under every email reads like a person who
    writes a lot of email. An empty ``name`` leaves the body as it is."""
def with_sign_off(body: builtins.str, name: builtins.str) -> builtins.str;

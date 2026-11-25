import re;

glob FIRST_EMAIL_MAX_WORDS = 60,
     FOLLOW_UP_MAX_WORDS = 50,
     BREAKUP_MAX_WORDS = 30,
     REPLY_MAX_WORDS = 120;

glob _DASH_CHARS = "‒–—―−",
     _SPACED_HYPHEN_RE = re.compile("(?<=\\S) +-{1,3} +(?=\\S)|(?<=\\w)--(?=\\w)"),
     _LIST_LINE_RE = re.compile("(?m)^\\s*(?:[-*•●▪]|\\d{1,2}[.)])\\s+\\S"),
     _MARKDOWN_RE = re.compile("(?m)\\*\\*[^*\\n]+\\*\\*|__[^_\\n]+__|^\\s*#{1,6}\\s");

glob AI_TELLS = tuple(
         ("hope this finds you|hope this email finds you|hope you're doing well|hope you are doing well|hope you're well|"
             "hope all is well|i know you're busy|i know you are busy|reaching out because|i'm reaching out|i am reaching out|"
             "just wanted to|wanted to reach out|just following up|just checking in|following up on my|circling back|"
             "circle back|touch base|i'd love to|i would love to|in today's|fast-paced|picture this|imagine if|"
             "imagine a world|what if i told you|here's the thing|here is the thing|the truth is|funny enough|"
             "let that sink in|worth a quick|quick question|no pressure|no obligation|no strings|would you be open to|"
             "let me know if you're interested|let me know if you are interested|are you the right person|game-changer|"
             "game changer|gamechanger|revolutionize|revolutionise|cutting-edge|cutting edge|next-level|next level|"
             "supercharge|unlock|unleash|elevate|empower|seamless|seamlessly|leverage|leveraging|synergy|synergies|delve|"
             "tapestry|testament to|robust|crucial|pivotal|transformative|transform your|streamline|pain point|pain points|"
             "best-in-class|world-class|low-hanging fruit|move the needle|at the end of the day|a whole new level|"
             "it's not about|it is not about|isn't about|this isn't just|"
             "it's not just|it isn't just|not just a").split("|"),
     ),
     _TELL_RES = tuple(
         (p, re.compile("(?<![\\w-])" + re.escape(p).replace("'", "['’]") + "(?![\\w-])"))
         for p in AI_TELLS,
     ),
     _NOT_ONLY_BUT_RE = re.compile("(?i)\\bnot (?:only|just|merely) [^.?!\\n]{1,60}?\\bbut\\b"),
     _GREETING_RE = re.compile(
         "(?i)^(?:hi|hey|hello|dear|good (?:morning|afternoon))\\b[^\\n]{0,40}$|^\\w[\\w .'-]{0,30},$",
     ),
     _SELF_OPENING_RE = re.compile("(?i)^(?:i|we|i'm|we're|i've|we've|i'd|we'd|my|our)\\b"),
     _TIDY = str.maketrans("‘’‚‛′“”„″    ", "'''''\"\"\"\"    ", "​⁠﻿"),
     _SIGN_OFF_RE = re.compile(
         "(?i)^(?:best|best wishes|thanks|thank you|thanks again|many thanks|cheers|regards|best regards|kind regards|warm regards|warmly|talk soon|speak soon|all the best|sincerely|take care)[,.]?$",
     );
def max_words(step: int) -> int;
def tidy(text: str) -> str;

def words(text: str) -> int;
def style_problems(
    subject: str,
    body: str,
    *,
    kind: str = "cold",
    step: int = 1,
    names: any = (),
    shape: bool = True,
) -> list[str];
def with_sign_off(body: str, name: str) -> str;

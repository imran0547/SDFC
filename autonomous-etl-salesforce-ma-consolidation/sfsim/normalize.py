"""Field-level normalisation used by transformation and matching."""
import re
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

LEGAL = {"inc", "incorporated", "llc", "ltd", "corp", "corporation", "co", "group", "plc"}
# Standard nickname table (excerpt of common US English hypocorisms).
NICK_TO_FORMAL = {"bob": "robert", "bill": "william", "liz": "elizabeth", "jim": "james",
                  "mike": "michael", "jen": "jennifer", "chris": "christopher",
                  "kate": "katherine", "rick": "richard", "tom": "thomas", "dan": "daniel",
                  "matt": "matthew", "joe": "joseph", "tony": "anthony", "pat": "patricia",
                  "maggie": "margaret", "steve": "steven", "andy": "andrew",
                  "jess": "jessica", "nick": "nicholas"}
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_PUNCT = re.compile(r"[^a-z0-9 ]+")
_WS = re.compile(r"\s+")


def company(s):
    if not s:
        return None
    t = s.lower().replace("&", " and ")
    t = _PUNCT.sub(" ", t)
    toks = [w for w in _WS.split(t.strip()) if w and w not in LEGAL]
    return " ".join(toks) or None


def person(s):
    if not s:
        return None
    t = _PUNCT.sub("", s.lower().strip())
    return t or None


def first_name(s):
    p = person(s)
    return NICK_TO_FORMAL.get(p, p) if p else None


def phone(s):
    if not s:
        return None
    d = re.sub(r"\D", "", str(s))
    return d[-10:] if len(d) >= 10 else None


def domain(s):
    if not s:
        return None
    t = s.lower().strip()
    for p in ("https://", "http://"):
        if t.startswith(p):
            t = t[len(p):]
    if t.startswith("www."):
        t = t[4:]
    return t.rstrip("/") or None


def email(s):
    if not s:
        return None, True
    t = s.strip().lower()
    return t, bool(EMAIL_RE.match(t))


def parse_datetime(value, fmt, tz=None):
    if value in (None, ""):
        return None
    try:
        if fmt == "iso_utc":
            dt = datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        else:
            dt = datetime.strptime(value, fmt).replace(tzinfo=ZoneInfo(tz))
        return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    except (ValueError, TypeError):
        return "INVALID"


def parse_date(value, fmt):
    if value in (None, ""):
        return None
    try:
        return datetime.strptime(value, fmt).date().isoformat()
    except (ValueError, TypeError):
        return "INVALID"

"""Convert paper.md (the manuscript source) to a LaTeX body with IEEE numeric citations."""
import re, sys

SRC = sys.argv[1]
OUT = sys.argv[2]
FIGDIR = sys.argv[3] if len(sys.argv) > 3 else "figures/"

KEYS = {
    ("Alharthi", "2017"): "alharthi2017", ("Batini", "2009"): "batini2009", ("Breck", "2019"): "breck2019",
    ("Christen", "2012a"): "christen2012book", ("Christen", "2012b"): "christen2012survey",
    ("Christophides", "2020"): "christophides2020", ("Dong", "2015"): "dong2015",
    ("Elmagarmid", "2007"): "elmagarmid2007", ("Fellegi", "1969"): "fellegi1969",
    ("Gruenheid", "2014"): "gruenheid2014", ("Hevner", "2004"): "hevner2004", ("Inoubli", "2018"): "inoubli2018",
    ("Jitterbit", "2026"): "jitterbit2026", ("Khan", "2013"): "khan2013", ("Kimball", "2004"): "kimball2004",
    ("Kleppmann", "2017"): "kleppmann2017", ("Köpcke", "2010"): "kopcke2010", ("Loshin", "2009"): "loshin2009",
    ("Mudgal", "2018"): "mudgal2018", ("Papadakis", "2020"): "papadakis2020", ("Peffers", "2007"): "peffers2007",
    ("Rahm", "2001"): "rahm2001", ("Rahm", "2000"): "rahm2000", ("Roh", "2021"): "roh2021",
    ("Saggi", "2018"): "saggi2018", ("Salesforce", "2026a"): "salesforce2026cdc",
    ("Salesforce", "2026b"): "salesforce2026bulk", ("Schelter", "2018"): "schelter2018",
    ("Simitsis", "2005"): "simitsis2005", ("Singh", "2015"): "singh2015", ("Vassiliadis", "2009"): "vassiliadis2009",
    ("Wang", "1996"): "wang1996", ("Winkler", "1990"): "winkler1990",
}
used = set()


def key_for(names, year):
    k = KEYS.get((names.split()[0].strip(","), year))
    if k is None:
        raise SystemExit(f"Unresolved citation: {names} {year}")
    used.add(k)
    return k


ITEM = re.compile(r"^(?:e\.g\.,\s*)?([A-ZÖ][^,;()]*?),\s*(\d{4}[ab]?)$")


def cite_paren(m):
    items = [x.strip() for x in m.group(1).split(";")]
    keys = []
    for it in items:
        mm = ITEM.match(it)
        if not mm:
            return m.group(0)
        keys.append(key_for(mm.group(1), mm.group(2)))
    return "~@@CITE{" + ",".join(keys) + "}@@"


NARR = re.compile(r"([A-ZÖ][\wö]+(?: et al\.| and [A-ZÖ][\wö]+)?) \((\d{4}[ab]?)\)")


def cite_narr(m):
    return m.group(1) + "~@@CITE{" + key_for(m.group(1), m.group(2)) + "}@@"


def esc(t):
    t = t.replace("\\", "\\textbackslash{}")
    for a, b in (("&", "\\&"), ("%", "\\%"), ("$", "\\$"), ("#", "\\#"), ("_", "\\_")):
        t = t.replace(a, b)
    t = re.sub(r'"([^"]*)"', r"``\1''", t)
    rep = {"±": "$\\pm$", "×": "$\\times$", "τ": "$\\tau$", "≥": "$\\geq$", "—": "---", "–": "--",
           "·": "\\textperiodcentered{}", "→": "$\\rightarrow$"}
    for a, b in rep.items():
        t = t.replace(a, b)
    return t


def inline(t):
    t = re.sub(r"\(([^()]*\d{4}[ab]?)\)", cite_paren, t)
    t = NARR.sub(cite_narr, t)
    # cross references
    t = re.sub(r"\bSections? (\d+(?:\.\d+)?)", lambda m: "Section~@@REF{sec:" + m.group(1) + "}@@", t)
    t = re.sub(r"\bTable (\d+)", lambda m: "Table~@@REF{tab:" + m.group(1) + "}@@", t)
    t = re.sub(r"\bFigure (\d+)", lambda m: "Fig.~@@REF{fig:" + m.group(1) + "}@@", t)
    t = re.sub(r"\*([^*]+)\*", r"@@EMPH{\1}@@", t)
    t = esc(t)
    t = re.sub(r"@@CITE\{([^}]*)\}@@", r"\\cite{\1}", t)
    t = re.sub(r"@@REF\{([^}]*)\}@@", r"\\ref{\1}", t)
    t = re.sub(r"@@EMPH\{([^}]*)\}@@", r"\\emph{\1}", t)
    t = t.replace("~\\cite", "~\\cite").replace(" ~\\cite", "~\\cite")
    return t


def table(cap, rows):
    m = re.match(r"Table (\d+)\.\s*(.*)", cap)
    num, title = m.group(1), m.group(2)
    cells = [[c.strip() for c in r.strip().strip("|").split("|")] for r in rows]
    n = len(cells[0])
    lens = [max(len(r[i]) for r in cells) for i in range(n)]
    wide = sum(lens) > 60
    total = 0.97 if wide else 0.95
    width = "\\textwidth" if wide else "\\columnwidth"
    pad = 2 * n * 0.012
    raw = [min(max(l, 16), 70) for l in lens]
    w = [(total - pad) * l / sum(raw) for l in raw]
    spec = "".join(f">{{\\raggedright\\arraybackslash\\hspace{{0pt}}}}p{{{x:.3f}{width}}}" for x in w)
    env = "table*" if wide else "table"
    out = [f"\\begin{{{env}}}[!t]", "\\centering", f"\\caption{{{inline(title)}}}", f"\\label{{tab:{num}}}",
           "\\setlength{\\tabcolsep}{4pt}", "\\renewcommand{\\arraystretch}{1.15}", "\\footnotesize",
           f"\\begin{{tabular}}{{{spec}}}", "\\hline"]
    for i, r in enumerate(cells):
        cs = [inline(c) for c in r]
        if i == 0:
            cs = ["\\textbf{" + c + "}" for c in cs]
        out.append(" & ".join(cs) + " \\\\")
        if i == 0:
            out.append("\\hline")
    out += ["\\hline", "\\end{tabular}", f"\\end{{{env}}}", ""]
    return "\n".join(out)


WIDE_FIGS = {"1", "3"}  # architecture and two-panel sweep span both columns; others by caption number


def figure(path, cap):
    m = re.match(r"Figure (\d+)\.\s*(.*)", cap)
    num, title = m.group(1), m.group(2)
    fname = path.split("/")[-1]
    wide = num in ("1", "2")  # Fig.1 architecture, Fig.2 threshold sweep (two panels)
    env = "figure*" if wide else "figure"
    width = "\\textwidth" if wide else "\\columnwidth"
    return "\n".join([f"\\begin{{{env}}}[!t]", "\\centering", f"\\includegraphics[width=0.98{width}]{{{FIGDIR}{fname}}}",
                      f"\\caption{{{inline(title)}}}", f"\\label{{fig:{num}}}", f"\\end{{{env}}}", ""])


lines = open(SRC, encoding="utf8").read().split("\n")
out = []
i = 0
in_list = False
started = False
while i < len(lines):
    ln = lines[i]
    if ln.startswith("# Declarations"):
        break
    if ln.startswith("# 1."):
        started = True
    if not started:
        i += 1
        continue
    if in_list and not ln.startswith("- "):
        out.append("\\end{itemize}")
        in_list = False
    if not ln.strip():
        out.append("")
    elif ln.startswith("# "):
        m = re.match(r"# (\d+)\.\s*(.*)", ln)
        out.append(f"\\section{{{esc(m.group(2))}}}\\label{{sec:{m.group(1)}}}")
    elif ln.startswith("## "):
        m = re.match(r"## (\d+\.\d+)\s*(.*)", ln)
        out.append(f"\\subsection{{{esc(m.group(2))}}}\\label{{sec:{m.group(1)}}}")
    elif ln.startswith("TABLE: "):
        cap = ln[7:]
        rows = []
        i += 1
        while i < len(lines) and lines[i].startswith("|"):
            rows.append(lines[i])
            i += 1
        out.append(table(cap, rows))
        continue
    elif ln.startswith("FIGURE: "):
        p, cap = ln[8:].split(" | ")
        out.append(figure(p.strip(), cap.strip()))
    elif ln.startswith("- "):
        if not in_list:
            out.append("\\begin{itemize}")
            in_list = True
        out.append("\\item " + inline(ln[2:]))
    else:
        out.append(inline(ln))
    i += 1

body = "\n".join(out)
# drop-cap style first paragraph for IEEE is optional; keep plain text.
open(OUT, "w", encoding="utf8").write(body)
missing = set(KEYS.values()) - used
print("citations used:", len(used), "unused bib entries:", sorted(missing))

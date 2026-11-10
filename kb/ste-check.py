#!/usr/bin/env python3
"""ste-check — check vault notes against the writing standard.

Portable copy of the checker used in the source team's vault. Changes from the original:
  - The vault root is found, not fixed: --vault DIR, else the nearest parent folder that holds
    0-Meta/ or .obsidian/, else the current folder.
  - The vocabulary block is optional. If 0-Meta/glossary.md has no `ste-rules` block, the
    built-in filler, modal and replacement rules apply and no term is forbidden.
  - --mode MODE forces one mode for every file (for files outside a vault).
  - The fifth (reference) layer and the team-specific record paths are removed. Any file named
    session-YYYY-MM-DD*.md counts as a record.
  The rules themselves (word limits, filler, modals, semicolons, passive voice, records and
  history sections not checked) are unchanged.

The rules are in 0-Meta/writing-standard.md. The vocabulary is in the `ste-rules` block of
0-Meta/glossary.md. The mode comes from the top-level folder of each note:

  technical     3-Technical/ and AGENTS.md   strict STE (20 words per step, 25 per sentence)
  architecture  2-Architecture/              STE writing rules (25 words per sentence)
  meta          0-Meta/, other root files    long sentences as warnings
  executive     1-Executive/                 very long sentences as warnings

Records are not checked: 3-Technical/journal/, log.md, session-YYYY-MM-DD*.md files, and
sections whose heading is a date or says history, changelog or change log.

Usage:  ste-check.py [--summary] [--errors-only] [--vault DIR] [--mode MODE] [PATH ...]
        (default PATH: the whole vault)
Exit:   1 if there is an error, else 0. Standard library only.
"""
import os
import re
import sys

VAULT = None
FORCE_MODE = None
DEFAULT_RULES = {
    "forbidden": [],
    "filler": ["basically", "simply", "just", "obviously", "actually", "really", "quite", "very"],
    "modal": ["should", "might", "may"],
    "replace": [
        {"pattern": r"\bset ?up\b(?! *[:=])", "use": "install, configure"},
        {"pattern": r"\bspin(?:s|ning)? up\b", "use": "start"},
        {"pattern": r"\bmake sure\b|\bensure\b", "use": "verify that, do a check"},
        {"pattern": r"\bin order to\b", "use": "to"},
        {"pattern": r"\butili[sz]e\b|\bleverage\b", "use": "use"},
    ],
}


def find_vault(start):
    d = os.path.abspath(start if os.path.isdir(start) else os.path.dirname(start))
    while True:
        if os.path.isdir(os.path.join(d, "0-Meta")) or os.path.isdir(os.path.join(d, ".obsidian")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return os.getcwd()
        d = parent
SKIP_DIRS = {".git", ".obsidian", ".trash", "_templates", "_tools"}
RECORD_PATH = re.compile(r"(^3-Technical/journal/|^log\.md$|(^|/)session-\d{4}-\d{2}-\d{2}[^/]*\.md$)")
NO_VOCAB = {"0-Meta/glossary.md", "0-Meta/writing-standard.md"}
HISTORY_HEADING = re.compile(r"(history|change ?log|changelog|session log|^\d{4}-\d{2}(-\d{2})?\b)", re.I)

FENCE = re.compile(r"^(\s*)(```|~~~)")
INLINE = re.compile(r"`[^`\n]*`")
# LaTeX (Obsidian renders it with MathJax): a formula is not prose. A line that is only `$$`
# opens or closes a formula block; `$$ ... $$` on one line and inline `$...$` count as one token.
MATH_FENCE = re.compile(r"^\s*\$\$\s*$")
MATH_LINE = re.compile(r"^\s*\$\$.*\$\$\s*$")
INLINE_MATH = re.compile(r"\$[^$\n]+?\$")
WIKI = re.compile(r"!?\[\[([^\]|#]*)(?:#[^\]|]*)?(?:\|([^\]]*))?\]\]")
MDLINK = re.compile(r"!?\[([^\]]*)\]\([^)]*\)")
URL = re.compile(r"https?://\S+")
COMMENT = re.compile(r"<!--.*?-->|%%.*?%%", re.S)
SENT_SPLIT = re.compile(r"(?<=[.!?])\s+(?=[A-Za-z0-9*\[(\"'])")
WORD = re.compile(r"[A-Za-z0-9][A-Za-z0-9'’/+.-]*")
PASSIVE = re.compile(r"\b(is|are|was|were|be|been|being)\s+(\w+ed|built|done|made|run|set|kept|shown|known|given|taken|written|sent|held|found|seen|put)\b", re.I)


def load_rules():
    """Parse the `ste-rules` block in the glossary without a YAML library. Fall back to defaults."""
    import copy
    path = os.path.join(VAULT, "0-Meta", "glossary.md")
    text = open(path, encoding="utf-8").read() if os.path.isfile(path) else ""
    m = re.search(r"```yaml ste-rules\n(.*?)```", text, re.S)
    if not m:
        rules = copy.deepcopy(DEFAULT_RULES)
    else:
        rules = {"forbidden": [], "filler": [], "modal": [], "replace": []}
        section = None
        for line in m.group(1).splitlines():
            if re.match(r"^\w+:\s*$", line):
                section = line.strip()[:-1]
                continue
            item = line.strip()
            if not item.startswith("- ") or section not in rules:
                continue
            item = item[2:].strip()
            if item.startswith("{"):
                entry = {}
                for k, v in re.findall(r"(\w+):\s*('(?:[^']|'')*'|[^,}]+)", item):
                    v = v.strip()
                    entry[k] = v[1:-1].replace("''", "'") if v.startswith("'") else v
                rules[section].append(entry)
            else:
                rules[section].append(item)
    for r in rules["forbidden"] + rules["replace"]:
        flags = 0 if r.get("case") == "sensitive" else re.I
        r["re"] = re.compile(r["pattern"], flags)
    rules["filler_re"] = re.compile(r"\b(" + "|".join(map(re.escape, rules["filler"])) + r")\b", re.I)
    rules["modal_re"] = re.compile(r"\b(" + "|".join(map(re.escape, rules["modal"])) + r")\b", re.I)
    return rules


def mode_of(rel):
    if FORCE_MODE:
        return FORCE_MODE
    if rel == "AGENTS.md" or rel.startswith("3-Technical/"):
        return "technical"
    if rel.startswith("2-Architecture/"):
        return "architecture"
    if rel.startswith("1-Executive/"):
        return "executive"
    return "meta"


def plain(s):
    s = INLINE.sub(" CODE ", s)
    s = INLINE_MATH.sub(" MATH ", s)
    s = WIKI.sub(lambda m: m.group(2) or os.path.basename(m.group(1) or "link"), s)
    s = MDLINK.sub(lambda m: m.group(1), s)
    s = URL.sub(" URL ", s)
    return s


def units(lines):
    """Yield (line_no, kind, text). kind: frontmatter, heading, table, step, item, prose."""
    i, n = 0, len(lines)
    if n and lines[0].strip() == "---":
        j = 1
        while j < n and lines[j].strip() != "---":
            yield j + 1, "frontmatter", lines[j]
            j += 1
        i = j + 1
    in_fence, in_math, skip_level, para, para_start = False, False, None, [], 0

    def flush():
        nonlocal para
        if para:
            yield para_start, "prose", " ".join(para)
            para = []

    while i < n:
        raw = lines[i]
        line = raw.rstrip("\n")
        if FENCE.match(line) and not in_math:
            yield from flush()
            in_fence = not in_fence
            i += 1
            continue
        if not in_fence and MATH_FENCE.match(line):
            yield from flush()
            in_math = not in_math
            i += 1
            continue
        if not in_fence and not in_math and MATH_LINE.match(line):
            yield from flush()
            i += 1
            continue
        if in_fence or in_math:
            i += 1
            continue
        h = re.match(r"^(#{1,6})\s+(.*)", line)
        if h:
            yield from flush()
            level = len(h.group(1))
            if skip_level is not None and level <= skip_level:
                skip_level = None
            if skip_level is None and HISTORY_HEADING.search(h.group(2)):
                skip_level = level
            if skip_level is None or level == skip_level:
                yield i + 1, "heading", h.group(2)
            i += 1
            continue
        if skip_level is not None:
            i += 1
            continue
        body = re.sub(r"^\s*>\s?(\[![^\]]*\][+-]?\s*)?", "", line)
        if body.strip().startswith("|"):
            yield from flush()
            yield i + 1, "table", body
        elif re.match(r"^\s*\d+[.)]\s+", body):
            yield from flush()
            yield i + 1, "step", re.sub(r"^\s*\d+[.)]\s+", "", body)
        elif re.match(r"^\s*[-*+]\s+", body):
            yield from flush()
            yield i + 1, "item", re.sub(r"^\s*[-*+]\s+(\[.\]\s+)?", "", body)
        elif not body.strip():
            yield from flush()
        else:
            if not para:
                para_start = i + 1
            para.append(body.strip())
        i += 1
    yield from flush()


def check_file(path, rules, out):
    rel = os.path.relpath(path, VAULT).replace(os.sep, "/")
    if RECORD_PATH.search(rel):
        return
    mode = mode_of(rel)
    text = COMMENT.sub(lambda m: "\n" * m.group(0).count("\n"), open(path, encoding="utf-8").read())
    lines = text.split("\n")
    is_drawing = rel.endswith(".excalidraw.md")
    vocab = rel not in NO_VOCAB

    def emit(ln, sev, msg):
        out.append((rel, ln, sev, msg))

    for ln, kind, t in units(lines):
        if is_drawing and kind != "frontmatter":
            continue
        if kind == "frontmatter":
            if vocab and re.match(r"^\s*(tags|aliases)\s*:|^\s*-\s+", t):
                for r in rules["forbidden"]:
                    if r.get("tags") and r["re"].search(t):
                        emit(ln, "error", f"tag/alias: '{r['re'].search(t).group(0)}' is forbidden, use '{r['use']}'")
            continue
        p = plain(t)
        if vocab:
            for r in rules["forbidden"]:
                m = r["re"].search(p)
                if m:
                    emit(ln, r.get("severity", "error"), f"'{m.group(0)}' is forbidden, use {r['use']}")
        if kind in ("heading", "table"):
            continue
        strict = mode in ("technical", "architecture")
        if strict:
            m = rules["filler_re"].search(p)
            if m:
                emit(ln, "error", f"filler word '{m.group(1)}'")
            m = rules["modal_re"].search(p)
            if m:
                emit(ln, "error" if mode == "technical" else "warning",
                     f"'{m.group(1)}': use 'must' or 'can'")
            if ";" in p:
                emit(ln, "error", "semicolon: write two sentences or a list")
            for r in rules["replace"]:
                m = r["re"].search(p)
                if m:
                    emit(ln, "warning", f"'{m.group(0)}': use {r['use']}")
            if PASSIVE.search(p):
                emit(ln, "warning", f"passive voice? '{PASSIVE.search(p).group(0)}'")
        for s in (x for part in re.split(r"\s+·\s+", p) for x in SENT_SPLIT.split(part)):
            w = len(WORD.findall(s))
            if mode == "technical":
                limit, sev = (20 if kind == "step" else 25), "error"
            elif mode == "architecture":
                limit, sev = 25, "error"
            elif mode == "meta":
                limit, sev = 25, "warning"
            else:
                limit, sev = 30, "warning"
            if w > limit:
                emit(ln, sev, f"sentence has {w} words (max {limit}): '{s[:70]}...'")


def main(argv):
    global VAULT, FORCE_MODE
    summary = "--summary" in argv
    errors_only = "--errors-only" in argv
    args, paths, i = list(argv), [], 0
    while i < len(args):
        a = args[i]
        if a in ("--vault", "--mode"):
            if i + 1 >= len(args):
                sys.exit(f"ste-check: {a} needs a value")
            if a == "--vault":
                VAULT = os.path.abspath(args[i + 1])
            else:
                FORCE_MODE = args[i + 1]
                if FORCE_MODE not in ("technical", "architecture", "meta", "executive"):
                    sys.exit("ste-check: --mode is technical, architecture, meta or executive")
            i += 2
            continue
        if not a.startswith("--"):
            paths.append(a)
        i += 1
    if VAULT is None:
        VAULT = find_vault(paths[0] if paths else os.getcwd())
    paths = paths or [VAULT]
    rules = load_rules()
    files = []
    for p in paths:
        p = os.path.abspath(p)
        if os.path.isdir(p):
            for d, ds, fs in os.walk(p):
                ds[:] = sorted(x for x in ds if x not in SKIP_DIRS)
                files += [os.path.join(d, f) for f in sorted(fs) if f.endswith(".md")]
        elif p.endswith(".md"):
            files.append(p)
    out = []
    for f in files:
        check_file(f, rules, out)
    errs = sum(1 for o in out if o[2] == "error")
    if summary:
        per = {}
        for rel, _, sev, _ in out:
            e, w = per.get(rel, (0, 0))
            per[rel] = (e + (sev == "error"), w + (sev == "warning"))
        for rel, (e, w) in sorted(per.items(), key=lambda x: -x[1][0]):
            if e or not errors_only:
                print(f"{e:4} errors {w:4} warnings  {rel}")
    else:
        for rel, ln, sev, msg in out:
            if sev == "error" or not errors_only:
                print(f"{rel}:{ln}: {sev}: {msg}")
    print(f"ste-check: {len(files)} notes, {errs} errors, {len(out) - errs} warnings", file=sys.stderr)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

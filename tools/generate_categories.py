#!/usr/bin/env python3
"""Generate categories.json for BrewBrowser.

Maps Homebrew formulae/casks to Debian/Ubuntu package "Sections" (the closest
thing the Linux world has to subject categories), with a keyword-heuristic
fallback for packages that don't match by name.

The output is a single JSON file meant to be:
  1. bundled in the app as an offline default, and
  2. hosted on GitHub (raw URL) so categories can be refreshed without an app
     release. BrewBrowser fetches the hosted copy at launch (ETag-cached) and
     falls back to the bundled copy.

Usage:
    python3 tools/generate_categories.py --out categories.json
    python3 tools/generate_categories.py --out categories.json --cache /tmp/bb-cache

No third-party dependencies (urllib + gzip + json from the stdlib).
"""

from __future__ import annotations

import argparse
import datetime
import gzip
import json
import os
import re
import sys
import urllib.request

# --- Sources -----------------------------------------------------------------
# (label, url) — loaded in priority order; the first archive to define a name
# wins, so Debian main is the most authoritative.
BREW_FORMULA_URL = "https://formulae.brew.sh/api/formula.json"
BREW_CASK_URL = "https://formulae.brew.sh/api/cask.json"

DEBIAN_SUITE = "stable"   # currently trixie
UBUNTU_SUITE = "noble"    # 24.04 LTS

PACKAGE_INDEXES = [
    ("debian", f"http://deb.debian.org/debian/dists/{DEBIAN_SUITE}/main/binary-amd64/Packages.gz"),
    ("debian", f"http://deb.debian.org/debian/dists/{DEBIAN_SUITE}/contrib/binary-amd64/Packages.gz"),
    ("debian", f"http://deb.debian.org/debian/dists/{DEBIAN_SUITE}/non-free/binary-amd64/Packages.gz"),
    ("debian", f"http://deb.debian.org/debian/dists/{DEBIAN_SUITE}/non-free-firmware/binary-amd64/Packages.gz"),
    ("ubuntu", f"http://archive.ubuntu.com/ubuntu/dists/{UBUNTU_SUITE}/main/binary-amd64/Packages.gz"),
    ("ubuntu", f"http://archive.ubuntu.com/ubuntu/dists/{UBUNTU_SUITE}/universe/binary-amd64/Packages.gz"),
    ("ubuntu", f"http://archive.ubuntu.com/ubuntu/dists/{UBUNTU_SUITE}/multiverse/binary-amd64/Packages.gz"),
]

# Friendly display names for the Debian section taxonomy.
SECTION_DISPLAY = {
    "admin": "System Administration", "cli-mono": "Mono/CLI", "comm": "Communication",
    "database": "Databases", "debug": "Debugging", "devel": "Development",
    "doc": "Documentation", "editors": "Editors", "education": "Education",
    "electronics": "Electronics", "embedded": "Embedded", "fonts": "Fonts",
    "games": "Games", "gnome": "GNOME", "gnu-r": "GNU R", "gnustep": "GNUstep",
    "golang": "Go", "graphics": "Graphics", "hamradio": "Ham Radio",
    "haskell": "Haskell", "httpd": "Web Servers", "interpreters": "Interpreters",
    "introspection": "Introspection", "java": "Java", "javascript": "JavaScript",
    "kde": "KDE", "kernel": "Kernel", "libdevel": "Library Development",
    "libs": "Libraries", "lisp": "Lisp", "localization": "Localization",
    "mail": "Mail", "math": "Mathematics", "metapackages": "Meta-packages",
    "misc": "Miscellaneous", "net": "Networking", "news": "Usenet News",
    "ocaml": "OCaml", "oldlibs": "Old Libraries", "otherosfs": "Other OS Filesystems",
    "perl": "Perl", "php": "PHP", "python": "Python", "ruby": "Ruby", "rust": "Rust",
    "science": "Science", "shells": "Shells", "sound": "Sound", "tasks": "Tasks",
    "tex": "TeX", "text": "Text Processing", "utils": "Utilities", "vcs": "Version Control",
    "video": "Video", "web": "Web", "x11": "X Window System", "xfce": "Xfce", "zope": "Zope",
}

# Keyword heuristic, ordered: first matching pattern in a package's description
# wins. Patterns are matched case-insensitively as whole-ish words.
HEURISTIC = [
    (r"\bcompiler|build system|build tool|debugger|linker|toolchain\b", "devel"),
    (r"\bversion control|\bgit\b|\bmercurial|subversion\b", "vcs"),
    (r"\bdatabase|\bsql\b|key-value store|datastore\b", "database"),
    (r"\bvideo|codec|ffmpeg|transcod|streaming\b", "video"),
    (r"\baudio|\bsound\b|music|\bmp3\b|synthesizer\b", "sound"),
    (r"\bfont\b|typeface\b", "fonts"),
    (r"\bgame\b|gaming|emulator\b", "games"),
    (r"\bbrowser|\bhtml\b|\bcss\b|\bweb\b", "web"),
    (r"\bimage|graphics|\bphoto|\bpng\b|\bjpeg\b|render(ing|er)\b", "graphics"),
    (r"\beditor\b|\bide\b", "editors"),
    (r"\bpython\b", "python"), (r"\bruby\b", "ruby"), (r"\bperl\b", "perl"),
    (r"\bphp\b", "php"), (r"\bnode\.?js|javascript\b", "javascript"),
    (r"\bhaskell\b", "haskell"), (r"\brust\b", "rust"),
    (r"\bgolang|\bgo programming\b", "golang"), (r"\blatex|\btex\b", "tex"),
    (r"\bmatrix|linear algebra|numeric|statistic|\bmath\b", "math"),
    (r"\bscientific|bioinformatic|physics|chemistry|astronom\b", "science"),
    (r"\bmail\b|smtp|imap|email\b", "mail"),
    (r"\bhttp\b|\bdns\b|\bproxy\b|\btcp\b|\bssh\b|\bvpn\b|network|download|\bftp\b", "net"),
    (r"\bshell\b|prompt\b", "shells"),
    (r"\bdocument|\bpdf\b|markdown|text process|parser\b", "text"),
    (r"\bcommand-line|command line|\bcli\b|terminal|utility|\butils?\b", "utils"),
    (r"\blibrary\b|\bbindings?\b", "libs"),
]
HEURISTIC = [(re.compile(p, re.I), s) for p, s in HEURISTIC]


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def fetch(url: str, cache_dir: str | None) -> bytes:
    if cache_dir:
        os.makedirs(cache_dir, exist_ok=True)
        key = re.sub(r"[^A-Za-z0-9._-]", "_", url)
        path = os.path.join(cache_dir, key)
        if os.path.exists(path):
            log(f"  cache hit: {url}")
            with open(path, "rb") as f:
                return f.read()
    log(f"  downloading: {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "BrewBrowser-categorygen/1"})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
    if cache_dir:
        with open(path, "wb") as f:
            f.write(data)
    return data


def parse_packages_index(raw_gz: bytes) -> dict[str, str]:
    """Return {package_name: section} from a Debian/Ubuntu Packages.gz."""
    text = gzip.decompress(raw_gz).decode("utf-8", "replace")
    out: dict[str, str] = {}
    pkg = None
    for line in text.splitlines():
        if line.startswith("Package: "):
            pkg = line[9:].strip()
        elif line.startswith("Section: ") and pkg:
            sec = line[9:].strip()
            sec = sec.rsplit("/", 1)[-1]  # drop component prefix e.g. universe/net
            out[pkg] = sec
            pkg = None
    return out


def build_section_map(cache_dir: str | None) -> dict[str, tuple[str, str]]:
    """name -> (section, origin). First archive to define a name wins."""
    section_map: dict[str, tuple[str, str]] = {}
    for origin, url in PACKAGE_INDEXES:
        try:
            idx = parse_packages_index(fetch(url, cache_dir))
        except Exception as e:  # noqa: BLE001 - best effort per archive
            log(f"  WARN: skipping {url}: {e}")
            continue
        added = 0
        for name, sec in idx.items():
            if name not in section_map:
                section_map[name] = (sec, origin)
                added += 1
        log(f"  {origin}: +{added} new names ({len(idx)} in index)")
    return section_map


def candidate_names(name: str, extra: list[str]) -> list[str]:
    """Normalised lookup keys to try against the Linux section map."""
    base = name.lower()
    cands = [base]
    cands += [e.lower() for e in extra]
    # strip @version (python@3.12 -> python)
    if "@" in base:
        cands.append(base.split("@", 1)[0])
    # common language aliases
    alias = {
        "python": "python3", "node": "nodejs", "go": "golang",
        "openjdk": "default-jdk", "gnu-sed": "sed", "coreutils": "coreutils",
    }
    for c in list(cands):
        if c in alias:
            cands.append(alias[c])
    # lib<->non-lib
    for c in list(cands):
        if c.startswith("lib"):
            cands.append(c[3:])
        else:
            cands.append("lib" + c)
    # try -dev/-bin/-tools suffixes (Debian dev packages carry the section too)
    for c in list(cands):
        cands += [c + "-dev", c + "-bin", c + "-tools", c + "-utils"]
    # de-dupe, keep order
    seen, ordered = set(), []
    for c in cands:
        if c and c not in seen:
            seen.add(c)
            ordered.append(c)
    return ordered


def heuristic_section(desc: str) -> str | None:
    if not desc:
        return None
    for pat, sec in HEURISTIC:
        if pat.search(desc):
            return sec
    return None


def categorize(items, name_key, desc_key, extra_fn, section_map):
    """Return ({name: {category, source}}, stats)."""
    out = {}
    stats = {"debian": 0, "ubuntu": 0, "guess": 0, "uncategorized": 0}
    for it in items:
        name = it.get(name_key)
        if not name:
            continue
        desc = it.get(desc_key) or ""
        hit = None
        for cand in candidate_names(name, extra_fn(it)):
            if cand in section_map:
                sec, origin = section_map[cand]
                hit = (sec, origin)
                break
        if hit:
            out[name] = {"category": hit[0], "source": hit[1]}
            stats[hit[1]] += 1
        else:
            sec = heuristic_section(desc)
            if sec:
                out[name] = {"category": sec, "source": "guess"}
                stats["guess"] += 1
            else:
                stats["uncategorized"] += 1  # omitted from output -> app shows Uncategorized
    return out, stats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="categories.json")
    ap.add_argument("--cache", default=None, help="dir to cache downloads")
    args = ap.parse_args()

    log("Fetching Homebrew catalog…")
    formulae = json.loads(fetch(BREW_FORMULA_URL, args.cache))
    casks = json.loads(fetch(BREW_CASK_URL, args.cache))
    log(f"  {len(formulae)} formulae, {len(casks)} casks")

    log("Building Debian/Ubuntu section map…")
    section_map = build_section_map(args.cache)
    log(f"  {len(section_map)} distinct package names mapped")

    log("Categorizing formulae…")
    f_out, f_stats = categorize(
        formulae, "name", "desc",
        lambda it: (it.get("aliases") or []) + (it.get("oldnames") or []),
        section_map)
    log("Categorizing casks…")
    c_out, c_stats = categorize(
        casks, "token", "desc",
        lambda it: it.get("name") or [],
        section_map)

    used = sorted({v["category"] for v in list(f_out.values()) + list(c_out.values())})
    categories = {k: SECTION_DISPLAY.get(k, k.title()) for k in used}

    doc = {
        "schema": 1,
        "generated": datetime.date.today().isoformat(),
        "source": f"Debian {DEBIAN_SUITE} + Ubuntu {UBUNTU_SUITE} package sections",
        "categories": categories,
        "formulae": dict(sorted(f_out.items())),
        "casks": dict(sorted(c_out.items())),
    }
    with open(args.out, "w") as f:
        json.dump(doc, f, indent=0, separators=(",", ":"), sort_keys=False)
        f.write("\n")

    def pct(n, total):
        return f"{n} ({100*n/total:.0f}%)" if total else "0"

    nf, nc = len(formulae), len(casks)
    log("\n=== Coverage ===")
    log(f"Formulae: matched debian={pct(f_stats['debian'],nf)} ubuntu={pct(f_stats['ubuntu'],nf)} "
        f"guess={pct(f_stats['guess'],nf)} uncat={pct(f_stats['uncategorized'],nf)}")
    log(f"Casks:    matched debian={pct(c_stats['debian'],nc)} ubuntu={pct(c_stats['ubuntu'],nc)} "
        f"guess={pct(c_stats['guess'],nc)} uncat={pct(c_stats['uncategorized'],nc)}")
    log(f"Categories used: {len(categories)}")
    log(f"Wrote {args.out} ({os.path.getsize(args.out)/1024:.0f} KB)")


if __name__ == "__main__":
    main()

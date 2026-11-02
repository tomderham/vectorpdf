#!/usr/bin/env python3
"""Builds VectorPDF's Apple Help book from docs/guide/*.md.

Uses only the Python standard library, plus Xcode's hiutil for the search indexes.
The converter supports just the Markdown the guide uses: headings, paragraphs, bold,
italics, inline code, links, images, bullet and numbered lists (nested by two spaces),
tables, fenced code blocks and blockquotes. A page can start with a <!-- keywords: ... --> comment,
and a heading can fix its link target with a trailing {#id}.

Each folder in docs/guide with a strings.json is a translation, built into its own .lproj. A
translated page starts with <!-- source: hash -->, the hash of the English page it was made from
(see source_hash). A page that's missing, or whose English page has since changed, is built from
the English page instead, so nobody follows outdated steps.

Tips only draws its own sidebar for Apple's online books, so the book draws one in the page and
connects it to the sidebar button in Tips' toolbar.
"""

import argparse
import hashlib
import html
import json
import plistlib
import re
import shutil
import subprocess
from pathlib import Path

ICON = "icon_256x256.png"
ENGLISH_STRINGS = {
    "book_title": "VectorPDF User Guide",
    "welcome": "Welcome",
    "search": "Search this guide",
    "no_results": "No results in this guide",
    "page_title": "{title} in VectorPDF",
}

PAGE_TEMPLATE = """<!doctype html>
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
{apple_title}<meta name="description" content="{description}">
<meta name="keywords" content="{keywords}">
<title>{title}</title>
<link rel="stylesheet" href="style.css">
</head>
<body{body_class}>
<aside id="toc"></aside>
<section>
<main>
{body}
</main>
</section>
<script src="search.js"></script>
<script src="toc.js"></script>
</body>
</html>
"""

STYLESHEET = """:root {
    color-scheme: light dark;
    --sidebar: #ececec;
    --selected: rgba(0, 0, 0, 0.11);
    --hover: rgba(0, 0, 0, 0.05);
    --link: #0066cc;
    --line: rgba(127, 127, 127, 0.3);
    --note: rgba(127, 127, 127, 0.11);
    --warning: rgba(255, 159, 10, 0.16);
    --text: #1d1d1f;
    --field: rgba(255, 255, 255, 0.75);
}
@media (prefers-color-scheme: dark) {
    :root {
        --sidebar: #2b2b2d; --selected: rgba(255, 255, 255, 0.14); --hover: rgba(255, 255, 255, 0.06);
        --link: #4da3ff; --text: #f5f5f7; --field: rgba(255, 255, 255, 0.08);
    }
}
html, body { height: 100%; margin: 0; }
body { display: flex; color: var(--text); font: 15px/1.5 -apple-system, sans-serif; }
a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }

#toc { flex: 0 0 245px; box-sizing: border-box; height: 100%; padding: 8px; overflow-y: auto;
       background: var(--sidebar); border-right: 1px solid var(--line); font-size: 14px; line-height: 1.3;
       -webkit-user-select: none; user-select: none; }
body.toc-hidden #toc { display: none; }
#toc ul { list-style: none; margin: 0; padding: 0; }
#toc a, #toc summary { display: block; position: relative; padding: 7px 10px 7px 20px; margin-bottom: 1px;
                       border-radius: 8px; color: inherit; cursor: default; }
#toc details a { padding-left: 32px; }
#toc a:hover, #toc summary:hover { background: var(--hover); text-decoration: none; }
#toc .current, #toc .current:hover { background: var(--selected); }
#toc summary { list-style: none; }
#toc summary::-webkit-details-marker { display: none; }
#toc summary::before { content: ""; position: absolute; left: 8px; top: 12px; width: 5px; height: 5px;
                       border-top: 1.5px solid; border-right: 1.5px solid; opacity: 0.6;
                       transform: rotate(45deg); transition: transform 0.12s; }
#toc details[open] > summary::before { transform: translateY(-1px) rotate(135deg); }
#guide-search { display: block; box-sizing: border-box; width: 100%; margin-bottom: 8px; padding: 5px 10px;
                border: 1px solid var(--line); border-radius: 8px; background: var(--field); color: inherit;
                font: inherit; outline: none; -webkit-appearance: none; appearance: none; }
#guide-search:focus { border-color: var(--link); }
#guide-results a { padding-left: 10px; }
#guide-results .none { padding: 7px 10px; opacity: 0.6; }
[hidden] { display: none !important; }
@media (max-width: 640px) { #toc { display: none; } }

section { flex: 1; min-width: 0; height: 100%; overflow-y: auto; box-sizing: border-box; padding: 28px 48px 64px; }
main { max-width: 680px; margin: 0 auto; }
h1 { font-size: 2.1em; line-height: 1.15; letter-spacing: -0.01em; margin: 0.4em 0 0.6em; }
h2 { font-size: 1.35em; line-height: 1.25; margin-top: 1.9em; }
h3 { font-size: 1.05em; margin-top: 1.5em; }
li { margin: 0.25em 0; }
code { font: 0.92em ui-monospace, Menlo, monospace; }
pre { padding: 10px 12px; overflow-x: auto; background: var(--note); border-radius: 8px; }
table { border-collapse: collapse; width: 100%; margin: 1em 0; }
th, td { text-align: left; vertical-align: top; padding: 6px 10px; border-bottom: 1px solid var(--line); }
img { max-width: 100%; height: auto; }
blockquote { margin: 1.2em 0; padding: 10px 14px; border-radius: 10px; background: var(--note); }
blockquote p { margin: 0; }
blockquote.warning { background: var(--warning); }

.landing h1 { font-size: 3em; margin: 0 0 0.1em; }
.landing .hero { display: flex; align-items: center; justify-content: space-between; gap: 24px;
                 padding: 16px 0 28px; margin-bottom: 8px; border-bottom: 1px solid var(--line); }
.landing .hero p { margin: 0; font-size: 1.4em; }
.landing .hero img { width: 128px; height: 128px; }
"""

# Fills in the sidebar. It's a script so that the sidebar's text isn't indexed on every page,
# which would make every page match a search for any page's title. Each page is a full load, so
# the sidebar's state is kept in session storage. Tips mixes every app's help in its own search, and
# common words can miss this guide altogether, so the sidebar has a search of its own.
TOC_SCRIPT = """document.getElementById("toc").innerHTML =
    '<input id="guide-search" type="search">' +
    '<ul id="guide-results" hidden></ul><div id="guide-contents">' + {toc} + '</div>';
document.getElementById("guide-search").placeholder = {search};
document.getElementById("guide-search").setAttribute("aria-label", {search});
var page = location.pathname.split("/").pop();
document.querySelectorAll("#toc a").forEach(function (a) {{
    if (a.getAttribute("href") !== page) return;
    a.className = "current";
    var group = a.closest("details");
    if (group) group.open = true;
}});

function load(key) {{
    try {{ return sessionStorage.getItem(key); }} catch (e) {{ return null; }}
}}
function store(key, value) {{
    try {{ sessionStorage.setItem(key, value); }} catch (e) {{}}
}}
function openGroups() {{
    try {{ return JSON.parse(load("openGroups")) || []; }} catch (e) {{ return []; }}
}}
document.querySelectorAll("#toc details").forEach(function (group) {{
    var name = group.querySelector("summary").textContent;
    if (openGroups().indexOf(name) >= 0) group.open = true;
    group.addEventListener("toggle", function () {{
        var names = openGroups().filter(function (n) {{ return n !== name; }});
        if (group.open) names.push(name);
        store("openGroups", JSON.stringify(names));
    }});
}});

function searchGuide(query) {{
    var terms = query.toLowerCase().split(/\\s+/).filter(Boolean);
    if (!terms.length) return [];
    return guidePages.map(function (p) {{
        var title = p.title.toLowerCase(), keywords = p.keywords.toLowerCase(), text = p.text.toLowerCase();
        var score = 0;
        for (var i = 0; i < terms.length; i++) {{
            var t = terms[i];
            var s = (title.indexOf(t) >= 0 ? 4 : 0) + (keywords.indexOf(t) >= 0 ? 2 : 0) + (text.indexOf(t) >= 0 ? 1 : 0);
            if (!s) return null;
            score += s;
        }}
        return {{ page: p, score: score }};
    }}).filter(Boolean).sort(function (a, b) {{ return b.score - a.score; }}).map(function (r) {{ return r.page; }});
}}

var searchField = document.getElementById("guide-search");
var results = document.getElementById("guide-results");
function showResults() {{
    var query = searchField.value.trim();
    store("guideSearch", searchField.value);
    results.hidden = !query;
    document.getElementById("guide-contents").hidden = !!query;
    results.textContent = "";
    if (!query) return;
    var found = searchGuide(query);
    found.forEach(function (p) {{
        var link = document.createElement("a");
        link.href = p.href;
        link.textContent = p.title;
        if (p.href === page) link.className = "current";
        var item = document.createElement("li");
        item.appendChild(link);
        results.appendChild(item);
    }});
    if (!found.length) {{
        var none = document.createElement("li");
        none.className = "none";
        none.textContent = {no_results};
        results.appendChild(none);
    }}
}}
searchField.addEventListener("input", showResults);
searchField.addEventListener("keydown", function (event) {{
    if (event.key !== "Escape") return;
    searchField.value = "";
    showResults();
}});
searchField.value = load("guideSearch") || "";
showResults();

var toc = document.getElementById("toc");
toc.scrollTop = Number(load("tocScroll")) || 0;
toc.addEventListener("scroll", function () {{ store("tocScroll", toc.scrollTop); }});

function setSidebarHidden(hidden) {{
    document.body.classList.toggle("toc-hidden", hidden);
    store("tocHidden", hidden ? "true" : "false");
}}
setSidebarHidden(load("tocHidden") === "true");
if ("HelpViewer" in window) {{
    window.HelpViewer.showTOCButton(true,
        function () {{ setSidebarHidden(false); }},
        function () {{ setSidebarHidden(true); }});
}}
"""


def inline(text):
    code_spans = []

    def stash_code(match):
        code_spans.append(f"<code>{html.escape(match.group(1), quote=False)}</code>")
        return f"\0{len(code_spans) - 1}\0"

    def convert_link(match):
        target = match.group(2)

        # Guide pages link to each other as .md, so they work on GitHub too
        if not re.match(r"[a-z]+:", target):
            target = re.sub(r"(?:^|(?<=/))README\.md", "index.html", target)
            target = re.sub(r"\.md(#|$)", r".html\1", target)

        return f'<a href="{html.escape(target)}">{match.group(1)}</a>'

    text = re.sub(r"`([^`]+)`", stash_code, text)
    text = html.escape(text, quote=False)
    text = re.sub(r"!\[([^\]]*)\]\(([^)\s]+)\)", r'<img alt="\1" src="\2">', text)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", convert_link, text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*([^*\s][^*]*)\*(?![\w*])", r"<em>\1</em>", text)
    return re.sub(r"\0(\d+)\0", lambda match: code_spans[int(match.group(1))], text)


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", re.sub(r"[*`]", "", text).lower()).strip("-")


HEADING_ID = r" *\{#([a-z0-9-]+)\}$"


def heading_id(text):
    match = re.search(HEADING_ID, text)
    return match.group(1) if match else slug(text)


def parse_list(lines, start, indent):
    pattern = re.compile(r"^( *)([-*]|\d+\.) +(.*)$")
    tag = "ol" if pattern.match(lines[start]).group(2)[0].isdigit() else "ul"
    output = [f"<{tag}>"]
    i = start

    while i < len(lines):
        match = pattern.match(lines[i])

        if match is None or len(match.group(1)) < indent:
            break

        if len(match.group(1)) > indent:
            nested, i = parse_list(lines, i, len(match.group(1)))
            output[-1] = output[-1].removesuffix("</li>") + "\n" + nested + "</li>"
            continue

        output.append(f"<li>{inline(match.group(3))}</li>")
        i += 1

    output.append(f"</{tag}>")
    return "\n".join(output), i


def table_cells(line):
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def convert(markdown):
    lines = markdown.splitlines()
    output = []
    i = 0

    while i < len(lines):
        line = lines[i]

        if not line.strip():
            i += 1
        elif line.startswith("```"):
            end = lines.index("```", i + 1)
            code = html.escape("\n".join(lines[i + 1:end]), quote=False)
            output.append(f"<pre><code>{code}</code></pre>")
            i = end + 1
        elif (heading := re.match(r"^(#{1,3}) +(.*)$", line)):
            level = len(heading.group(1))
            text = re.sub(HEADING_ID, "", heading.group(2))
            output.append(f'<h{level} id="{heading_id(heading.group(2))}">{inline(text)}</h{level}>')
            i += 1
        elif re.match(r"^ *([-*]|\d+\.) +", line):
            block, i = parse_list(lines, i, 0)
            output.append(block)
        elif line.startswith("> "):
            quote = []

            while i < len(lines) and lines[i].startswith("> "):
                quote.append(lines[i][2:].strip())
                i += 1

            text = " ".join(quote)
            css = ' class="warning"' if text.startswith("**Warning") else ""
            output.append(f"<blockquote{css}><p>{inline(text)}</p></blockquote>")
        elif line.startswith("|"):
            header = table_cells(line)
            i += 2
            rows = []

            while i < len(lines) and lines[i].startswith("|"):
                rows.append(table_cells(lines[i]))
                i += 1

            head = "".join(f"<th>{inline(cell)}</th>" for cell in header)
            body = "".join("<tr>" + "".join(f"<td>{inline(cell)}</td>" for cell in row) + "</tr>\n" for row in rows)
            output.append(f"<table>\n<thead><tr>{head}</tr></thead>\n<tbody>\n{body}</tbody>\n</table>")
        else:
            paragraph = []

            while i < len(lines) and lines[i].strip() and not re.match(r"^(#{1,3} |```|> |\||( *)([-*]|\d+\.) +)", lines[i]):
                paragraph.append(lines[i].strip())
                i += 1

            output.append(f"<p>{inline(' '.join(paragraph))}</p>")

    return "\n".join(output)


def toc_html(index_markdown, strings):
    """The index page's headings and links are the sidebar's groups and pages."""
    output = [f'<ul><li><a href="index.html">{html.escape(strings["welcome"])}</a></li>']
    in_group = False

    for line in index_markdown.splitlines():
        if line.startswith("## "):
            if in_group:
                output.append("</ul></details></li>")
            output.append(f"<li><details><summary>{html.escape(line[3:])}</summary><ul>")
            in_group = True
        elif (entry := re.match(r"^- \[([^\]]+)\]\(([^)]+)\.md\)", line)):
            output.append(f'<li><a href="{entry.group(2)}.html">{html.escape(entry.group(1))}</a></li>')

    return "".join(output) + "</ul></details></li></ul>"


def page_title(markdown, fallback):
    match = re.search(r"^# +(.*)$", markdown, re.MULTILINE)
    return match.group(1) if match else fallback


def split_comments(markdown):
    """A page's keywords and source hash are in comments at its top, which stay hidden on GitHub."""
    found = {"keywords": "", "source": ""}

    while (match := re.match(r"<!-- (keywords|source): (.*?) -->\n+", markdown)):
        found[match.group(1)] = match.group(2)
        markdown = markdown[match.end():]

    return found, markdown


def source_hash(markdown):
    return hashlib.sha256(split_comments(markdown)[1].encode("utf-8")).hexdigest()[:12]


def description(markdown):
    """The page's first paragraph, which Tips shows under the title in search results."""
    for line in markdown.splitlines():
        if line.strip() and not re.match(r"^(#|\||>|```|-|\*|\d+\.)", line):
            text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", line)
            return re.sub(r"[*`]", "", text)
    return ""


def search_title(title, strings):
    """Search lists every app's help together, so titles name the app, as Apple's do."""
    return title if "VectorPDF" in title else strings["page_title"].format(title=title)


def landing(markdown):
    """The index page's title and first paragraph form a hero beside the app icon."""
    title, tagline, rest = markdown.split("\n\n", 2)
    return (f'<div class="hero"><div><h1>{html.escape(title[2:])}</h1><p>{inline(tagline)}</p></div>'
            f'<img src="{ICON}" alt=""></div>\n{convert(rest)}')


def check_links(pages, name_of_guide):
    """Fails the build on a link to a page or heading that doesn't exist, or a page not in the sidebar."""
    problems = []
    anchors = {name: {heading_id(h) for h in re.findall(r"^#{1,3} +(.*)$", text, re.MULTILINE)} for name, text in pages.items()}

    for name, text in pages.items():
        for target in re.findall(r"\]\(([^)\s]+)\)", text):
            if re.match(r"[a-z]+:", target):
                continue

            page, _, fragment = target.partition("#")
            page = page or name

            if page not in pages:
                problems.append(f"{name}: no page {page}")
            elif fragment and fragment not in anchors[page]:
                problems.append(f"{name}: no heading #{fragment} in {page}")

    for name in pages:
        if name != "README.md" and f"({name})" not in pages["README.md"]:
            problems.append(f"{name}: not listed in README.md")

    if problems:
        raise SystemExit(f"error: problems in the {name_of_guide} guide:\n  " + "\n  ".join(problems))


# Bold in English, but telling the reader what to do rather than naming something on screen.
INSTRUCTIONS = {"Double-click", "Drag", "Force Click", "Triple-click"}


def protected_terms(markdown):
    """What a translation must keep as it is, so readers can find it in the English app: shortcuts,
    menu paths, and bold labels in title case, such as **Create Anchor and Open in New Window**."""
    word = r"[A-Z][A-Za-z0-9&-]*"
    name = rf"{word}(?: {word})*"
    small = r"(?:a|an|and|as|at|by|for|from|in|of|on|or|the|to|with)"
    terms = set(re.findall(r"[⌃⌥⇧⌘]+(?:[A-Za-z0-9,.+−?]|\[|\])", markdown))
    terms |= {re.sub(r"^(Choose|Click|Open) ", "", path) for path in re.findall(rf"{name}(?: > {name})+", markdown)}
    terms |= set(re.findall(rf"\*\*({word}(?: (?:{word}|{small}))*)\*\*", markdown)) - INSTRUCTIONS
    return terms


def check_translation(path, translated, english):
    missing = sorted(term for term in protected_terms(english) if term not in translated)

    if missing:
        raise SystemExit(f"error: {path} changed or dropped: " + ", ".join(missing))


def language_pages(guide_dir, translation_dir):
    """The English pages, replaced by each translated page that's still up to date."""
    pages = {path.name: path.read_text(encoding="utf-8") for path in guide_dir.glob("*.md")}

    if translation_dir is None:
        return pages

    for path in translation_dir.glob("*.md"):
        translated = path.read_text(encoding="utf-8")

        if path.name not in pages:
            raise SystemExit(f"error: {path} has no English page")
        if split_comments(translated)[0]["source"] == source_hash(pages[path.name]):
            check_translation(path, translated, pages[path.name])
            pages[path.name] = translated
        else:
            print(f"warning: {path} is out of date, using the English page")

    return pages


def build_language(guide_dir, translation_dir, pages_dir, icon):
    language = translation_dir.name if translation_dir else "en"
    strings = dict(ENGLISH_STRINGS)

    if translation_dir:
        strings.update(json.loads((translation_dir / "strings.json").read_text(encoding="utf-8")))

    pages = language_pages(guide_dir, translation_dir)
    check_links(pages, language)
    pages_dir.mkdir(parents=True)

    if translation_dir:
        with open(pages_dir / "InfoPlist.strings", "wb") as info:
            plistlib.dump({"HPDBookTitle": strings["book_title"]}, info)

    index_markdown = split_comments(pages["README.md"])[1]
    (pages_dir / "style.css").write_text(STYLESHEET, encoding="utf-8")
    (pages_dir / "toc.js").write_text(TOC_SCRIPT.format(
        toc=json.dumps(toc_html(index_markdown, strings), ensure_ascii=False),
        search=json.dumps(strings["search"], ensure_ascii=False),
        no_results=json.dumps(strings["no_results"], ensure_ascii=False)), encoding="utf-8")
    shutil.copy(icon, pages_dir / ICON)

    search_pages = []

    for name, source in sorted(pages.items()):
        comments, markdown = split_comments(source)
        title = page_title(markdown, Path(name).stem)
        is_index = name == "README.md"
        target = pages_dir / ("index.html" if is_index else Path(name).with_suffix(".html").name)

        if not is_index:
            text = html.unescape(re.sub(r"<[^>]+>", " ", convert(markdown)))
            search_pages.append({"href": target.name, "title": title, "keywords": comments["keywords"], "text": " ".join(text.split())})

        target.write_text(PAGE_TEMPLATE.format(
            lang=language,
            # The help viewer uses this tag to find the book's title page
            apple_title=f'<meta name="AppleTitle" content="{html.escape(strings["book_title"])}">\n' if is_index else "",
            description=html.escape(description(markdown)),
            keywords=html.escape(comments["keywords"]),
            title=html.escape(search_title(title, strings)),
            body_class=' class="landing"' if is_index else "",
            body=landing(markdown) if is_index else convert(markdown)), encoding="utf-8")

    (pages_dir / "search.js").write_text(f"var guidePages = {json.dumps(search_pages, ensure_ascii=False)};\n", encoding="utf-8")

    images = guide_dir / "images"

    if images.is_dir():
        shutil.copytree(images, pages_dir / "images")

    # Spotlight-format index (required since macOS 10.14), plus the older format
    locale = ["-l", language]
    subprocess.run(["hiutil", "-I", "corespotlight", "-Caf", str(pages_dir / "VectorPDF.cshelpindex"), *locale, str(pages_dir)], check=True)
    subprocess.run(["hiutil", "-I", "lsm", "-Caf", str(pages_dir / "VectorPDF.helpindex"), *locale, str(pages_dir)], check=True)


def build_book(guide_dir, resources_dir, version, bundle_id, icon):
    book = resources_dir / "VectorPDF.help"
    shutil.rmtree(book, ignore_errors=True)

    (book / "Contents" / "Resources").mkdir(parents=True)

    with open(book / "Contents" / "Info.plist", "wb") as info:
        plistlib.dump({
            "CFBundleDevelopmentRegion": "en",
            "CFBundleIdentifier": bundle_id,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": ENGLISH_STRINGS["book_title"],
            "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": version,
            "CFBundleSignature": "hbwr",
            "CFBundleVersion": version,
            "HPDBookAccessPath": "index.html",
            "HPDBookCSIndexPath": "VectorPDF.cshelpindex",
            "HPDBookIconPath": ICON,
            "HPDBookIndexPath": "VectorPDF.helpindex",
            "HPDBookTitle": ENGLISH_STRINGS["book_title"],
            "HPDBookType": "3",
        }, info)

    resources = book / "Contents" / "Resources"
    build_language(guide_dir, None, resources / "en.lproj", icon)

    for strings_file in sorted(guide_dir.glob("*/strings.json")):
        translation_dir = strings_file.parent
        build_language(guide_dir, translation_dir, resources / f"{translation_dir.name}.lproj", icon)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--guide", type=Path, required=True, help="folder containing the guide's Markdown files")
    parser.add_argument("--resources", type=Path, required=True, help="the app bundle's Resources folder")
    parser.add_argument("--version", required=True, help="VectorPDF version")
    parser.add_argument("--bundle-id", required=True, help="the help book's bundle identifier")
    parser.add_argument("--icon", type=Path, required=True, help="PNG of the app icon")
    args = parser.parse_args()

    build_book(args.guide, args.resources, args.version, args.bundle_id, args.icon)


if __name__ == "__main__":
    main()

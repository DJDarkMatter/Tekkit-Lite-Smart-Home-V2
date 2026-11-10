"""Build and check the clickable, portrait menu tree in the repository root."""

import argparse
from dataclasses import dataclass, field
from hashlib import sha256
from io import BytesIO
from itertools import combinations
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "documentation_menu_tree.md"
PDF = ROOT / "documentation_menu_tree.pdf"
REPO = "https://github.com/DJDarkMatter/Tekkit-Lite-Smart-Home-V2"
GROUPS = {
    "OS": "#11645B",
    "Automation": "#28559A",
    "ME & Machines": "#6B4690",
    "Utilities": "#954B28",
}
PAPER, INK, MUTED, RULE = "#F0F5F6", "#142A34", "#47616C", "#CFDDE0"
A3 = (841.89, 1190.55)


@dataclass
class Node:
    depth: int
    label: str
    note: str = ""
    link: str = ""
    anchor: str = ""


@dataclass
class Branch:
    group: str
    title: str
    summary: str = ""
    path: str = ""
    sources: list[str] = field(default_factory=list)
    nodes: list[Node] = field(default_factory=list)

    @property
    def key(self):
        return re.sub(r"[^a-z0-9 -]", "", self.title.lower()).replace(" ", "-")


def read_tree():
    apps = {path.name: path.read_text(encoding="utf-8") for path in ROOT.glob("apps_*.lua")}
    screensaver = apps.get("apps_screensaver.lua", "")
    catalog = re.search(r"local titles\s*=\s*\{([^}]+)\}", screensaver)
    designs = re.findall(r'"([^"]+)"', catalog[1]) if catalog else []
    branch, group, branches = None, None, []
    for line in SOURCE.read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            group = line[3:]
            if group not in GROUPS:
                raise ValueError(f"Unknown section group {group!r}")
            branch = None
        elif line.startswith("### "):
            if not group:
                raise ValueError(f"Set a section group before {line!r}")
            branch = Branch(group, line[4:])
            branches.append(branch)
        elif branch and line.strip():
            row = re.fullmatch(r"( *)- (.+)", line)
            if line.startswith("**Path** "):
                branch.path = line[9:]
            elif line.startswith("**Source** "):
                branch.sources = re.findall(r"\]\(([\w.]+)\)", line)
            elif line.strip() == "<!-- screensaver designs -->":
                if not designs or branch.title != "Screensaver":
                    raise ValueError("Cannot populate the screensaver catalog")
                branch.nodes.extend(Node(1, f"{index:02d} {name}") for index, name in enumerate(designs, 1))
            elif row:
                spaces, content = row.groups()
                depth = len(spaces) // 2
                if len(spaces) % 2 or depth > (branch.nodes[-1].depth + 1 if branch.nodes else 0):
                    raise ValueError(f"Invalid tree indentation in {line!r}")
                label, _, note = content.partition(" — ")
                anchor = re.match(r'<a name="([a-z0-9-]+)"></a> ', label)
                if anchor:
                    label = label[anchor.end():]
                link = re.fullmatch(r"\[(.+)\]\(#([a-z0-9-]+)\)", label)
                branch.nodes.append(Node(depth, link[1] if link else label, note,
                                         link[2] if link else "", anchor[1] if anchor else ""))
            elif not branch.summary:
                branch.summary = line
            else:
                raise ValueError(f"Unexpected text in {branch.title}: {line!r}")

    keys = ["hub", "full-tree"]
    covered = []
    for branch in branches:
        if not all((branch.summary, branch.path, branch.sources, branch.nodes)):
            raise ValueError(f"Incomplete branch {branch.title!r}")
        keys.extend([branch.key] + [node.anchor for node in branch.nodes if node.anchor])
        app_sources = set(branch.sources) & apps.keys()
        if branch.group == "OS":
            if app_sources:
                raise ValueError(f"Built-in branch {branch.title!r} must use its OS sources")
        else:
            if len(app_sources) != 1:
                raise ValueError(f"Link one app source in {branch.title!r}")
            filename = app_sources.pop()
            covered.append(filename)
            title = re.search(r'local app\s*=\s*\{\s*title\s*=\s*"([^"]+)"', apps[filename])
            if not title or title[1] != branch.title:
                raise ValueError(f"Update the menu tree title for {filename}")
    if sorted(covered) != sorted(apps):
        raise ValueError("Document each installed app source in exactly one branch")
    if len(keys) != len(set(keys)):
        raise ValueError("Menu tree contains duplicate anchors")
    for branch in branches:
        for node in branch.nodes:
            if node.link and node.link not in keys:
                raise ValueError(f"Unknown link #{node.link} in {branch.title} / {node.label}")
    return branches, len(apps), len(designs)


def release_and_digest(branches):
    files = {SOURCE.name, Path(__file__).name, "main_os.lua", "clients_monitor_client.lua",
             "lib_io_history.lua", "lib_me.lua", "lib_sensor_server.lua"}
    files.update(source for branch in branches for source in branch.sources)
    digest = sha256()
    for name in sorted(files):
        content = (ROOT / name).read_text(encoding="utf-8")
        digest.update(name.encode() + b"\0" + content.encode() + b"\0")
    banner = (ROOT / "main_os.lua").read_text(encoding="utf-8")
    version = re.search(r"SmartHome OS (v\d+): starting", banner)
    if not version:
        raise ValueError("Could not read the OS version from main_os.lua")
    return version[1], "menu-tree-inputs=" + digest.hexdigest()


class Page:
    """Use top-down coordinates for page layout and clickable regions."""

    def __init__(self, canvas, width, height):
        self.canvas, self.width, self.height = canvas, width, height
        canvas.setPageSize((width, height))
        self.box(0, 0, width, height, PAPER)

    def box(self, x, y, w, h, fill, border=None, radius=0):
        self.canvas.setFillColor(fill)
        if border:
            self.canvas.setStrokeColor(border)
        draw = self.canvas.roundRect if radius else self.canvas.rect
        args = [x, self.height - y - h, w, h] + ([radius] if radius else [])
        draw(*args, fill=1, stroke=bool(border))

    def line(self, x1, y1, x2, y2, color=RULE):
        self.canvas.setStrokeColor(color)
        self.canvas.line(x1, self.height - y1, x2, self.height - y2)

    def text(self, x, y, value, size=12, font="MenuSans", color=INK, align="left"):
        self.canvas.setFillColor(color)
        self.canvas.setFont(font, size)
        draw = {"left": self.canvas.drawString, "right": self.canvas.drawRightString,
                "center": self.canvas.drawCentredString}[align]
        draw(x, self.height - y, value.replace("→", "›"))

    def width_of(self, value, size, font="MenuSans"):
        return self.canvas.stringWidth(value.replace("→", "›"), font, size)

    def wrap(self, value, width, size, font="MenuSans"):
        lines = []
        for word in value.split():
            if self.width_of(word, size, font) > width:
                raise ValueError(f"Text cannot fit in the menu tree: {word!r}")
            if lines and self.width_of(lines[-1] + " " + word, size, font) <= width:
                lines[-1] += " " + word
            else:
                lines.append(word)
        return lines

    def link(self, x, y, w, h, target):
        region = (x, self.height - y - h, x + w, self.height - y)
        if target.startswith("https://"):
            self.canvas.linkURL(target, region, thickness=0)
        else:
            self.canvas.linkRect("", target, region, thickness=0)

    def bookmark(self, key, title):
        self.canvas.bookmarkPage(key)
        self.canvas.addOutlineEntry(title, key)

    def nav(self, label, target, right, top, scale=1):
        width = self.width_of(label, 12 * scale, "MenuSans-Bold") + 25 * scale
        self.box(right - width, top, width, 29 * scale, "#FFFFFF", RULE, 6 * scale)
        self.text(right - width / 2, top + 19 * scale, label, 12 * scale, "MenuSans-Bold", align="center")
        self.link(right - width, top, width, 29 * scale, target)
        return right - width - 8 * scale

    def footer(self, left, right, caption, number, scale=1):
        y = self.height - 38 * scale
        self.line(left, y, right, y)
        self.text(left, y + 17 * scale, caption, 9.5 * scale, color=MUTED)
        self.text(right, y + 17 * scale, f"MENU TREE  /  {number:02d}", 9.5 * scale,
                  "MenuSans-Bold", MUTED, "right")


def tree_rows(page, branch, width, scale=1, notes=True):
    label_size, note_size, indent = 13 * scale, 10.8 * scale, 17 * scale
    rows = []
    for node in branch.nodes:
        avail = width - node.depth * indent - 8 * scale
        font = "MenuSans-Bold" if node.depth == 0 or node.anchor else "MenuSans"
        labels = page.wrap(node.label, avail, label_size, font)
        note = " · " + node.note if notes and node.note else ""
        inline = (note and len(labels) == 1
                  and page.width_of(labels[0], label_size, font) + page.width_of(note, note_size) <= avail)
        extra = page.wrap(node.note, avail, note_size) if note and not inline else []
        height = (17.5 + (len(labels) - 1) * 14 + len(extra) * 12) * scale
        rows.append((node, font, labels, note if inline else "", extra, height))
    return rows


def draw_rows(page, branch, rows, x, y, width, scale=1, poster=False):
    accent = GROUPS[branch.group]
    parents = []
    for index, (node, font, labels, inline, extra, height) in enumerate(rows):
        baseline = y + 12 * scale
        dot_y = baseline - 4 * scale
        indent = 17 * scale
        dot_x = x + node.depth * indent
        if node.depth:
            page.line(dot_x - indent, parents[node.depth - 1], dot_x - indent, dot_y)
            page.line(dot_x - indent, dot_y, dot_x - 2 * scale, dot_y)
        parents[node.depth:] = [dot_y]
        page.box(dot_x - 1.3 * scale, dot_y - 1.3 * scale, 2.6 * scale, 2.6 * scale, accent)
        label_x = dot_x + 7 * scale
        node_key = node.anchor or f"node:{branch.key}:{index}"
        if not poster:
            page.canvas.bookmarkPage(node_key, fit="FitH", top=page.height - max(0, y - 24))
        for line in labels:
            page.text(label_x, baseline, line, 13 * scale, font, accent if node.link else INK)
            baseline += 14 * scale
        if inline:
            note_x = label_x + page.width_of(labels[0], 13 * scale, font) + 3 * scale
            page.text(note_x, baseline - 14 * scale, inline, 10.8 * scale, color=MUTED)
        for line in extra:
            page.text(label_x, baseline - 2 * scale, line, 10.8 * scale, color=MUTED)
            baseline += 12 * scale
        if node.link or poster:
            # Use only this row's region. Ancestor links never cover children.
            page.link(label_x, y, x + width - label_x, height, node.link or node_key)
        y += height


def hub(canvas, branches, version, app_count, design_count):
    page = Page(canvas, *A3)
    page.bookmark("hub", "Menu hub")
    page.box(0, 0, page.width, 8, "#11645B")
    page.nav("Full tree  ›", "full-tree", page.width - 38, 30)
    page.text(38, 54, f"NAVIGATION MAP  /  {version.upper()}", 12, "MenuSans-Bold", GROUPS["OS"])
    page.text(36, 108, "SmartHome OS menu tree", 39, "MenuSans-Bold")
    page.text(38, 139, f"{app_count} optional apps, Settings, desktop controls, alerts and shared dialogs.", 14, color=MUTED)
    page.text(38, 164, f"{len(branches)} branches  /  {sum(len(b.nodes) for b in branches)} menu entries  /  {design_count} screensavers",
              11.5, "MenuSans-Bold", MUTED)

    half = (len(branches) + 1) // 2
    spacing = min(97, 847 / half)
    card_width, top = 305, 202
    center = page.width / 2
    hub_y = top + (half - 1) * spacing / 2 + 20
    for side, column in enumerate((branches[:half], branches[half:])):
        x = 38 if side == 0 else page.width - 38 - card_width
        edge = x + card_width if side == 0 else x
        rail = edge + (13 if side == 0 else -13)
        page.line(rail, top + 32, rail, top + (len(column) - 1) * spacing + 32)
        page.line(rail, hub_y + 12, center, hub_y + 12)
        for row, branch in enumerate(column):
            y = top + row * spacing
            color = GROUPS[branch.group]
            page.line(edge, y + 32, rail, y + 32)
            page.box(x, y, card_width, spacing - 12, "#FFFFFF", RULE, 9)
            page.text(x + 14, y + 18, f"{1 + row + side * half:02d}  /  {branch.group.upper()}",
                      9, "MenuSans-Bold", color)
            page.text(x + 14, y + 39, branch.title, 17, "MenuSans-Bold")
            for i, line in enumerate(page.wrap(branch.summary, card_width - 26, 10.4)):
                page.text(x + 14, y + 55 + 12 * i, line, 10.4, color=MUTED)
            page.text(x + card_width - 14, y + 38, "›", 18, "MenuSans-Bold", color, "right")
            page.link(x, y, card_width, spacing - 12, branch.key)

    page.box(center - 62, hub_y - 14, 124, 54, INK, radius=9)
    page.text(center, hub_y + 9, "SmartHome OS", 13, "MenuSans-Bold", "#FFFFFF", "center")
    page.text(center, hub_y + 26, "Menu branches", 9.5, color="#C7DCDF", align="center")
    page.footer(38, page.width - 38, "Select a card for its branch. Use Full tree for all paths on one page.", 1)
    canvas.showPage()


def full_tree(canvas, branches, version):
    width, margin, gap, scale = 2480, 50, 36, 1.16
    card_width = (width - 2 * margin - 3 * gap) / 4
    sizing = Page(canvas, width, 1.38 * width)
    cards = [(branch, tree_rows(sizing, branch, card_width - 50, scale, notes=False)) for branch in branches]
    weights = [78 + sum(row[-1] for row in rows) for _, rows in cards]

    def score(cuts):
        edges = (0, *cuts, len(cards))
        totals = [sum(weights[start:end]) for start, end in zip(edges, edges[1:])]
        return max(totals), sum(total ** 2 for total in totals)

    cuts = min(combinations(range(1, len(cards)), 3), key=score)
    height = max(1.38 * width, 320 + score(cuts)[0] + 65)
    # The sizing page only provides font metrics. Its background is covered here.
    page = Page(canvas, width, height)
    page.bookmark("full-tree", "Full menu tree")
    page.nav("‹  Menu hub", "hub", width - margin, 30, 1.7)
    page.text(margin, 59, f"SMART HOME OS  /  {version.upper()}  /  FULL NAVIGATION MAP", 20,
              "MenuSans-Bold", GROUPS["OS"])
    page.text(margin, 133, "Menus, submenus & paths", 59, "MenuSans-Bold")
    page.text(margin, 173, "Select a heading for its branch or an entry for the corresponding detail.",
              21, color=MUTED)

    center, root_y = width / 2, 195
    page.box(center - 142, root_y, 284, 58, INK, radius=12)
    page.text(center, root_y + 37, "SmartHome OS", 25, "MenuSans-Bold", "#FFFFFF", "center")
    page.link(center - 142, root_y, 284, 58, "hub")
    page.line(center, root_y + 58, center, 278)
    page.line(margin + 7, 278, width - margin - card_width + 7, 278)

    edges = (0, *cuts, len(cards))
    for column, (start, end) in enumerate(zip(edges, edges[1:])):
        x, y = margin + column * (card_width + gap), 314
        rail = x + 7
        page.line(rail, 278, rail, y + sum(weights[start:end - 1]) + 27)
        for index in range(start, end):
            branch, rows = cards[index]
            color = GROUPS[branch.group]
            card_height = weights[index] - 17
            page.line(rail, y + 27, x + 19, y + 27)
            page.box(x + 19, y, card_width - 19, card_height, "#FFFFFF", RULE, 10)
            page.text(x + 35, y + 23, f"{index + 1:02d}  /  {branch.group.upper()}", 12, "MenuSans-Bold", color)
            page.text(x + 35, y + 47, branch.title, 24, "MenuSans-Bold")
            page.text(x + card_width - 17, y + 46, "›", 26, "MenuSans-Bold", color, "right")
            page.link(x + 19, y, card_width - 19, 55, branch.key)
            draw_rows(page, branch, rows, x + 35, y + 57, card_width - 50, scale, poster=True)
            y += weights[index]

    page.footer(margin, width - margin, "Zoom to read individual paths. Brackets mark context-dependent entries.", 2, 1.8)
    canvas.showPage()


def detail(canvas, branch, number):
    width, height = A3
    margin, body_top = 38, 184
    body_width = width - 2 * margin - 42
    sizing = Page(canvas, width, height)
    rows = tree_rows(sizing, branch, body_width)
    available = height - body_top - 102
    scale = max(.82, min(1, available / sum(row[-1] for row in rows)))
    if scale < 1:
        rows = tree_rows(sizing, branch, body_width, scale)
    body_height = sum(row[-1] for row in rows)
    height = max(height, body_top + body_height + 102)
    page = Page(canvas, width, height)
    page.bookmark(branch.key, branch.title)
    accent = GROUPS[branch.group]
    page.box(0, 0, width, 8, accent)
    right = page.nav("Full tree", "full-tree", width - margin, 28)
    page.nav("‹  Hub", "hub", right, 28)
    page.text(margin, 50, f"{number - 2:02d}  /  {branch.group.upper()}", 12, "MenuSans-Bold", accent)
    page.text(margin - 2, 99, branch.title, 39, "MenuSans-Bold")
    page.text(margin, 126, branch.summary, 13.4, color=MUTED)
    page.box(margin, 140, width - 2 * margin, 28, "#E3ECEE", radius=6)
    page.text(margin + 12, 158, branch.path, 12, "MenuSans-Bold")
    page.text(width - margin - 12, 158, f"{len(branch.nodes)} ENTRIES", 10, "MenuSans-Bold", MUTED, "right")
    page.box(margin, body_top - 5, width - 2 * margin, body_height + 13, "#FFFFFF", RULE, 9)
    draw_rows(page, branch, rows, margin + 19, body_top, body_width, scale)
    y, x = body_top + body_height + 28, margin + 54
    page.text(margin, y, "SOURCE", 9, "MenuSans-Bold", MUTED)
    for filename in branch.sources:
        span = page.width_of(filename, 9.5, "MenuSans-Bold")
        page.text(x, y, filename, 9.5, "MenuSans-Bold", accent)
        page.link(x, y - 11, span, 14, f"{REPO}/blob/main/{filename}")
        x += span + 16
    page.footer(margin, width - margin, "Brackets mark context-dependent entries. Colored labels open linked paths.", number)
    canvas.showPage()


def build_pdf(branches, version, digest, app_count, design_count):
    import reportlab
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.pdfgen.canvas import Canvas

    fonts = Path(reportlab.__file__).parent / "fonts"
    pdfmetrics.registerFont(TTFont("MenuSans", str(fonts / "Vera.ttf")))
    pdfmetrics.registerFont(TTFont("MenuSans-Bold", str(fonts / "VeraBd.ttf")))
    buffer = BytesIO()
    canvas = Canvas(buffer, invariant=1, pageCompression=1, initialFontName="MenuSans")
    canvas.setTitle(f"SmartHome OS menu tree ({version})")
    canvas.setSubject("Portrait map of desktop controls, Settings, shared dialogs and app menus")
    canvas.setAuthor("Tekkit Lite Smart Home V2")
    canvas.setKeywords(digest)
    hub(canvas, branches, version, app_count, design_count)
    full_tree(canvas, branches, version)
    for number, branch in enumerate(branches, 3):
        detail(canvas, branch, number)
    canvas.save()
    return buffer.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check the PDF against the current inputs")
    args = parser.parse_args()
    try:
        branches, app_count, design_count = read_tree()
        version, digest = release_and_digest(branches)
        if args.check:
            existing = PDF.read_bytes() if PDF.is_file() else b""
            if not existing.startswith(b"%PDF-") or not existing.rstrip().endswith(b"%%EOF") or digest.encode() not in existing:
                parser.exit(1, f"{PDF.name} is stale or missing. Review {SOURCE.name}, then run python3 {Path(__file__).name}.\n")
            print(f"{PDF.name} is current for {version}.")
        else:
            PDF.write_bytes(build_pdf(branches, version, digest, app_count, design_count))
            print(f"Built {PDF.name} for {version} with {len(branches)} branches and {app_count} apps.")
    except (OSError, ValueError) as exc:
        parser.exit(1, f"Menu tree: {exc}\n")
    except ModuleNotFoundError as exc:
        if exc.name != "reportlab":
            raise
        parser.exit(1, "Install ReportLab to build the menu tree PDF: python3 -m pip install reportlab==4.4.9\n")


if __name__ == "__main__":
    main()

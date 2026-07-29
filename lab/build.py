#!/usr/bin/env python3
"""
build.py — turn the editable Markdown lab source into the styled student HTML.

Usage:
    python3 build.py                 # lab.md  -> index.html   (in this folder)
    python3 build.py lab.md out.html # explicit input/output

Then serve it as usual:  python3 serve.py

────────────────────────────────────────────────────────────────────────────
MARKDOWN DIALECT (everything you need to edit the lab lives in lab.md)
────────────────────────────────────────────────────────────────────────────
Front matter (top of file, between --- lines): title, brand_dark, brand_wolf,
  brand_tag, header_title, header_subtitle.

Headings drive the page structure:
    #   Section        -> big badged section     {id=... badge=Setup}
    ##  Subsection     -> grouped area           {id=...}
    ### Step card      -> numbered card          {id=... icon=📦 note="— used in: ..."}

  - A section/subsection's text BEFORE its first `###` becomes the intro line.
  - Step cards auto-number 1,2,3… within their parent unless you give {icon=…}.
  - A step card shows in the sidebar only if it has an explicit {id=…};
    add {nav=false} to force-hide one.

Content (inside cards, list items, or callouts):
    ```           fenced code  -> command block
    - / 1. / a.   lists (letter markers => a,b,c sub-steps; nested by indent)
    ![alt](img "caption")      -> figure (caption optional)
    :::row ... :::             -> two figures side by side
    | a | b |     tables       -> credential table
    > [!NOTE] Title            -> green callout   (NOTE/TIP/INFO)
    > [!WARNING] Title         -> amber callout   (WARNING/CAUTION)
    `code`  **bold**  [[Ctrl+C]] (kbd)  [text](url)
    end a line with \\ for a manual line break
"""
import sys, os, re

# ───────────────────────── inline formatting ──────────────────────────────
def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

def inline(text):
    """Format one run of inline text (raw HTML is allowed through)."""
    out = []
    for part in re.split(r'(`[^`]*`)', text):
        if len(part) >= 2 and part.startswith('`') and part.endswith('`'):
            out.append('<code>' + esc(part[1:-1]) + '</code>')
        else:
            part = re.sub(r'\[\[([^\]]+)\]\]', r'<kbd>\1</kbd>', part)
            part = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', part)
            part = re.sub(r'(?<!\!)\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', part)
            out.append(part)
    return ''.join(out)

def join_para(lines):
    """Join wrapped paragraph lines; a trailing backslash => <br>."""
    parts = []
    for i, ln in enumerate(lines):
        ln = ln.rstrip()
        if ln.endswith('\\'):
            parts.append(inline(ln[:-1].rstrip()) + '<br>')
        else:
            parts.append(inline(ln.strip()) + ('' if i == len(lines) - 1 else ' '))
    return ''.join(parts)

# ───────────────────────── small line helpers ─────────────────────────────
def leading(l):
    return len(l) - len(l.lstrip(' '))

def dedent(lines):
    ind = [leading(l) for l in lines if l.strip()]
    n = min(ind) if ind else 0
    return [l[n:] if len(l) >= n else l for l in lines]

MARKER = re.compile(r'^(\s*)([-*]|\d+[.)]|[A-Za-z][.)])\s+(.*)$')
IMG    = re.compile(r'^\s*!\[([^\]]*)\]\(([^)"\s]+)(?:\s+"([^"]*)")?\)\s*$')
TSEP   = re.compile(r'^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)+\|?\s*$')

def is_table_start(lines, i):
    return ('|' in lines[i] and i + 1 < len(lines) and TSEP.match(lines[i + 1]) is not None)

def is_block_start(lines, i):
    l = lines[i]
    s = l.strip()
    if s == '':
        return True
    if MARKER.match(l) or IMG.match(l):
        return True
    if s.startswith('```') or s.startswith(':::'):
        return True
    if l.lstrip().startswith('>'):
        return True
    if is_table_start(lines, i):
        return True
    return False

# ───────────────────────── block renderer ─────────────────────────────────
def render_blocks(lines, para_class=None):
    html, i, n = [], 0, len(lines)
    while i < n:
        line = lines[i]
        if line.strip() == '':
            i += 1
            continue

        # fenced code
        if line.strip().startswith('```'):
            i += 1
            buf = []
            while i < n and not lines[i].strip().startswith('```'):
                buf.append(lines[i])
                i += 1
            i += 1  # closing fence
            body = esc('\n'.join(dedent(buf)))
            html.append('<div class="code-block"><pre>%s</pre></div>' % body)
            continue

        # :::row  (side-by-side figures)
        if line.strip().startswith(':::'):
            i += 1
            buf = []
            while i < n and not lines[i].strip().startswith(':::'):
                buf.append(lines[i])
                i += 1
            i += 1
            figs = [render_figure(m) for m in (IMG.match(b) for b in buf) if m]
            html.append('<div class="img-row">%s</div>' % ''.join(figs))
            continue

        # blockquote callout
        if line.lstrip().startswith('>'):
            buf = []
            while i < n and lines[i].lstrip().startswith('>'):
                stripped = lines[i].lstrip()[1:]
                if stripped.startswith(' '):
                    stripped = stripped[1:]
                buf.append(stripped)
                i += 1
            html.append(render_callout(buf))
            continue

        # figure
        m = IMG.match(line)
        if m:
            html.append(render_figure(m))
            i += 1
            continue

        # table
        if is_table_start(lines, i):
            buf = []
            while i < n and '|' in lines[i] and lines[i].strip():
                buf.append(lines[i])
                i += 1
            html.append(render_table(buf))
            continue

        # list
        if MARKER.match(line):
            block, i = collect_list(lines, i)
            html.append(block)
            continue

        # paragraph
        buf = [line]
        i += 1
        while i < n and not is_block_start(lines, i):
            buf.append(lines[i])
            i += 1
        cls = (' class="%s"' % para_class) if para_class else ''
        html.append('<p%s>%s</p>' % (cls, join_para(buf)))
    return ''.join(html)

def render_figure(m):
    alt, src, cap = m.group(1), m.group(2), m.group(3)
    caption = '<figcaption>%s</figcaption>' % inline(cap) if cap else ''
    return '<figure><img src="%s" alt="%s">%s</figure>' % (src, alt, caption)

def render_table(rows):
    cells = lambda r: [c.strip() for c in r.strip().strip('|').split('|')]
    head = cells(rows[0])
    body = rows[2:]
    th = ''.join('<th>%s</th>' % inline(c) for c in head)
    trs = []
    for r in body:
        tds = ''.join('<td>%s</td>' % inline(c) for c in cells(r))
        trs.append('<tr>%s</tr>' % tds)
    return ('<table class="cred-table"><thead><tr>%s</tr></thead>'
            '<tbody>%s</tbody></table>') % (th, ''.join(trs))

CALLOUT_WARN = {'WARNING', 'WARN', 'CAUTION', 'DANGER'}
def render_callout(lines):
    cls, title = 'callout', 'Note'
    body = lines
    m = re.match(r'^\[!(\w+)\]\s*(.*)$', lines[0].strip()) if lines else None
    if m:
        kind = m.group(1).upper()
        if kind in CALLOUT_WARN:
            cls = 'callout warn'
        if m.group(2).strip():
            title = m.group(2).strip()
        body = lines[1:]
    inner = render_blocks(dedent(body))
    return ('<div class="%s"><div class="callout-title">%s</div>%s</div>'
            % (cls, inline(title), inner))

def collect_list(lines, i):
    base = leading(lines[i])
    items = []
    while i < len(lines):
        m = MARKER.match(lines[i])
        if not (m and leading(lines[i]) == base):
            break
        marker, text = m.group(2), m.group(3)
        child, i = [], i + 1
        while i < len(lines) and (lines[i].strip() == '' or leading(lines[i]) > base):
            child.append(lines[i])
            i += 1
        items.append((marker, text, child))

    first = items[0][0]
    if first[0] in '-*':
        otag, ctag = '<ul>', '</ul>'
    elif first[0].isdigit():
        start = int(re.match(r'\d+', first).group())
        otag = '<ol start="%d">' % start if start != 1 else '<ol>'
        ctag = '</ol>'
    else:
        t = 'A' if first[0].isupper() else 'a'
        otag, ctag = '<ol type="%s">' % t, '</ol>'

    lis = []
    for _, text, child in items:
        inner = render_blocks(dedent(child)) if any(c.strip() for c in child) else ''
        lis.append('<li>%s%s</li>' % (inline(text), inner))
    return otag + ''.join(lis) + ctag, i

# ───────────────────────── document structure ─────────────────────────────
class Node:
    def __init__(self, title, attrs):
        self.title = title
        self.attrs = attrs
        self.intro = []       # raw lines before first child
        self.children = []    # sub-nodes
    def aid(self):
        return self.attrs.get('id')

def parse_attrs(s):
    attrs = {}
    for m in re.finditer(r'(\w+)=("([^"]*)"|(\S+))', s):
        attrs[m.group(1)] = m.group(3) if m.group(3) is not None else m.group(4)
    return attrs

def split_heading(text):
    m = re.search(r'\s*\{([^}]*)\}\s*$', text)
    if m:
        return text[:m.start()].strip(), parse_attrs(m.group(1))
    return text.strip(), {}

def split_front_matter(text):
    meta = {}
    if text.startswith('---'):
        end = text.find('\n---', 3)
        if end != -1:
            block = text[3:end]
            text = text[end + 4:]
            for ln in block.splitlines():
                if ':' in ln:
                    k, v = ln.split(':', 1)
                    meta[k.strip()] = v.strip()
    return meta, text.lstrip('\n')

def parse_document(text):
    # strip HTML comments (author notes) outside code — safe for this content
    text = re.sub(r'<!--.*?-->', '', text, flags=re.S)
    lines = text.splitlines()
    sections, sec, sub = [], None, None
    for line in lines:
        h = re.match(r'^(#{1,3})\s+(.*)$', line)
        if h:
            level = len(h.group(1))
            title, attrs = split_heading(h.group(2))
            node = Node(title, attrs)
            if level == 1:
                sections.append(node); sec, sub = node, None
            elif level == 2:
                node.kind = 'sub'; sec.children.append(node); sub = node
            else:
                node.kind = 'card'
                (sub or sec).children.append(node)
            continue
        target = None
        if sec is not None:
            cur = (sub or sec)
            # a card collects into its body; section/subsection collect intro
            if getattr(cur, 'kind', None) == 'card':
                target = cur.intro
            elif cur.children and getattr(cur.children[-1], 'kind', '') == 'card':
                target = cur.children[-1].intro
            else:
                target = cur.intro
        if target is not None:
            target.append(line)
    return sections

# ───────────────────────── HTML rendering ─────────────────────────────────
def render_card(card, number):
    icon = card.attrs.get('icon') or (str(number) if number else '')
    note = card.attrs.get('note')
    note_html = ' <span class="step-note">%s</span>' % inline(note) if note else ''
    idattr = ' id="%s"' % card.aid() if card.aid() else ''
    body = render_blocks(card.intro)
    return ('<div%s class="step-card"><div class="step-title">'
            '<span class="step-num">%s</span><h4>%s%s</h4></div>%s</div>'
            % (idattr, icon, inline(card.title), note_html, body))

def render_cards(container):
    out, counter = [], 0
    for child in container.children:
        if getattr(child, 'kind', '') != 'card':
            continue
        if 'icon' in child.attrs:
            out.append(render_card(child, None))
        else:
            counter += 1
            out.append(render_card(child, counter))
    return ''.join(out)

def render_subsection(sub):
    idattr = ' id="%s"' % sub.aid() if sub.aid() else ''
    return ('<div%s class="subsection"><h3>%s</h3>%s%s</div>'
            % (idattr, inline(sub.title),
               render_blocks(sub.intro, para_class='intro'),
               render_cards(sub)))

def render_section(sec):
    badge = sec.attrs.get('badge', sec.title)
    idattr = ' id="%s"' % sec.aid() if sec.aid() else ''
    parts = ['<section%s class="lab-section"><div class="section-heading">'
             '<span class="section-badge">%s</span><h2>%s</h2></div>%s'
             % (idattr, badge, inline(sec.title),
                render_blocks(sec.intro, para_class='section-intro'))]
    parts.append(render_cards(sec))
    for child in sec.children:
        if getattr(child, 'kind', '') == 'sub':
            parts.append(render_subsection(child))
    parts.append('</section>')
    return ''.join(parts)

def nav_link(node, cls):
    return '<a href="#%s" class="%s">%s</a>' % (node.aid(), cls, inline(node.title))

def render_nav(sections):
    out = []
    for sec in sections:
        out.append('<div class="nav-group">%s</div>' % sec.attrs.get('badge', sec.title))
        direct = [c for c in sec.children if getattr(c, 'kind', '') == 'card']
        subs   = [c for c in sec.children if getattr(c, 'kind', '') == 'sub']
        if direct:
            out.append(nav_link(sec, 'nav-main'))
            for c in direct:
                if c.aid() and c.attrs.get('nav') != 'false':
                    out.append(nav_link(c, 'nav-sub'))
        for sub in subs:
            out.append(nav_link(sub, 'nav-main'))
            for c in sub.children:
                if getattr(c, 'kind', '') == 'card' and c.aid() and c.attrs.get('nav') != 'false':
                    out.append(nav_link(c, 'nav-sub'))
    return '\n    '.join(out)

# ───────────────────────── page shell ─────────────────────────────────────
STYLE = r'''<style>
:root {
  --bg:          #0c0c0c;
  --surface:     #141414;
  --card:        #1b1b1b;
  --border:      #272727;
  --green:       #7ab526;
  --green-hi:    #9fd43a;
  --green-lo:    #2c4a0a;
  --green-bg:    rgba(122, 181, 38, 0.07);
  --text:        #dedede;
  --muted:       #6e6e6e;
  --code-bg:     #090e05;
  --warn-bg:     rgba(240, 180, 41, 0.07);
  --warn:        #f0b429;
  --sidebar-w:   268px;
  --header-h:    56px;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
html { scroll-behavior: smooth; }
body {
  background: var(--bg); color: var(--text);
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  font-size: 15px; line-height: 1.75; display: flex; min-height: 100vh;
}
::-webkit-scrollbar { width: 6px; height: 6px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: #2e2e2e; border-radius: 3px; }
::-webkit-scrollbar-thumb:hover { background: var(--green-lo); }
.sidebar {
  width: var(--sidebar-w); min-width: var(--sidebar-w);
  background: var(--surface); border-right: 1px solid var(--border);
  position: sticky; top: 0; height: 100vh; overflow-y: auto;
  display: flex; flex-direction: column; flex-shrink: 0;
}
.sidebar-brand { padding: 22px 20px 18px; border-bottom: 1px solid var(--border); }
.brand-logo { font-size: 21px; font-weight: 900; letter-spacing: 2px; line-height: 1; text-transform: uppercase; }
.brand-logo .dark { color: var(--text); }
.brand-logo .wolf { color: var(--green); }
.brand-tag { font-size: 10px; color: var(--muted); text-transform: uppercase; letter-spacing: 2px; margin-top: 5px; }
.nav { padding: 8px 0 32px; }
.nav-group { font-size: 10px; font-weight: 700; text-transform: uppercase; letter-spacing: 2.5px; color: var(--green); padding: 18px 20px 5px; }
.nav a {
  display: block; padding: 5px 20px; color: var(--muted); text-decoration: none;
  font-size: 13px; line-height: 1.4; transition: color 0.12s;
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.nav a:hover { color: var(--text); }
.nav a.active { color: var(--green); border-left: 2px solid var(--green); padding-left: 18px; }
.nav a.nav-main { font-weight: 600; color: #9a9a9a; font-size: 13px; }
.nav a.nav-main:hover { color: var(--text); }
.nav a.nav-sub { padding-left: 34px; font-size: 12px; }
.main { flex: 1; min-width: 0; padding: 0 52px 80px 52px; max-width: 940px; }
.page-header { padding: 44px 0 28px; border-bottom: 1px solid var(--border); margin-bottom: 52px; }
.page-header h1 { font-size: 26px; font-weight: 700; color: var(--text); letter-spacing: -0.3px; margin-bottom: 6px; }
.page-header .subtitle { color: var(--muted); font-size: 14px; }
.lab-section { margin-bottom: 72px; }
.section-heading { display: flex; align-items: center; gap: 14px; margin-bottom: 36px; padding-bottom: 14px; border-bottom: 2px solid var(--green-lo); }
.section-badge { background: var(--green); color: #000; font-size: 10px; font-weight: 900; letter-spacing: 2px; text-transform: uppercase; padding: 4px 12px; border-radius: 3px; }
.section-heading h2 { font-size: 22px; font-weight: 700; color: var(--green); letter-spacing: 1px; }
.section-intro { color: var(--muted); margin-bottom: 24px; font-size: 14px; }
.subsection { margin-bottom: 52px; }
.subsection > h3 { font-size: 17px; font-weight: 600; color: var(--text); margin-bottom: 10px; padding-bottom: 8px; border-bottom: 1px solid var(--border); }
.subsection > .intro { color: var(--muted); margin-bottom: 24px; font-size: 14px; }
.step-card { background: var(--card); border: 1px solid var(--border); border-left: 3px solid var(--border); border-radius: 6px; padding: 22px 26px; margin-bottom: 18px; transition: border-color 0.15s; }
.step-card:hover { border-left-color: var(--green-lo); }
.step-card:target { border-left-color: var(--green); }
.step-title { display: flex; align-items: center; gap: 13px; margin-bottom: 14px; }
.step-num { background: var(--green-lo); color: var(--green-hi); font-size: 11px; font-weight: 800; min-width: 26px; height: 26px; border-radius: 50%; display: flex; align-items: center; justify-content: center; flex-shrink: 0; letter-spacing: 0; }
.step-title h4 { font-size: 15px; font-weight: 600; color: var(--text); }
.step-note { font-weight: 400; color: var(--muted); font-size: 13px; }
.step-card p { margin-bottom: 10px; }
.step-card p:last-child { margin-bottom: 0; }
.step-card ol, .step-card ul { padding-left: 22px; margin-bottom: 12px; }
.step-card li { margin-bottom: 5px; }
.step-card li::marker { color: var(--green); }
.step-card ol[type="a"] li::marker { color: var(--green); }
code { font-family: 'Consolas', 'Monaco', 'Courier New', monospace; font-size: 13px; background: var(--code-bg); color: var(--green-hi); padding: 1px 6px; border-radius: 3px; border: 1px solid var(--green-lo); }
.code-block { background: var(--code-bg); border: 1px solid var(--green-lo); border-radius: 5px; padding: 13px 16px; margin: 10px 0 14px; overflow-x: auto; }
.code-block pre { font-family: 'Consolas', 'Monaco', 'Courier New', monospace; font-size: 13px; color: var(--green-hi); line-height: 1.55; white-space: pre; }
.code-block pre .dim { color: var(--muted); }
kbd { display: inline-block; background: #222; border: 1px solid #444; border-bottom: 2px solid #333; border-radius: 3px; font-size: 11px; font-family: 'Consolas', monospace; padding: 1px 6px; color: #ccc; }
.callout { border-left: 3px solid var(--green); background: var(--green-bg); padding: 13px 17px; border-radius: 0 5px 5px 0; margin: 14px 0; }
.callout-title { font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 1.5px; color: var(--green); margin-bottom: 6px; }
.callout p, .callout li { font-size: 14px; margin-bottom: 4px; }
.callout ul, .callout ol { padding-left: 18px; margin-top: 6px; }
.callout.warn { border-color: var(--warn); background: var(--warn-bg); }
.callout.warn .callout-title { color: var(--warn); }
.cred-table { width: 100%; border-collapse: collapse; margin: 10px 0 4px; font-size: 13px; }
.cred-table th { background: var(--green-lo); color: var(--green-hi); text-align: left; padding: 7px 14px; font-size: 11px; text-transform: uppercase; letter-spacing: 1px; }
.cred-table td { padding: 7px 14px; border-bottom: 1px solid var(--border); }
.cred-table tr:last-child td { border-bottom: none; }
figure { margin: 14px 0; }
figure img { max-width: 100%; border-radius: 5px; border: 1px solid var(--border); display: block; }
figcaption { font-size: 11px; color: var(--muted); margin-top: 5px; text-align: center; font-style: italic; }
.img-row { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin: 14px 0; }
@media (max-width: 800px) {
  .sidebar { display: none; }
  .main { padding: 0 20px 60px; }
  .img-row { grid-template-columns: 1fr; }
}
</style>'''

SCRIPT = r'''<script>
const links = document.querySelectorAll('.nav a[href^="#"]');
const targets = [];
links.forEach(a => {
  const id = a.getAttribute('href').slice(1);
  const el = document.getElementById(id);
  if (el) targets.push({ el, a });
});
function updateNav() {
  const y = window.scrollY + 140;
  let current = null;
  for (const { el, a } of targets) {
    if (el.getBoundingClientRect().top + window.scrollY <= y) current = a;
  }
  links.forEach(l => l.classList.remove('active'));
  if (current) current.classList.add('active');
}
window.addEventListener('scroll', updateNav, { passive: true });
updateNav();
</script>'''

def render_page(meta, sections):
    nav = render_nav(sections)
    content = '\n'.join(render_section(s) for s in sections)
    g = lambda k, d='': meta.get(k, d)
    return (
'<!DOCTYPE html>\n<html lang="en">\n<head>\n'
'<meta charset="UTF-8">\n'
'<meta name="viewport" content="width=device-width, initial-scale=1.0">\n'
'<title>%s</title>\n%s\n</head>\n<body>\n\n'
'<aside class="sidebar">\n'
'  <div class="sidebar-brand">\n'
'    <div class="brand-logo"><span class="dark">%s </span><span class="wolf">%s</span></div>\n'
'    <div class="brand-tag">%s</div>\n'
'  </div>\n'
'  <nav class="nav">\n    %s\n  </nav>\n'
'</aside>\n\n'
'<main class="main">\n'
'  <header class="page-header">\n'
'    <h1>%s</h1>\n'
'    <p class="subtitle">%s</p>\n'
'  </header>\n\n'
'%s\n'
'</main>\n\n%s\n\n</body>\n</html>\n'
    ) % (g('title', 'Lab'), STYLE,
         g('brand_dark', 'DARK'), g('brand_wolf', 'WOLF'), g('brand_tag', ''),
         nav, g('header_title', g('title', 'Lab')), g('header_subtitle', ''),
         content, SCRIPT)

# ───────────────────────── entry point ────────────────────────────────────
def main():
    here = os.path.dirname(os.path.abspath(__file__))
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, 'lab.md')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, 'index.html')
    with open(src, encoding='utf-8') as f:
        text = f.read()
    meta, body = split_front_matter(text)
    sections = parse_document(body)
    html = render_page(meta, sections)
    with open(out, 'w', encoding='utf-8') as f:
        f.write(html)
    print('[*] %s -> %s  (%d sections, %d bytes)'
          % (os.path.basename(src), os.path.basename(out), len(sections), len(html)))

if __name__ == '__main__':
    main()

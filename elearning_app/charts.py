"""Tiny server-side SVG chart helpers.

No JavaScript and no internet needed: each function returns an HTML snippet (SVG).
Colours are CSS variables (--c1 ... --c7), so the charts follow light/dark mode on their own.
"""
import math

from markupsafe import Markup, escape

PALETTE = ["var(--c1)", "var(--c2)", "var(--c3)", "var(--c4)", "var(--c5)", "var(--c6)"]
GRADE_COLORS = {"A+": "var(--c3)", "A": "var(--c3)", "B": "var(--c6)",
                "C": "var(--c4)", "D": "var(--c7)", "F": "var(--c5)"}
GRADE_ORDER = ["A+", "A", "B", "C", "D", "F"]


def _fmt(v):
    v = float(v)
    return str(int(v)) if v == int(v) else f"{v:.1f}"


def _nice_max(m):
    if m <= 0:
        return 1
    exp = 10 ** math.floor(math.log10(m))
    for mult in (1, 2, 2.5, 5, 10):
        if m <= mult * exp:
            return mult * exp
    return 10 * exp


def _short(label, n=24):
    label = str(label)
    return label if len(label) <= n else label[: n - 1] + "…"


def _empty(msg="No data yet."):
    return Markup(f'<p class="empty">{escape(msg)}</p>')


def _legend(items):
    """items: list of (label, colour)"""
    lis = "".join(f'<li><i style="background:{c}"></i>{escape(l)}</li>' for l, c in items)
    return f'<ul class="legend">{lis}</ul>'


# ------------------------------------------------------------ horizontal bars
def bar_chart(labels, series, unit="", max_value=None, notes=None):
    """Horizontal (grouped) bars. series = [{"name":..., "values":[...], "color":...}].
    notes = optional text shown at the end of each row (e.g. '10/60')."""
    if not labels or not any(v for s in series for v in s["values"]):
        return _empty()
    n = len(series)
    top = max_value or _nice_max(max(v for s in series for v in s["values"]))
    left, right, bar_h, gap = 150, 56, 16, 14
    row_h = n * (bar_h + 3) + gap
    w = 600
    plot_w = w - left - right
    h = len(labels) * row_h + 26
    out = [f'<svg class="chart" viewBox="0 0 {w} {h}" role="img" preserveAspectRatio="xMinYMin meet">']
    for k in range(5):                                   # vertical grid + axis labels
        x = left + plot_w * k / 4
        out.append(f'<line class="grid" x1="{x:.1f}" y1="0" x2="{x:.1f}" y2="{h - 22}"/>')
        out.append(f'<text class="axis" x="{x:.1f}" y="{h - 6}" text-anchor="middle">{_fmt(top * k / 4)}{unit if k == 4 else ""}</text>')
    for i, label in enumerate(labels):
        y0 = i * row_h + gap / 2
        out.append(f'<text class="lbl" x="{left - 10}" y="{y0 + (n * (bar_h + 3)) / 2 + 4:.1f}" text-anchor="end">{escape(_short(label))}</text>')
        for j, s in enumerate(series):
            val = s["values"][i] or 0
            bw = max(0.0, plot_w * min(val, top) / top)
            y = y0 + j * (bar_h + 3)
            colour = s.get("color") or PALETTE[j % len(PALETTE)]
            tip = f'{label}: {_fmt(val)}{unit}' + (f' ({s["name"]})' if n > 1 else "")
            out.append(f'<rect class="bar-rect" x="{left}" y="{y:.1f}" width="{bw:.1f}" height="{bar_h}" rx="5" style="fill:{colour}"><title>{escape(tip)}</title></rect>')
            txt = _fmt(val) + unit if not (notes and j == 0) else notes[i]
            out.append(f'<text class="val" x="{left + bw + 6:.1f}" y="{y + bar_h - 4:.1f}">{escape(txt)}</text>')
    out.append("</svg>")
    leg = _legend([(s["name"], s.get("color") or PALETTE[j % len(PALETTE)]) for j, s in enumerate(series)]) if n > 1 else ""
    return Markup("".join(out) + leg)


# ------------------------------------------------------------------ columns
def column_chart(labels, values, colors=None, unit=""):
    """Vertical single-series columns (e.g. grade distribution)."""
    if not labels or not any(values):
        return _empty()
    if all(float(v) == int(v) for v in values):          # counts: whole-number ticks
        top = max(4, math.ceil(max(values) / 4) * 4)
    else:
        top = _nice_max(max(values))
    w, h, pad_l, pad_b, pad_t = 600, 230, 34, 28, 16
    plot_h = h - pad_b - pad_t
    slot = (w - pad_l - 10) / len(labels)
    bw = min(54, slot * 0.6)
    out = [f'<svg class="chart" viewBox="0 0 {w} {h}" role="img" preserveAspectRatio="xMinYMin meet">']
    for k in range(5):
        y = pad_t + plot_h * (1 - k / 4)
        out.append(f'<line class="grid" x1="{pad_l}" y1="{y:.1f}" x2="{w - 6}" y2="{y:.1f}"/>')
        out.append(f'<text class="axis" x="{pad_l - 6}" y="{y + 4:.1f}" text-anchor="end">{_fmt(top * k / 4)}</text>')
    for i, (label, val) in enumerate(zip(labels, values)):
        x = pad_l + slot * i + (slot - bw) / 2
        bh = plot_h * val / top
        y = pad_t + plot_h - bh
        colour = (colors[i] if colors else PALETTE[i % len(PALETTE)])
        out.append(f'<rect class="bar-rect" x="{x:.1f}" y="{y:.1f}" width="{bw:.1f}" height="{max(bh, 0):.1f}" rx="6" style="fill:{colour}"><title>{escape(str(label))}: {_fmt(val)}{unit}</title></rect>')
        if val:
            out.append(f'<text class="val" x="{x + bw / 2:.1f}" y="{y - 5:.1f}" text-anchor="middle">{_fmt(val)}{unit}</text>')
        out.append(f'<text class="lbl" x="{x + bw / 2:.1f}" y="{h - 8}" text-anchor="middle">{escape(str(label))}</text>')
    out.append("</svg>")
    return Markup("".join(out))


# -------------------------------------------------------------------- donut
def donut_chart(labels, values, colors=None, center_big="", center_small=""):
    total = sum(values)
    colors = colors or PALETTE
    r, cx, cy, sw = 62, 80, 80, 20
    circ = 2 * math.pi * r
    out = [f'<svg class="donut-svg" viewBox="0 0 160 160" role="img">',
           f'<circle class="ring" cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke-width="{sw}"/>']
    if total > 0:
        offset = 0.0
        for i, v in enumerate(values):
            if v <= 0:
                continue
            seg = circ * v / total
            gap = 2 if sum(1 for x in values if x > 0) > 1 else 0
            out.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke-width="{sw}" '
                       f'stroke-dasharray="{max(seg - gap, 0.1):.2f} {circ - max(seg - gap, 0.1):.2f}" '
                       f'stroke-dashoffset="{-offset:.2f}" transform="rotate(-90 {cx} {cy})" '
                       f'style="stroke:{colors[i % len(colors)]}"><title>{escape(str(labels[i]))}: {_fmt(v)}</title></circle>')
            offset += seg
    out.append(f'<text class="big" x="{cx}" y="{cy + 2}" text-anchor="middle">{escape(str(center_big))}</text>')
    out.append(f'<text class="small" x="{cx}" y="{cy + 20}" text-anchor="middle">{escape(str(center_small))}</text>')
    out.append("</svg>")
    leg = _legend([(f"{l} ({_fmt(v)})", colors[i % len(colors)]) for i, (l, v) in enumerate(zip(labels, values))])
    return Markup(f'<div class="donut">{"".join(out)}{leg}</div>')


# --------------------------------------------------------------------- line
def line_chart(labels, values, max_value=100, unit="%"):
    pts = [(l, v) for l, v in zip(labels, values) if v is not None]
    if len(pts) < 2:
        return _empty("Not enough sessions yet.")
    w, h, pad_l, pad_b, pad_t, pad_r = 600, 220, 38, 30, 14, 30
    top = max_value
    plot_w, plot_h = w - pad_l - pad_r, h - pad_b - pad_t
    xs = [pad_l + plot_w * i / (len(pts) - 1) for i in range(len(pts))]
    ys = [pad_t + plot_h * (1 - min(v, top) / top) for _, v in pts]
    out = [f'<svg class="chart" viewBox="0 0 {w} {h}" role="img" preserveAspectRatio="xMinYMin meet">']
    for k in range(5):
        y = pad_t + plot_h * (1 - k / 4)
        out.append(f'<line class="grid" x1="{pad_l}" y1="{y:.1f}" x2="{w - pad_r}" y2="{y:.1f}"/>')
        out.append(f'<text class="axis" x="{pad_l - 6}" y="{y + 4:.1f}" text-anchor="end">{_fmt(top * k / 4)}</text>')
    path = " ".join(f"{'M' if i == 0 else 'L'}{x:.1f},{y:.1f}" for i, (x, y) in enumerate(zip(xs, ys)))
    area = f"{path} L{xs[-1]:.1f},{pad_t + plot_h} L{xs[0]:.1f},{pad_t + plot_h} Z"
    out.append(f'<path class="area" d="{area}"/>')
    out.append(f'<path class="line" d="{path}" fill="none"/>')
    step = max(1, len(pts) // 8)
    for i, ((label, v), x, y) in enumerate(zip(pts, xs, ys)):
        out.append(f'<circle class="dot" cx="{x:.1f}" cy="{y:.1f}" r="4"><title>{escape(str(label))}: {_fmt(v)}{unit}</title></circle>')
        if i % step == 0 or i == len(pts) - 1:
            out.append(f'<text class="axis" x="{x:.1f}" y="{h - 8}" text-anchor="middle">{escape(str(label))}</text>')
    out.append("</svg>")
    return Markup("".join(out))

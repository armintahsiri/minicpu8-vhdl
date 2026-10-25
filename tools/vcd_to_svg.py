#!/usr/bin/env python3
"""Render selected top-level VCD signals as dependency-free SVG timing plots."""
import argparse
import html
import re
from pathlib import Path


def read_vcd(path):
    scopes, names, values, events = [], {}, {}, []
    in_defs = True
    now = 0
    for line in path.read_text(errors="replace").splitlines():
        line = line.strip()
        if in_defs:
            if line.startswith("$scope"):
                scopes.append(line.split()[2])
            elif line.startswith("$upscope"):
                scopes.pop()
            elif line.startswith("$var"):
                p = line.split()
                if len(scopes) == 1:
                    names[p[3]] = (p[4], int(p[2]))
                    values[p[3]] = "x"
            elif line == "$enddefinitions $end":
                in_defs = False
            continue
        if line.startswith("#"):
            now = int(line[1:])
        elif line.startswith("b"):
            p = line.split()
            if len(p) == 2 and p[1] in names:
                values[p[1]] = p[0][1:]
                events.append((now, p[1], values[p[1]]))
        elif line and line[0] in "01xXzZ" and line[1:] in names:
            values[line[1:]] = line[0].lower()
            events.append((now, line[1:], values[line[1:]]))
    return names, events, now


def render(source, output, signals, title):
    path = Path(source)
    names, events, end = read_vcd(path)
    by_name = {name: ident for ident, (name, _) in names.items()}
    chosen = [(name, by_name[name]) for name in signals if name in by_name]
    if not chosen:
        raise SystemExit(f"none of the requested top-level signals found in {source}")
    width, left, right, row_h, top = 1100, 190, 1060, 52, 70
    height = top + row_h * len(chosen) + 32
    scale = (right-left) / max(end, 1)
    series = {ident: [(0, "x")] for _, ident in chosen}
    for t, ident, value in events:
        if ident in series:
            series[ident].append((t, value))
    colors = ["#1769aa", "#c0392b", "#198754", "#7c3aed", "#d97706", "#0891b2"]
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
           '<rect width="100%" height="100%" fill="#fff"/>',
           f'<text x="24" y="38" font-family="sans-serif" font-size="22" font-weight="bold">{html.escape(title)}</text>',
           f'<text x="{left}" y="58" font-family="sans-serif" font-size="12" fill="#555">0</text>',
           f'<text x="{right-50}" y="58" font-family="sans-serif" font-size="12" fill="#555">end</text>']
    for row, (name, ident) in enumerate(chosen):
        y = top + row * row_h
        out.append(f'<text x="{left-14}" y="{y+22}" text-anchor="end" font-family="monospace" font-size="14">{html.escape(name)}</text>')
        out.append(f'<line x1="{left}" y1="{y+34}" x2="{right}" y2="{y+34}" stroke="#ddd"/>')
        vals = series[ident]
        # Thin events that land at the same SVG x coordinate are retained as vertical changes.
        if names[ident][1] == 1:
            yy = lambda v: y + (11 if v == "1" else 31 if v == "0" else 21)
            points = [(left, yy(vals[0][1]))]
            for t, v in vals[1:]:
                x = left + t * scale
                points.extend([(x, points[-1][1]), (x, yy(v))])
            points.append((right, points[-1][1]))
            d = " ".join(("M" if i == 0 else "L") + f"{x:.1f},{yy:.1f}" for i, (x, yy) in enumerate(points))
            out.append(f'<path d="{d}" fill="none" stroke="{colors[row%len(colors)]}" stroke-width="2"/>')
        else:
            for i, (t, v) in enumerate(vals):
                x = left + t * scale
                x2 = left + (vals[i+1][0] * scale if i+1 < len(vals) else end * scale)
                if x2 - x > 16:
                    out.append(f'<rect x="{x:.1f}" y="{y+9}" width="{x2-x:.1f}" height="28" rx="4" fill="#eef4fb" stroke="#9bb7d2"/>')
                    label = f"0x{int(v,2):02X}" if v and set(v) <= set("01") else v
                    out.append(f'<text x="{(x+x2)/2:.1f}" y="{y+28}" text-anchor="middle" font-family="monospace" font-size="12">{label}</text>')
    out.append(f'<text x="{left}" y="{height-8}" font-family="sans-serif" font-size="12" fill="#555">Simulation time (normalized)</text></svg>')
    Path(output).parent.mkdir(parents=True, exist_ok=True)
    Path(output).write_text("\n".join(out) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("output")
    ap.add_argument("--signals", nargs="+", required=True)
    ap.add_argument("--title", required=True)
    a = ap.parse_args()
    render(a.source, a.output, a.signals, a.title)


if __name__ == "__main__":
    main()

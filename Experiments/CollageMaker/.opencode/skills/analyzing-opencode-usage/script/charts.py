#!/usr/bin/env python3
"""SVG chart generators for LLM usage report.

Input: list of row tuples from merged daily data, where each row is:
    (date, total_tokens, input_tokens, output_tokens, reasoning_tokens,
     sessions, effective_commits, commits, adds, dels, tok_per_commit,
     tok_per_line, reasoning_pct)

Output: SVG string for the chart.
"""


def fmt(v):
    """Format token count for display (1.2M, 3.5K, etc.)."""
    if v >= 1e9:
        return f'{v/1e9:.1f}B'
    if v >= 1e6:
        return f'{v/1e6:.1f}M'
    if v >= 1e3:
        return f'{v/1e3:.1f}K'
    return f'{v:,}'


def fmt_short(v):
    """Compact format for chart axis labels (no commas)."""
    if v >= 1e9:
        return f'{v/1e9:.1f}B'
    if v >= 1e6:
        return f'{v/1e6:.1f}M'
    if v >= 1e3:
        return f'{v/1e3:.1f}K'
    return str(int(v))


def render_stacked_area(rows):
    """Chart 1: Daily Token Breakdown (stacked area).

    Returns SVG string with three gradient-filled layers (input, output, reasoning)
    and a data table below.
    """
    if not rows:
        return '<p style="color:#8892a4">No daily token data in this period.</p>'

    width, height, pad = 800, 320, 55
    n = len(rows)
    max_total = max(r[1] for r in rows) if rows else 1

    def compute_points(values):
        pts = []
        for i, v in enumerate(values):
            x = pad + (int(i * (width - 2*pad) / (n-1)) if n > 1 else width // 2)
            y = height - pad - int(v * (height - 2*pad) / max_total)
            pts.append((x, y))
        return pts

    inp_vals = [r[2] for r in rows]
    out_vals = [r[3] for r in rows]
    rea_vals = [r[4] for r in rows]

    stack_out_top = [inp_vals[i] + out_vals[i] for i in range(n)]
    stack_total = [stack_out_top[i] + rea_vals[i] for i in range(n)]

    inp_pts = compute_points(inp_vals)
    out_bot_pts = list(inp_pts)
    out_top_pts = compute_points(stack_out_top)
    rea_bot_pts = list(out_top_pts)
    rea_top_pts = compute_points(stack_total)

    def pts_to_str(pts):
        return ' '.join(f'{x},{y}' for x, y in pts)

    svg_parts = []
    svg_parts.append(
        f'<svg viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg" class="chart-svg">'
    )

    # Defs: gradients for each layer
    svg_parts.append('  <defs>')
    for name, color in [('inp', '#4fc3f7'), ('out', '#4db6ac'), ('rea', '#ba68c8')]:
        svg_parts.append(
            f'    <linearGradient id="grad-{name}" x1="0" y1="0" x2="0" y2="1">'
        )
        svg_parts.append(
            f'      <stop offset="0%" stop-color="{color}" stop-opacity="0.35"/>'
        )
        svg_parts.append(
            f'      <stop offset="100%" stop-color="{color}" stop-opacity="0.08"/>'
        )
        svg_parts.append('    </linearGradient>')
    svg_parts.append('  </defs>')

    # Reasoning area (topmost)
    rea_area = pts_to_str([p for p in rea_top_pts] + [p for p in reversed(rea_bot_pts)])
    svg_parts.append(
        f'  <polygon points="{rea_area}" fill="url(#grad-rea)" stroke="#ba68c8" '
        f'stroke-width="1" opacity="0.9"/>'
    )

    # Output area (middle)
    out_area = pts_to_str([p for p in out_top_pts] + [p for p in reversed(out_bot_pts)])
    svg_parts.append(
        f'  <polygon points="{out_area}" fill="url(#grad-out)" stroke="#4db6ac" '
        f'stroke-width="1" opacity="0.9"/>'
    )

    # Input area (bottom)
    inp_area = pts_to_str(
        [p for p in inp_pts] + [(inp_pts[-1][0], height-pad), (inp_pts[0][0], height-pad)]
    )
    svg_parts.append(
        f'  <polygon points="{inp_area}" fill="url(#grad-inp)" stroke="#4fc3f7" '
        f'stroke-width="1" opacity="0.9"/>'
    )

    # Data points on top of each layer
    for i in range(n):
        x = inp_pts[i][0]
        y_top = rea_top_pts[i][1]
        svg_parts.append(
            f'  <circle cx="{x}" cy="{y_top}" r="3" fill="#1a1a2e" stroke="#ba68c8" '
            f'stroke-width="1.5" class="chart-point" data-chart-type="stacked" '
            f'data-date="{rows[i][0]}" data-input="{inp_vals[i]}" '
            f'data-output="{out_vals[i]}" data-reasoning="{rea_vals[i]}" '
            f'data-total="{rows[i][1]}"/>'
        )

    # X-axis labels
    step = max(1, n // 8)
    for i in range(0, n, step):
        x = inp_pts[i][0]
        svg_parts.append(
            f'  <text x="{x}" y="{height-10}" text-anchor="middle" '
            f'fill="#8892a4" font-size="10">{rows[i][0]}</text>'
        )

    # Y-axis labels (max, midpoint)
    svg_parts.append(
        f'  <text x="{pad-5}" y="12" text-anchor="end" fill="#8892a4" '
        f'font-size="10">{fmt_short(max_total)}</text>'
    )
    mid = max_total // 2
    if mid > 0:
        y_mid = height - pad - int(mid * (height-2*pad) / max_total)
        svg_parts.append(
            f'  <text x="{pad-5}" y="{y_mid+4}" text-anchor="end" fill="#8892a4" '
            f'font-size="10">{fmt_short(mid)}</text>'
        )

    # Grid lines
    for frac in [0, 0.25, 0.5, 0.75, 1.0]:
        y = height - pad - int(frac * max_total * (height-2*pad) / max_total)
        svg_parts.append(
            f'  <line x1="{pad}" y1="{y}" x2="{width-pad}" y2="{y}" '
            f'stroke="rgba(255,255,255,0.06)" stroke-width="1"/>'
        )

    # Axes
    svg_parts.append(
        f'  <line x1="{pad}" y1="{pad}" x2="{pad}" y2="{height-pad}" '
        f'stroke="#8892a4" stroke-width="1"/>'
    )
    svg_parts.append(
        f'  <line x1="{pad}" y1="{height-pad}" x2="{width-pad}" y2="{height-pad}" '
        f'stroke="#8892a4" stroke-width="1"/>'
    )

    svg_parts.append('</svg>')

    # Chart table (breakdown per day)
    result = '\n'.join(svg_parts)
    result += '<table><thead><tr><th>Date</th><th class="num">Input'
    result += '</th><th class="num">Output</th>'
    result += '<th class="num">Reasoning</th><th class="num">Total</th></tr></thead><tbody>'
    for r in rows:
        result += (
            f'<tr><td>{r[0]}</td><td class="num">{fmt(r[2])}</td>'
            f'<td class="num">{fmt(r[3])}</td><td class="num">{fmt(r[4])}</td>'
            f'<td class="num">{fmt(r[1])}</td></tr>'
        )
    result += '</tbody></table>'
    return result


def render_tokens_vs_commits(rows):
    """Chart 2: Dual-axis tokens vs commits.

    Returns SVG string with token bars/line (left axis) and commit line (right, dashed).
    Includes a data table below.
    """
    if not rows:
        return '<p style="color:#8892a4">No daily data in this period.</p>'

    width, height, pad = 800, 320, 55
    n = len(rows)

    tok_vals = [r[1] for r in rows]
    commit_vals = [r[6] for r in rows]

    max_tok = max(tok_vals) if tok_vals else 1
    max_commits = max(commit_vals) if commit_vals else 1

    def x_coord(i):
        return pad + (int(i * (width-2*pad) / (n-1)) if n > 1 else width // 2)

    def y_tok(v):
        return height - pad - int(v * (height-2*pad) / max_tok)

    def y_commits(v):
        return height - pad - int(v * (height-2*pad) / max_commits)

    svg_parts = []
    svg_parts.append(
        f'<svg viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg" class="chart-svg">'
    )

    # Token bars (background)
    bar_w = max(4, int((width-2*pad) / n * 0.5)) if n > 0 else 10
    for i in range(n):
        x = x_coord(i) - bar_w // 2
        y = y_tok(tok_vals[i])
        h_bar = height - pad - y
        svg_parts.append(
            f'  <rect x="{x}" y="{y}" width="{bar_w}" height="{h_bar}" '
            f'fill="#4fc3f7" opacity="0.15" rx="2"/>'
        )

    # Token line
    tok_points = ' '.join(
        f'{x_coord(i)},{y_tok(tok_vals[i])}' for i in range(n)
    )
    if n > 1:
        tok_area = (
            tok_points + f' {x_coord(0)},{height-pad} {x_coord(-1)},{height-pad}'
        )
        svg_parts.append(f'  <polygon points="{tok_area}" fill="url(#grad-inp)" opacity="0.3"/>')
    svg_parts.append(
        f'  <polyline points="{tok_points}" fill="none" stroke="#4fc3f7"'
        f'stroke-width="2" stroke-linejoin="round"/>'
    )

    # Commit line (right axis, dashed)
    comm_points = ' '.join(
        f'{x_coord(i)},{y_commits(commit_vals[i])}' for i in range(n)
    )
    svg_parts.append(
        f'  <polyline points="{comm_points}" fill="none" stroke="#f5a623"'
        f'stroke-width="2" stroke-linejoin="round" stroke-dasharray="6,3"/>'
    )

    # Data point dots (tokens)
    for i in range(n):
        svg_parts.append(
            f'  <circle cx="{x_coord(i)}" cy="{y_tok(tok_vals[i])}" r="3.5"'
            f' fill="#1a1a2e" stroke="#4fc3f7" stroke-width="1.5"'
            f' class="chart-point" data-chart-type="dual-axis-tok-commits"'
            f' data-date="{rows[i][0]}" data-tokens="{tok_vals[i]}"'
            f' data-commits="{commit_vals[i]}"/>'
        )

    # X-axis labels
    step = max(1, n // 8)
    for i in range(0, n, step):
        svg_parts.append(
            f'  <text x="{x_coord(i)}" y="{height-10}" text-anchor="middle"'
            f' fill="#8892a4" font-size="10">{rows[i][0]}</text>'
        )

    # Left Y-axis (tokens)
    svg_parts.append(
        f'  <text x="{pad-5}" y="12" text-anchor="end" fill="#4fc3f7"'
        f' font-size="10">{fmt_short(max_tok)}</text>'
    )
    mid_tok = max_tok // 2
    if mid_tok > 0:
        y_mid = height - pad - int(mid_tok * (height-2*pad) / max_tok)
        svg_parts.append(
            f'  <text x="{pad-5}" y="{y_mid+4}" text-anchor="end" fill="#4fc3f7"'
            f' font-size="10">{fmt_short(mid_tok)}</text>'
        )

    # Right Y-axis (commits)
    svg_parts.append(
        f'  <text x="{width-pad+8}" y="12" text-anchor="start" fill="#f5a623"'
        f' font-size="10">{max_commits}</text>'
    )
    mid_c = max_commits // 2
    if mid_c > 0:
        y_mid = height - pad - int(mid_c * (height-2*pad) / max_commits)
        svg_parts.append(
            f'  <text x="{width-pad+8}" y="{y_mid+4}" text-anchor="start" fill="#f5a623"'
            f' font-size="10">{mid_c}</text>'
        )

    # Axis lines
    svg_parts.append(
        f'  <line x1="{pad}" y1="{pad}" x2="{pad}" y2="{height-pad}" '
        f'stroke="#4fc3f7" stroke-width="1" opacity="0.5"/>'
    )
    svg_parts.append(
        f'  <line x1="{width-pad}" y1="{pad}" x2="{width-pad}" y2="{height-pad}" '
        f'stroke="#f5a623" stroke-width="1" opacity="0.5"/>'
    )
    svg_parts.append(
        f'  <line x1="{pad}" y1="{height-pad}" x2="{width-pad}" y2="{height-pad}" '
        f'stroke="#8892a4" stroke-width="1"/>'
    )

    # Legend
    lx = pad + 10
    ly = pad + 16
    svg_parts.append(
        f'  <line x1="{lx}" y1="{ly-3}" x2="{lx+16}" y2="{ly-3}" stroke="#4fc3f7" stroke-width="2"/>'
    )
    svg_parts.append(
        f'  <text x="{lx+20}" y="{ly+1}" fill="#8892a4" font-size="10">Total Tokens</text>'
    )
    lx += 130
    svg_parts.append(
        f'  <line x1="{lx}" y1="{ly-3}" x2="{lx+16}" y2="{ly-3}" stroke="#f5a623" '
        f'stroke-width="2" stroke-dasharray="6,3"/>'
    )
    svg_parts.append(
        f'  <text x="{lx+20}" y="{ly+1}" fill="#8892a4" font-size="10">Commits</text>'
    )

    svg_parts.append('</svg>')

    # Table
    result = '\n'.join(svg_parts)
    result += (
        '<table><thead><tr><th>Date</th><th class="num">Total Tokens</th>'
        '<th class="num">Input</th><th class="num">Output</th>'
        '<th class="num">Reasoning</th><th class="num">Commits</th></tr></thead><tbody>'
    )
    for r in rows:
        result += (
            f'<tr><td>{r[0]}</td><td class="num">{fmt(r[1])}</td>'
            f'<td class="num">{fmt(r[2])}</td><td class="num">{fmt(r[3])}</td>'
            f'<td class="num">{fmt(r[4])}</td><td class="num">{r[6]}</td></tr>'
        )
    result += '</tbody></table>'
    return result


def render_efficiency(rows):
    """Chart 3: Dual-axis tokens per commit vs. per line added.

    Returns SVG string with tok/commit line (left axis) and tok/line line (right axis).
    Uses dual-axis when scale ratio > 5, otherwise single dot markers.
    Includes a data table below.
    """
    if not rows:
        return '<p style="color:#8892a4">No daily data in this period.</p>'

    width, height, pad = 800, 320, 55
    n = len(rows)

    tpc_vals = [r[10] for r in rows]
    tpl_vals = [r[11] for r in rows]

    max_tpc = max(tpc_vals) if tpc_vals else 1
    max_tpl = max(tpl_vals) if tpl_vals else 1

    scale_ratio = max_tpc / max_tpl if max_tpl > 0 else 1

    def x_coord(i):
        return pad + (int(i * (width-2*pad) / (n-1)) if n > 1 else width // 2)

    def y_tpc(v):
        return height - pad - int(v * (height-2*pad) / max_tpc)

    def y_tpl(v):
        return height - pad - int(v * (height-2*pad) / max_tpl)

    svg_parts = []
    svg_parts.append(
        f'<svg viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg" class="chart-svg">'
    )

    # Tok/Commit line (left axis)
    tpc_points = ' '.join(
        f'{x_coord(i)},{y_tpc(tpc_vals[i])}' for i in range(n)
    )
    if n > 1:
        tpc_area = (
            tpc_points + f' {x_coord(0)},{height-pad} {x_coord(-1)},{height-pad}'
        )
        svg_parts.append(f'  <polygon points="{tpc_area}" fill="url(#grad-inp)" opacity="0.2"/>')
    svg_parts.append(
        f'  <polyline points="{tpc_points}" fill="none" stroke="#4fc3f7"'
        f'stroke-width="2" stroke-linejoin="round"/>'
    )

    # Tok/Line line (right axis)
    tpl_points = ' '.join(
        f'{x_coord(i)},{y_tpl(tpl_vals[i])}' for i in range(n)
    )
    svg_parts.append(
        f'  <polyline points="{tpl_points}" fill="none" stroke="#4db6ac"'
        f'stroke-width="2" stroke-linejoin="round"/>'
    )

    # Data point dots
    for i in range(n):
        if scale_ratio > 5:
            svg_parts.append(
                f'  <circle cx="{x_coord(i)}" cy="{y_tpc(tpc_vals[i])}" r="3.5"'
                f' fill="#1a1a2e" stroke="#4fc3f7" stroke-width="1.5"'
                f' class="chart-point" data-chart-type="dual-axis-efficiency"'
                f' data-date="{rows[i][0]}" data-tok-per-commit="{tpc_vals[i]}"'
                f' data-tok-per-line="{tpl_vals[i]}"/>'
            )
            tx, ty = x_coord(i), y_tpl(tpl_vals[i])
            tri_pts = f'{tx},{ty-4} {tx-3.5},{ty+4} {tx+3.5},{ty+4}'
            svg_parts.append(
                f'  <polygon points="{tri_pts}" fill="#1a1a2e" stroke="#4db6ac"'
                f'stroke-width="1.5" class="chart-point" data-chart-type="dual-axis-efficiency"'
                f'date="{rows[i][0]}" data-tok-per-commit="{tpc_vals[i]}"'
                f'data-tok-per-line="{tpl_vals[i]}"/>'
            )
        else:
            avg_y = (y_tpc(tpc_vals[i]) + y_tpl(tpl_vals[i])) // 2
            svg_parts.append(
                f'  <circle cx="{x_coord(i)}" cy="{avg_y}" r="3.5"'
                f' fill="#1a1a2e" stroke="#ba68c8" stroke-width="1.5"'
                f' class="chart-point" data-chart-type="dual-axis-efficiency"'
                f'date="{rows[i][0]}" data-tok-per-commit="{tpc_vals[i]}"'
                f'data-tok-per-line="{tpl_vals[i]}"/>'
            )

    # X-axis labels
    step = max(1, n // 8)
    for i in range(0, n, step):
        svg_parts.append(
            f'  <text x="{x_coord(i)}" y="{height-10}" text-anchor="middle"'
            f' fill="#8892a4" font-size="10">{rows[i][0]}</text>'
        )

    # Left Y-axis (tok/commit)
    svg_parts.append(
        f'  <text x="{pad-5}" y="12" text-anchor="end" fill="#4fc3f7"'
        f' font-size="10">{fmt_short(max_tpc)}</text>'
    )
    mid_tpc = max_tpc // 2
    if mid_tpc > 0:
        y_mid = height - pad - int(mid_tpc * (height-2*pad) / max_tpc)
        svg_parts.append(
            f'  <text x="{pad-5}" y="{y_mid+4}" text-anchor="end" fill="#4fc3f7"'
            f' font-size="10">{fmt_short(mid_tpc)}</text>'
        )

    # Right Y-axis (tok/line) — only if scales differ significantly
    if scale_ratio > 5:
        svg_parts.append(
            f'  <text x="{width-pad+8}" y="12" text-anchor="start" fill="#4db6ac"'
            f' font-size="10">{fmt_short(max_tpl)}</text>'
        )
        mid_t = max_tpl // 2
        if mid_t > 0:
            y_mid = height - pad - int(mid_t * (height-2*pad) / max_tpl)
            svg_parts.append(
                f'  <text x="{width-pad+8}" y="{y_mid+4}" text-anchor="start" fill="#4db6ac"'
                f' font-size="10">{fmt_short(mid_t)}</text>'
            )

    # Axis lines
    svg_parts.append(
        f'  <line x1="{pad}" y1="{pad}" x2="{pad}" y2="{height-pad}" '
        f'stroke="#4fc3f7" stroke-width="1" opacity="0.5"/>'
    )
    if scale_ratio > 5:
        svg_parts.append(
            f'  <line x1="{width-pad}" y1="{pad}" x2="{width-pad}" y2="{height-pad}" '
            f'stroke="#4db6ac" stroke-width="1" opacity="0.5"/>'
        )
    svg_parts.append(
        f'  <line x1="{pad}" y1="{height-pad}" x2="{width-pad}" y2="{height-pad}" '
        f'stroke="#8892a4" stroke-width="1"/>'
    )

    # Legend
    lx = pad + 10
    ly = pad + 16
    svg_parts.append(
        f'  <line x1="{lx}" y1="{ly-3}" x2="{lx+16}" y2="{ly-3}" stroke="#4fc3f7" stroke-width="2"/>'
    )
    svg_parts.append(
        f'  <text x="{lx+20}" y="{ly+1}" fill="#8892a4" font-size="10">Tokens / Commit</text>'
    )
    lx += 150
    svg_parts.append(
        f'  <line x1="{lx}" y1="{ly-3}" x2="{lx+16}" y2="{ly-3}" stroke="#4db6ac" stroke-width="2"/>'
    )
    svg_parts.append(
        f'  <text x="{lx+20}" y="{ly+1}" fill="#8892a4" font-size="10">Tokens / Line Added</text>'
    )

    svg_parts.append('</svg>')

    # Table
    result = '\n'.join(svg_parts)
    result += (
        '<table><thead><tr><th>Date</th><th class="num">Tok/Commit</th>'
        '<th class="num">Tok/Line</th><th class="num">Commits</th>'
        '<th class="num">Adds</th></tr></thead><tbody>'
    )
    for r in rows:
        result += (
            f'<tr><td>{r[0]}</td><td class="num">{fmt(r[10])}</td>'
            f'<td class="num">{fmt(r[11])}</td><td class="num">{r[6]}</td>'
            f'<td class="num">{fmt(r[8])}</td></tr>'
        )
    result += '</tbody></table>'
    return result


# ── Test mode (python3 charts.py --test) ─────────────────────────────────────

if __name__ == '__main__':
    import sys

    # Synthetic test data: 10 days of fake merged rows
    test_rows = [
        ('2026-06-19', 52340, 28000, 18340, 6000, 4, 3, 3, 420, 45, 17447, 124, '11.5%'),
        ('2026-06-20', 89120, 45000, 32120, 12000, 6, 5, 5, 680, 78, 17824, 131, '13.5%'),
        ('2026-06-21', 124500, 62000, 45500, 17000, 8, 7, 7, 920, 110, 17786, 135, '13.7%'),
        ('2026-06-22', 45600, 22000, 16600, 7000, 3, 2, 2, 310, 32, 22800, 147, '15.4%'),
        ('2026-06-23', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '—'),
        ('2026-06-24', 156780, 78000, 56780, 22000, 10, 9, 9, 1200, 145, 17420, 131, '14.0%'),
        ('2026-06-25', 203400, 102000, 74400, 27000, 12, 11, 11, 1500, 198, 18491, 136, '13.3%'),
        ('2026-06-26', 98700, 50000, 33700, 15000, 7, 6, 6, 800, 95, 16450, 123, '15.2%'),
        ('2026-06-27', 175200, 88000, 62200, 25000, 11, 10, 10, 1350, 175, 17520, 130, '14.3%'),
        ('2026-06-28', 67890, 34000, 23890, 10000, 5, 4, 4, 520, 62, 16973, 131, '14.7%'),
    ]

    print('=== Chart 1: Stacked Area ===')
    c1 = render_stacked_area(test_rows)
    assert '<svg' in c1 and '</svg>' in c1, "Chart 1 SVG not generated"
    cp_count = c1.count('class="chart-point"')
    assert cp_count == 10, f"Expected 10 chart-points, got {cp_count}"
    print(f'OK — {len(c1)} chars, 10 chart-points\n')

    print('=== Chart 2: Tokens vs Commits ===')
    c2 = render_tokens_vs_commits(test_rows)
    assert '<svg' in c2 and '</svg>' in c2, "Chart 2 SVG not generated"
    assert 'stroke-dasharray="6,3"' in c2, "Missing dashed commit line"
    print(f'OK — {len(c2)} chars\n')

    print('=== Chart 3: Efficiency ===')
    c3 = render_efficiency(test_rows)
    assert '<svg' in c3 and '</svg>' in c3, "Chart 3 SVG not generated"
    print(f'OK — {len(c3)} chars\n')

    # Test empty input
    print('=== Empty input ===')
    e1 = render_stacked_area([])
    assert 'No daily token data' in e1
    e2 = render_tokens_vs_commits([])
    assert 'No daily data' in e2
    e3 = render_efficiency([])
    assert 'No daily data' in e3
    print('OK — empty inputs handled\n')

    # Test fmt functions
    print('=== fmt / fmt_short ===')
    assert fmt(1500) == '1.5K'
    assert fmt(2500000) == '2.5M'
    assert fmt(3200000000) == '3.2B'
    assert fmt(42) == '42'
    assert fmt_short(1500) == '1.5K'
    assert fmt_short(1234567) == '1.2M'
    assert fmt_short(42) == '42'
    print('OK — formatting correct\n')

    print(f'render_report.py: {len(c1)+len(c2)+len(c3)} total SVG chars across 3 charts')
    sys.exit(0)

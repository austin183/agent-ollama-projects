#!/usr/bin/env python3
"""SVG chart generators and HTML table renderers for opencode usage reports.

Two row formats are supported:

**Tuple rows** (used by LLM usage report charts):
    (date, total_tokens, input_tokens, output_tokens, reasoning_tokens,
     sessions, effective_commits, commits, adds, dels, tok_per_commit,
     tok_per_line, reasoning_pct)

**Dict rows** (used by Token Value Analysis report charts):
    Dict with keys: date, total_tokens, cum_tokens, cum_swift/cum_test,
    build_tok, review_tok, plan_tok, explore_tok, other_tok, commits, adds,
    dels, test_adds, test_dels, test_ratio, rolling_tok_per_commit

Output: SVG string or HTML table strings.
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
    max_total = max((r[1] for r in rows), default=0)
    if max_total == 0:
        max_total = 1

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

    Returns SVG string with token bars/line (left axis), uncached input line,
    cached input line, and commit line (right, dashed).
    Includes a data table below.
    """
    if not rows:
        return '<p style="color:#8892a4">No daily data in this period.</p>'

    width, height, pad = 800, 320, 55
    n = len(rows)

    tok_vals = [r[1] for r in rows]
    commit_vals = [r[6] for r in rows]
    uncached_vals = [r[2] for r in rows]
    inp_raw_vals = [r[13] if len(r) > 13 else 0 for r in rows]

    max_tok = max(1, max(tok_vals)) if tok_vals else 1
    max_commits = max(1, max(commit_vals)) if commit_vals else 1

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

    # Uncached input line (green, solid)
    uncached_points = ' '.join(
        f'{x_coord(i)},{y_tok(uncached_vals[i])}' for i in range(n)
    )
    svg_parts.append(
        f'  <polyline points="{uncached_points}" fill="none" stroke="#4db6ac"'
        f'stroke-width="1.5" stroke-linejoin="round"/>'
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
    lx += 120
    svg_parts.append(
        f'  <line x1="{lx}" y1="{ly-3}" x2="{lx+16}" y2="{ly-3}" stroke="#4db6ac" stroke-width="1.5"/>'
    )
    svg_parts.append(
        f'  <text x="{lx+20}" y="{ly+1}" fill="#8892a4" font-size="10">Uncached Input</text>'
    )
    lx += 110
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
        '<th class="num">Input (Uncached)</th><th class="num">Input (Cached)</th>'
        '<th class="num">Output</th><th class="num">Reasoning</th>'
        '<th class="num">Commits</th></tr></thead><tbody>'
    )
    for i, r in enumerate(rows):
        cached_in = max(0, inp_raw_vals[i] - uncached_vals[i])
        result += (
            f'<tr><td>{r[0]}</td><td class="num">{fmt(r[1])}</td>'
            f'<td class="num">{fmt(uncached_vals[i])}</td>'
            f'<td class="num">{fmt(cached_in)}</td>'
            f'<td class="num">{fmt(r[3])}</td>'
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

    max_tpc = max(1, max(tpc_vals)) if tpc_vals else 1
    max_tpl = max(1, max(tpl_vals)) if tpl_vals else 1

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
                f'data-date="{rows[i][0]}" data-tok-per-commit="{tpc_vals[i]}"'
                f'data-tok-per-line="{tpl_vals[i]}"/>'
            )
        else:
            avg_y = (y_tpc(tpc_vals[i]) + y_tpl(tpl_vals[i])) // 2
            svg_parts.append(
                f'  <circle cx="{x_coord(i)}" cy="{avg_y}" r="3.5"'
                f' fill="#1a1a2e" stroke="#ba68c8" stroke-width="1.5"'
                f' class="chart-point" data-chart-type="dual-axis-efficiency"'
                f'data-date="{rows[i][0]}" data-tok-per-commit="{tpc_vals[i]}"'
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


def render_cumulative_efficiency(rows, y_key='cum_swift', y_label='Swift Lines'):
    """Chart: Cumulative tokens vs. cumulative code/test lines (efficiency curve).

    Dual-axis: cumulative tokens (left, area) and cumulative lines (right, line).
    Input: list of dict rows with cum_tokens, cum_swift/cum_test keys.
    """
    if not rows:
        return '<p style="color:#8892a4">No data for efficiency curve.</p>'

    width, height, pad = 800, 320, 55
    n = len(rows)

    tok_vals = [r['cum_tokens'] for r in rows]
    line_vals = [r[y_key] for r in rows]

    max_tok = max(1, max(tok_vals)) if tok_vals else 1
    max_lines = max(1, max(line_vals)) if line_vals else 1

    def x_coord(i):
        return pad + (int(i * (width - 2 * pad) / (n - 1)) if n > 1 else width // 2)

    def y_tok(v):
        return height - pad - int(v * (height - 2 * pad) / max_tok)

    def y_lines(v):
        return height - pad - int(v * (height - 2 * pad) / max_lines)

    svg = []
    svg.append(f'<svg viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg" class="chart-svg">')
    svg.append('  <defs>')
    svg.append('    <linearGradient id="grad-cum-tok" x1="0" y1="0" x2="0" y2="1">')
    svg.append('      <stop offset="0%" stop-color="#4fc3f7" stop-opacity="0.35"/>')
    svg.append('      <stop offset="100%" stop-color="#4fc3f7" stop-opacity="0.08"/>')
    svg.append('    </linearGradient>')
    svg.append('  </defs>')

    # Token area
    tok_pts = ' '.join(f'{x_coord(i)},{y_tok(tok_vals[i])}' for i in range(n))
    tok_area = f'{tok_pts} {x_coord(0)},{height-pad} {x_coord(-1)},{height-pad}'
    svg.append(f'  <polygon points="{tok_area}" fill="url(#grad-cum-tok)" stroke="#4fc3f7" stroke-width="1" opacity="0.9"/>')

    # Lines line
    line_pts = ' '.join(f'{x_coord(i)},{y_lines(line_vals[i])}' for i in range(n))
    svg.append(f'  <polyline points="{line_pts}" fill="none" stroke="#4db6ac" stroke-width="2" stroke-linejoin="round"/>')

    # Data points
    for i in range(n):
        svg.append(
            f'  <circle cx="{x_coord(i)}" cy="{y_tok(tok_vals[i])}" r="3" fill="#1a1a2e" '
            f'stroke="#4fc3f7" stroke-width="1.5" class="chart-point" data-chart-type="cumulative-efficiency" '
            f'data-date="{rows[i]["date"]}" data-cum-tokens="{tok_vals[i]}" data-cum-lines="{line_vals[i]}"/>'
        )

    # X-axis labels
    step = max(1, n // 8)
    for i in range(0, n, step):
        svg.append(f'  <text x="{x_coord(i)}" y="{height-10}" text-anchor="middle" fill="#8892a4" font-size="10">{rows[i]["date"]}</text>')

    # Left Y-axis (tokens)
    svg.append(f'  <text x="{pad-5}" y="12" text-anchor="end" fill="#4fc3f7" font-size="10">{fmt_short(max_tok)}</text>')
    mid_tok = max_tok // 2
    if mid_tok > 0:
        y_mid = height - pad - int(mid_tok * (height - 2 * pad) / max_tok)
        svg.append(f'  <text x="{pad-5}" y="{y_mid+4}" text-anchor="end" fill="#4fc3f7" font-size="10">{fmt_short(mid_tok)}</text>')

    # Right Y-axis (lines)
    svg.append(f'  <text x="{width-pad+8}" y="12" text-anchor="start" fill="#4db6ac" font-size="10">{fmt_short(max_lines)}</text>')
    mid_l = max_lines // 2
    if mid_l > 0:
        y_mid = height - pad - int(mid_l * (height - 2 * pad) / max_lines)
        svg.append(f'  <text x="{width-pad+8}" y="{y_mid+4}" text-anchor="start" fill="#4db6ac" font-size="10">{fmt_short(mid_l)}</text>')

    # Axes
    svg.append(f'  <line x1="{pad}" y1="{pad}" x2="{pad}" y2="{height-pad}" stroke="#4fc3f7" stroke-width="1" opacity="0.5"/>')
    svg.append(f'  <line x1="{width-pad}" y1="{pad}" x2="{width-pad}" y2="{height-pad}" stroke="#4db6ac" stroke-width="1" opacity="0.5"/>')
    svg.append(f'  <line x1="{pad}" y1="{height-pad}" x2="{width-pad}" y2="{height-pad}" stroke="#8892a4" stroke-width="1"/>')

    # Legend
    lx, ly = pad + 10, pad + 16
    svg.append(f'  <rect x="{lx}" y="{ly-8}" width="12" height="8" fill="#4fc3f7" opacity="0.3" rx="1"/>')
    svg.append(f'  <text x="{lx+16}" y="{ly+1}" fill="#8892a4" font-size="10">Cumulative Tokens</text>')
    lx += 160
    svg.append(f'  <line x1="{lx}" y1="{ly-3}" x2="{lx+16}" y2="{ly-3}" stroke="#4db6ac" stroke-width="2"/>')
    svg.append(f'  <text x="{lx+20}" y="{ly+1}" fill="#8892a4" font-size="10">Cumulative {y_label}</text>')

    svg.append('</svg>')

    # Table
    result = '\n'.join(svg)
    result += f'<table><thead><tr><th>Date</th><th class="num">Cum. Tokens</th><th class="num">Cum. {y_label}</th><th class="num">Tok/Line</th></tr></thead><tbody>'
    for r in rows:
        tok_per = round(r['cum_tokens'] / r[y_key]) if r[y_key] > 0 else 0
        result += f'<tr><td>{r["date"]}</td><td class="num">{fmt(r["cum_tokens"])}</td><td class="num">{fmt(r[y_key])}</td><td class="num">{fmt(tok_per)}</td></tr>'
    result += '</tbody></table>'
    return result


def render_daily_agent_stacked(rows):
    """Chart: Daily tokens stacked by agent type (build/review/plan/explore/other).

    Input: list of dict rows with build_tok, review_tok, plan_tok, explore_tok, other_tok keys.
    """
    if not rows:
        return '<p style="color:#8892a4">No daily agent data.</p>'

    width, height, pad = 800, 320, 55
    n = len(rows)

    build_vals = [r.get('build_tok', 0) for r in rows]
    review_vals = [r.get('review_tok', 0) for r in rows]
    plan_vals = [r.get('plan_tok', 0) for r in rows]
    explore_vals = [r.get('explore_tok', 0) for r in rows]
    other_vals = [r.get('other_tok', 0) for r in rows]

    total_vals = [b + rv + p + e + o for b, rv, p, e, o in zip(build_vals, review_vals, plan_vals, explore_vals, other_vals)]
    max_total = max(1, max(total_vals)) if total_vals else 1

    def x_coord(i):
        return pad + (int(i * (width - 2 * pad) / (n - 1)) if n > 1 else width // 2)

    def y_coord(v):
        return height - pad - int(v * (height - 2 * pad) / max_total)

    # Compute stacked layers (bottom to top: build, review, plan, explore, other)
    stack_build = [(x_coord(i), y_coord(build_vals[i])) for i in range(n)]
    stack_review_bot = stack_build[:]
    stack_review_top = [(x_coord(i), y_coord(build_vals[i] + review_vals[i])) for i in range(n)]
    stack_plan_bot = stack_review_top[:]
    stack_plan_top = [(x_coord(i), y_coord(build_vals[i] + review_vals[i] + plan_vals[i])) for i in range(n)]
    stack_explore_bot = stack_plan_top[:]
    stack_explore_top = [(x_coord(i), y_coord(build_vals[i] + review_vals[i] + plan_vals[i] + explore_vals[i])) for i in range(n)]
    stack_other_bot = stack_explore_top[:]
    stack_other_top = [(x_coord(i), y_coord(total_vals[i])) for i in range(n)]

    def pts_str(pts):
        return ' '.join(f'{x},{y}' for x, y in pts)

    svg = []
    svg.append(f'<svg viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg" class="chart-svg">')
    svg.append('  <defs>')
    for name, color in [('build', '#4fc3f7'), ('review', '#4db6ac'), ('plan', '#ba68c8'), ('explore', '#f5a623'), ('other', '#8892a4')]:
        svg.append(f'    <linearGradient id="grad-{name}" x1="0" y1="0" x2="0" y2="1">')
        svg.append(f'      <stop offset="0%" stop-color="{color}" stop-opacity="0.35"/>')
        svg.append(f'      <stop offset="100%" stop-color="{color}" stop-opacity="0.08"/>')
        svg.append('    </linearGradient>')
    svg.append('  </defs>')

    # Draw from top to bottom (other on top)
    layers = [
        ('other', stack_other_top, stack_other_bot, '#8892a4'),
        ('explore', stack_explore_top, stack_explore_bot, '#f5a623'),
        ('plan', stack_plan_top, stack_plan_bot, '#ba68c8'),
        ('review', stack_review_top, stack_review_bot, '#4db6ac'),
        ('build', stack_build, [(p[0], height - pad) for p in stack_build], '#4fc3f7'),
    ]
    for name, top_pts, bot_pts, color in layers:
        area = pts_str(top_pts) + ' ' + pts_str(reversed(bot_pts))
        svg.append(f'  <polygon points="{area}" fill="url(#grad-{name})" stroke="{color}" stroke-width="0.5" opacity="0.9"/>')

    # Data points on top
    for i in range(n):
        svg.append(
            f'  <circle cx="{x_coord(i)}" cy="{y_coord(total_vals[i])}" r="3" fill="#1a1a2e" '
            f'stroke="#8892a4" stroke-width="1.5" class="chart-point" data-chart-type="agent-stacked" '
            f'data-date="{rows[i]["date"]}" data-build="{build_vals[i]}" data-review="{review_vals[i]}" '
            f'data-plan="{plan_vals[i]}" data-explore="{explore_vals[i]}" data-other="{other_vals[i]}" data-total="{total_vals[i]}"/>'
        )

    # X-axis labels
    step = max(1, n // 8)
    for i in range(0, n, step):
        svg.append(f'  <text x="{x_coord(i)}" y="{height-10}" text-anchor="middle" fill="#8892a4" font-size="10">{rows[i]["date"]}</text>')

    # Y-axis
    svg.append(f'  <text x="{pad-5}" y="12" text-anchor="end" fill="#8892a4" font-size="10">{fmt_short(max_total)}</text>')
    mid = max_total // 2
    if mid > 0:
        y_mid = height - pad - int(mid * (height - 2 * pad) / max_total)
        svg.append(f'  <text x="{pad-5}" y="{y_mid+4}" text-anchor="end" fill="#8892a4" font-size="10">{fmt_short(mid)}</text>')

    # Axes
    svg.append(f'  <line x1="{pad}" y1="{pad}" x2="{pad}" y2="{height-pad}" stroke="#8892a4" stroke-width="1"/>')
    svg.append(f'  <line x1="{pad}" y1="{height-pad}" x2="{width-pad}" y2="{height-pad}" stroke="#8892a4" stroke-width="1"/>')

    # Legend
    lx, ly = pad + 10, pad + 16
    for label, color in [('Build', '#4fc3f7'), ('Review', '#4db6ac'), ('Plan', '#ba68c8'), ('Explore', '#f5a623'), ('Other', '#8892a4')]:
        svg.append(f'  <rect x="{lx}" y="{ly-8}" width="10" height="8" fill="{color}" opacity="0.5" rx="1"/>')
        svg.append(f'  <text x="{lx+14}" y="{ly+1}" fill="#8892a4" font-size="10">{label}</text>')
        lx += 75

    svg.append('</svg>')

    # Table
    result = '\n'.join(svg)
    result += '<table><thead><tr><th>Date</th><th class="num">Build</th><th class="num">Review</th><th class="num">Plan</th><th class="num">Explore</th><th class="num">Other</th><th class="num">Total</th></tr></thead><tbody>'
    for r in rows:
        result += (
            f'<tr><td>{r["date"]}</td>'
            f'<td class="num">{fmt(r.get("build_tok", 0))}</td>'
            f'<td class="num">{fmt(r.get("review_tok", 0))}</td>'
            f'<td class="num">{fmt(r.get("plan_tok", 0))}</td>'
            f'<td class="num">{fmt(r.get("explore_tok", 0))}</td>'
            f'<td class="num">{fmt(r.get("other_tok", 0))}</td>'
            f'<td class="num">{fmt(r.get("total_effective", 0))}</td></tr>'
        )
    result += '</tbody></table>'
    return result


def render_rolling_tok_per_commit(rows):
    """Chart: 7-day rolling tokens per commit (smoothed efficiency trend).

    Input: list of dict rows with rolling_tok_per_commit, commits keys.
    """
    if not rows:
        return '<p style="color:#8892a4">No rolling efficiency data.</p>'

    width, height, pad = 800, 320, 55
    n = len(rows)

    vals = [r.get('rolling_tok_per_commit', 0) for r in rows]
    max_val = max(1, max(vals)) if vals else 1

    def x_coord(i):
        return pad + (int(i * (width - 2 * pad) / (n - 1)) if n > 1 else width // 2)

    def y_coord(v):
        return height - pad - int(v * (height - 2 * pad) / max_val)

    svg = []
    svg.append(f'<svg viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg" class="chart-svg">')
    svg.append('  <defs>')
    svg.append('    <linearGradient id="grad-inp" x1="0" y1="0" x2="0" y2="1">')
    svg.append('      <stop offset="0%" stop-color="#4fc3f7" stop-opacity="0.35"/>')
    svg.append('      <stop offset="100%" stop-color="#4fc3f7" stop-opacity="0.08"/>')
    svg.append('    </linearGradient>')
    svg.append('  </defs>')

    # Line + area
    pts = ' '.join(f'{x_coord(i)},{y_coord(vals[i])}' for i in range(n))
    area = f'{pts} {x_coord(0)},{height-pad} {x_coord(-1)},{height-pad}'
    svg.append(f'  <polygon points="{area}" fill="url(#grad-inp)" opacity="0.2"/>')
    svg.append(f'  <polyline points="{pts}" fill="none" stroke="#4fc3f7" stroke-width="2" stroke-linejoin="round"/>')

    # Points
    for i in range(n):
        svg.append(
            f'  <circle cx="{x_coord(i)}" cy="{y_coord(vals[i])}" r="3.5" fill="#1a1a2e" '
            f'stroke="#4fc3f7" stroke-width="1.5" class="chart-point" data-chart-type="rolling-tpc" '
            f'data-date="{rows[i]["date"]}" data-rolling-tpc="{vals[i]}"/>'
        )

    # X-axis labels
    step = max(1, n // 8)
    for i in range(0, n, step):
        svg.append(f'  <text x="{x_coord(i)}" y="{height-10}" text-anchor="middle" fill="#8892a4" font-size="10">{rows[i]["date"]}</text>')

    # Y-axis + grid
    svg.append(f'  <text x="{pad-5}" y="12" text-anchor="end" fill="#4fc3f7" font-size="10">{fmt_short(max_val)}</text>')
    mid = max_val // 2
    if mid > 0:
        y_mid = height - pad - int(mid * (height - 2 * pad) / max_val)
        svg.append(f'  <text x="{pad-5}" y="{y_mid+4}" text-anchor="end" fill="#4fc3f7" font-size="10">{fmt_short(mid)}</text>')

    for frac in [0, 0.25, 0.5, 0.75, 1.0]:
        y = height - pad - int(frac * max_val * (height - 2 * pad) / max_val)
        svg.append(f'  <line x1="{pad}" y1="{y}" x2="{width-pad}" y2="{y}" stroke="rgba(255,255,255,0.06)" stroke-width="1"/>')

    # Axes
    svg.append(f'  <line x1="{pad}" y1="{pad}" x2="{pad}" y2="{height-pad}" stroke="#8892a4" stroke-width="1"/>')
    svg.append(f'  <line x1="{pad}" y1="{height-pad}" x2="{width-pad}" y2="{height-pad}" stroke="#8892a4" stroke-width="1"/>')

    svg.append('</svg>')

    # Table
    result = '\n'.join(svg)
    result += '<table><thead><tr><th>Date</th><th class="num">7d Avg Tok/Commit</th><th class="num">Commits</th></tr></thead><tbody>'
    for r in rows:
        result += f'<tr><td>{r["date"]}</td><td class="num">{fmt(r.get("rolling_tok_per_commit", 0))}</td><td class="num">{r.get("commits", 0)}</td></tr>'
    result += '</tbody></table>'
    return result


def render_test_ratio(rows):
    """Chart: Test ratio over time (test lines as % of total code adds).

    Input: list of dict rows with test_adds, adds, test_ratio keys.
    """
    if not rows:
        return '<p style="color:#8892a4">No test ratio data.</p>'

    # Filter to days with code adds
    rows = [r for r in rows if r.get('adds', 0) > 0]
    if not rows:
        return '<p style="color:#8892a4">No days with code additions.</p>'

    width, height, pad = 800, 260, 55
    n = len(rows)
    max_val = 100.0  # percentage

    def x_coord(i):
        return pad + (int(i * (width - 2 * pad) / (n - 1)) if n > 1 else width // 2)

    def y_coord(v):
        return height - pad - int(v * (height - 2 * pad) / max_val)

    svg = []
    svg.append(f'<svg viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg" class="chart-svg">')
    svg.append('  <defs>')
    svg.append('    <linearGradient id="grad-out" x1="0" y1="0" x2="0" y2="1">')
    svg.append('      <stop offset="0%" stop-color="#4db6ac" stop-opacity="0.35"/>')
    svg.append('      <stop offset="100%" stop-color="#4db6ac" stop-opacity="0.08"/>')
    svg.append('    </linearGradient>')
    svg.append('  </defs>')

    # Area + line
    pts = ' '.join(f'{x_coord(i)},{y_coord(rows[i].get("test_ratio", 0))}' for i in range(n))
    area = f'{pts} {x_coord(0)},{height-pad} {x_coord(-1)},{height-pad}'
    svg.append(f'  <polygon points="{area}" fill="url(#grad-out)" opacity="0.3"/>')
    svg.append(f'  <polyline points="{pts}" fill="none" stroke="#4db6ac" stroke-width="2" stroke-linejoin="round"/>')

    # 36% reference line
    ref_y = y_coord(36)
    svg.append(f'  <line x1="{pad}" y1="{ref_y}" x2="{width-pad}" y2="{ref_y}" stroke="#f5a623" stroke-width="1" stroke-dasharray="4,4"/>')
    svg.append(f'  <text x="{width-pad+8}" y="{ref_y+4}" text-anchor="start" fill="#f5a623" font-size="9">36% target</text>')

    # Points
    for i in range(n):
        svg.append(
            f'  <circle cx="{x_coord(i)}" cy="{y_coord(rows[i].get("test_ratio", 0))}" r="3.5" fill="#1a1a2e" '
            f'stroke="#4db6ac" stroke-width="1.5" class="chart-point" data-chart-type="test-ratio" '
            f'data-date="{rows[i]["date"]}" data-test-ratio="{rows[i].get("test_ratio", 0)}"/>'
        )

    # X-axis labels
    step = max(1, n // 8)
    for i in range(0, n, step):
        svg.append(f'  <text x="{x_coord(i)}" y="{height-10}" text-anchor="middle" fill="#8892a4" font-size="10">{rows[i]["date"]}</text>')

    # Y-axis grid + labels
    for pct in [0, 25, 50, 75, 100]:
        y = y_coord(pct)
        svg.append(f'  <text x="{pad-5}" y="{y+4}" text-anchor="end" fill="#8892a4" font-size="10">{pct}%</text>')
        svg.append(f'  <line x1="{pad}" y1="{y}" x2="{width-pad}" y2="{y}" stroke="rgba(255,255,255,0.06)" stroke-width="1"/>')

    # Axes
    svg.append(f'  <line x1="{pad}" y1="{pad}" x2="{pad}" y2="{height-pad}" stroke="#8892a4" stroke-width="1"/>')
    svg.append(f'  <line x1="{pad}" y1="{height-pad}" x2="{width-pad}" y2="{height-pad}" stroke="#8892a4" stroke-width="1"/>')

    svg.append('</svg>')

    # Table
    result = '\n'.join(svg)
    result += '<table><thead><tr><th>Date</th><th class="num">Test Adds</th><th class="num">Total Adds</th><th class="num">Test %</th></tr></thead><tbody>'
    for r in rows:
        result += f'<tr><td>{r["date"]}</td><td class="num">{fmt(r.get("test_adds", 0))}</td><td class="num">{fmt(r.get("adds", 0))}</td><td class="num">{r.get("test_ratio", 0)}%</td></tr>'
    result += '</tbody></table>'
    return result


def render_context_efficiency_table(agents_detailed):
    """Table: Agent context efficiency (avg turns, avg input/session, avg input/turn).

    Input: list of dicts with context_type, sessions, total_tokens_raw, input_tokens_raw,
    output_tokens_raw, reasoning_tokens_raw keys.
    """
    if not agents_detailed:
        return '<p style="color:#8892a4">No context efficiency data.</p>'

    # Filter out agents with zero tokens (failed sessions, model errors)
    agents_detailed = [a for a in agents_detailed if (a.get('total_tokens_raw', 0) or 0) > 0]
    if not agents_detailed:
        return '<p style="color:#8892a4">No agents with token data.</p>'

    html = '<table><thead><tr><th>Agent</th><th class="num">Sessions</th><th class="num">Total Tokens</th><th class="num">Input</th><th class="num">Output</th><th class="num">Reasoning</th></tr></thead><tbody>'
    for a in agents_detailed:
        name = (a.get('context_type') or 'unknown').replace('_', '-').replace('-', '-')[:20]
        sessions = a.get('sessions', 0) or 0
        total_tok = a.get('total_tokens_raw', 0) or 0
        inp = a.get('input_tokens_raw', 0) or 0
        out_ = a.get('output_tokens_raw', 0) or 0
        rea = a.get('reasoning_tokens_raw', 0) or 0
        html += f'<tr><td>{name}</td><td class="num">{sessions}</td><td class="num">{fmt(total_tok)}</td><td class="num">{fmt(inp)}</td><td class="num">{fmt(out_)}</td><td class="num">{fmt(rea)}</td></tr>'
    html += '</tbody></table>'
    return html


def render_cumulative_cost(rows):
    """Chart: Cumulative estimated cost over time (dual-axis: low/high estimates).

    Input: list of dict rows with cost_cheap, cost_expensive, daily_cost_cheap, daily_cost_expensive keys.
    """
    if not rows:
        return '<p style="color:#8892a4">No cost data.</p>'

    width, height, pad = 800, 320, 55
    n = len(rows)

    cheap_vals = [r.get('cost_cheap', 0) for r in rows]
    exp_vals = [r.get('cost_expensive', 0) for r in rows]

    max_cheap = max(1, max(cheap_vals)) if cheap_vals else 1
    max_exp = max(1, max(exp_vals)) if exp_vals else 1

    def x_coord(i):
        return pad + (int(i * (width - 2 * pad) / (n - 1)) if n > 1 else width // 2)

    def y_cheap(v):
        return height - pad - int(v * (height - 2 * pad) / max_cheap)

    def y_exp(v):
        return height - pad - int(v * (height - 2 * pad) / max_exp)

    svg = []
    svg.append(f'<svg viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg" class="chart-svg">')
    svg.append('  <defs>')
    svg.append('    <linearGradient id="grad-cheap" x1="0" y1="0" x2="0" y2="1">')
    svg.append('      <stop offset="0%" stop-color="#f5a623" stop-opacity="0.25"/>')
    svg.append('      <stop offset="100%" stop-color="#f5a623" stop-opacity="0.05"/>')
    svg.append('    </linearGradient>')
    svg.append('  </defs>')

    # Cheap estimate area
    cheap_pts = ' '.join(f'{x_coord(i)},{y_cheap(cheap_vals[i])}' for i in range(n))
    cheap_area = f'{cheap_pts} {x_coord(0)},{height-pad} {x_coord(-1)},{height-pad}'
    svg.append(f'  <polygon points="{cheap_area}" fill="url(#grad-cheap)" stroke="#f5a623" stroke-width="1" opacity="0.8"/>')

    # Expensive estimate line
    exp_pts = ' '.join(f'{x_coord(i)},{y_exp(exp_vals[i])}' for i in range(n))
    svg.append(f'  <polyline points="{exp_pts}" fill="none" stroke="#ef5350" stroke-width="2" stroke-linejoin="round" stroke-dasharray="6,3"/>')

    # Data points
    for i in range(n):
        svg.append(
            f'  <circle cx="{x_coord(i)}" cy="{y_cheap(cheap_vals[i])}" r="3" fill="#1a1a2e" '
            f'stroke="#f5a623" stroke-width="1.5" class="chart-point" data-chart-type="cumulative-cost" '
            f'data-date="{rows[i]["date"]}" data-cost-low="{cheap_vals[i]}" data-cost-high="{exp_vals[i]}" '
            f'data-daily-low="{rows[i].get("daily_cost_cheap", 0)}" data-daily-high="{rows[i].get("daily_cost_expensive", 0)}"/>'
        )

    # X-axis labels
    step = max(1, n // 8)
    for i in range(0, n, step):
        svg.append(f'  <text x="{x_coord(i)}" y="{height-10}" text-anchor="middle" fill="#8892a4" font-size="10">{rows[i]["date"]}</text>')

    # Left Y-axis (cheap)
    svg.append(f'  <text x="{pad-5}" y="12" text-anchor="end" fill="#f5a623" font-size="10">${max_cheap:,.0f}</text>')
    mid_c = max_cheap // 2
    if mid_c > 0:
        y_mid = height - pad - int(mid_c * (height - 2 * pad) / max_cheap)
        svg.append(f'  <text x="{pad-5}" y="{y_mid+4}" text-anchor="end" fill="#f5a623" font-size="10">${mid_c:,.0f}</text>')

    # Right Y-axis (expensive)
    svg.append(f'  <text x="{width-pad+8}" y="12" text-anchor="start" fill="#ef5350" font-size="10">${max_exp:,.0f}</text>')
    mid_e = max_exp // 2
    if mid_e > 0:
        y_mid = height - pad - int(mid_e * (height - 2 * pad) / max_exp)
        svg.append(f'  <text x="{width-pad+8}" y="{y_mid+4}" text-anchor="start" fill="#ef5350" font-size="10">${mid_e:,.0f}</text>')

    # Axes
    svg.append(f'  <line x1="{pad}" y1="{pad}" x2="{pad}" y2="{height-pad}" stroke="#f5a623" stroke-width="1" opacity="0.5"/>')
    svg.append(f'  <line x1="{width-pad}" y1="{pad}" x2="{width-pad}" y2="{height-pad}" stroke="#ef5350" stroke-width="1" opacity="0.5"/>')
    svg.append(f'  <line x1="{pad}" y1="{height-pad}" x2="{width-pad}" y2="{height-pad}" stroke="#8892a4" stroke-width="1"/>')

    # Legend
    lx, ly = pad + 10, pad + 16
    svg.append(f'  <rect x="{lx}" y="{ly-8}" width="12" height="8" fill="#f5a623" opacity="0.3" rx="1"/>')
    svg.append(f'  <text x="{lx+16}" y="{ly+1}" fill="#8892a4" font-size="10">Cum. Cost (Low)</text>')
    lx += 140
    svg.append(f'  <line x1="{lx}" y1="{ly-3}" x2="{lx+16}" y2="{ly-3}" stroke="#ef5350" stroke-width="2" stroke-dasharray="6,3"/>')
    svg.append(f'  <text x="{lx+20}" y="{ly+1}" fill="#8892a4" font-size="10">Cum. Cost (High)</text>')

    svg.append('</svg>')

    # Table
    result = '\n'.join(svg)
    result += '<table><thead><tr><th>Date</th><th class="num">Daily (Low)</th><th class="num">Daily (High)</th><th class="num">Cum. (Low)</th><th class="num">Cum. (High)</th></tr></thead><tbody>'
    for r in rows:
        result += (
            f'<tr><td>{r["date"]}</td>'
            f'<td class="num">${r.get("daily_cost_cheap", 0):,.2f}</td>'
            f'<td class="num">${r.get("daily_cost_expensive", 0):,.2f}</td>'
            f'<td class="num">${r.get("cost_cheap", 0):,.2f}</td>'
            f'<td class="num">${r.get("cost_expensive", 0):,.2f}</td></tr>'
        )
    result += '</tbody></table>'
    return result


# ── Test mode (python3 charts.py --test) ─────────────────────────────────────

if __name__ == '__main__':
    import sys

    # ── Tuple-row test data (LLM usage report charts) ────────────────────────
    tuple_rows = [
        ('2026-06-19', 52340, 28000, 18340, 6000, 4, 3, 3, 420, 45, 17447, 124, '11.5%'),
        ('2026-06-20', 89120, 45000, 32120, 12000, 6, 5, 5, 680, 78, 17824, 131, '13.5%'),
        ('2026-06-21', 124500, 62000, 45500, 17000, 8, 7, 7, 920, 110, 17786, 135, '13.7%'),
        ('2026-06-22', 45600, 22000, 16600, 7000, 3, 2, 2, 310, 32, 22800, 147, '15.4%'),
        ('2026-06-24', 156780, 78000, 56780, 22000, 10, 9, 9, 1200, 145, 17420, 131, '14.0%'),
        ('2026-06-25', 203400, 102000, 74400, 27000, 12, 11, 11, 1500, 198, 18491, 136, '13.3%'),
        ('2026-06-26', 98700, 50000, 33700, 15000, 7, 6, 6, 800, 95, 16450, 123, '15.2%'),
        ('2026-06-27', 175200, 88000, 62200, 25000, 11, 10, 10, 1350, 175, 17520, 130, '14.3%'),
        ('2026-06-28', 67890, 34000, 23890, 10000, 5, 4, 4, 520, 62, 16973, 131, '14.7%'),
    ]

    print('=== Chart: Stacked Area (tuple rows) ===')
    c1 = render_stacked_area(tuple_rows)
    assert '<svg' in c1 and '</svg>' in c1
    cp_count = c1.count('class="chart-point"')
    assert cp_count == 9, f"Expected 9 chart-points, got {cp_count}"
    print(f'OK — {len(c1)} chars\n')

    print('=== Chart: Tokens vs Commits (tuple rows) ===')
    c2 = render_tokens_vs_commits(tuple_rows)
    assert '<svg' in c2 and '</svg>' in c2
    assert 'stroke-dasharray="6,3"' in c2
    print(f'OK — {len(c2)} chars\n')

    print('=== Chart: Efficiency (tuple rows) ===')
    c3 = render_efficiency(tuple_rows)
    assert '<svg' in c3 and '</svg>' in c3
    print(f'OK — {len(c3)} chars\n')

    # ── Dict-row test data (Token Value Analysis charts) ──────────────────────
    cum_tok = 0
    cum_swift = 0
    cum_test = 0
    dict_rows = []
    cum_cheap = 0.0
    cum_exp = 0.0
    for i in range(15):
        date = f'2026-05-{25+i:02d}' if i < 7 else f'2026-06-{i-6:02d}'
        adds = 200 + i * 30
        test_adds = int(adds * 0.35)
        tokens = 15000000 + i * 500000
        cum_tok += tokens
        cum_swift += adds
        cum_test += test_adds
        day_cheap = tokens * 0.05 / 1e6
        day_exp = tokens * 0.50 / 1e6
        cum_cheap += day_cheap
        cum_exp += day_exp
        dict_rows.append({
            'date': date,
            'total_tokens': tokens,
            'cum_tokens': cum_tok,
            'cum_swift': cum_swift,
            'cum_test': cum_test,
            'build_tok': int(tokens * 0.85),
            'review_tok': int(tokens * 0.05),
            'plan_tok': int(tokens * 0.05),
            'explore_tok': int(tokens * 0.03),
            'other_tok': int(tokens * 0.02),
            'commits': max(1, i // 2),
            'adds': adds,
            'test_adds': test_adds,
            'test_ratio': 35.0,
            'rolling_tok_per_commit': 10000000 - i * 200000,
            'cost_cheap': round(cum_cheap, 2),
            'cost_expensive': round(cum_exp, 2),
            'daily_cost_cheap': round(day_cheap, 2),
            'daily_cost_expensive': round(day_exp, 2),
        })

    print('=== Chart: Cumulative Efficiency (swift) ===')
    c4 = render_cumulative_efficiency(dict_rows, 'cum_swift', 'Swift Lines')
    assert '<svg' in c4 and '</svg>' in c4
    print(f'OK — {len(c4)} chars\n')

    print('=== Chart: Cumulative Efficiency (test) ===')
    c5 = render_cumulative_efficiency(dict_rows, 'cum_test', 'Test Lines')
    assert '<svg' in c5 and '</svg>' in c5
    print(f'OK — {len(c5)} chars\n')

    print('=== Chart: Agent Stacked (dict rows) ===')
    c6 = render_daily_agent_stacked(dict_rows)
    assert '<svg' in c6 and '</svg>' in c6
    print(f'OK — {len(c6)} chars\n')

    print('=== Chart: Rolling Tok/Commit ===')
    c7 = render_rolling_tok_per_commit(dict_rows)
    assert '<svg' in c7 and '</svg>' in c7
    print(f'OK — {len(c7)} chars\n')

    print('=== Chart: Test Ratio ===')
    c8 = render_test_ratio(dict_rows)
    assert '<svg' in c8 and '</svg>' in c8
    assert '36% target' in c8
    print(f'OK — {len(c8)} chars\n')

    print('=== Chart: Cumulative Cost ===')
    c9 = render_cumulative_cost(dict_rows)
    assert '<svg' in c9 and '</svg>' in c9
    assert 'Cum. Cost (Low)' in c9
    print(f'OK — {len(c9)} chars\n')

    test_agents = [
        {'agent': 'build', 'sessions': 400, 'total_tokens': 900000000, 'total_input': 800000000, 'avg_turns': 2.2, 'avg_input_per_turn': 639000},
        {'agent': 'explore', 'sessions': 100, 'total_tokens': 17000000, 'total_input': 17000000, 'avg_turns': 1.0, 'avg_input_per_turn': 170000},
    ]
    print('=== Table: Context Efficiency ===')
    t1 = render_context_efficiency_table(test_agents)
    assert '<table' in t1
    print(f'OK — {len(t1)} chars\n')

    # ── Empty input handling ───────────────────────────────────────────────────
    print('=== Empty inputs ===')
    for fn, args in [
        (render_stacked_area, ([],)),
        (render_tokens_vs_commits, ([],)),
        (render_efficiency, ([],)),
        (render_cumulative_efficiency, ([],)),
        (render_daily_agent_stacked, ([],)),
        (render_rolling_tok_per_commit, ([],)),
        (render_test_ratio, ([],)),
        (render_context_efficiency_table, ([],)),
        (render_cumulative_cost, ([],)),
    ]:
        result = fn(*args)
        assert 'color:#8892a4' in result or 'No data' in result or 'No ' in result, f"{fn.__name__} empty handling failed"
    print('OK — all empty inputs handled\n')

    # ── fmt / fmt_short ────────────────────────────────────────────────────────
    print('=== fmt / fmt_short ===')
    assert fmt(1500) == '1.5K'
    assert fmt(2500000) == '2.5M'
    assert fmt(3200000000) == '3.2B'
    assert fmt(42) == '42'
    assert fmt_short(1500) == '1.5K'
    assert fmt_short(1234567) == '1.2M'
    assert fmt_short(42) == '42'
    print('OK\n')

    total = len(c1) + len(c2) + len(c3) + len(c4) + len(c5) + len(c6) + len(c7) + len(c8) + len(c9) + len(t1)
    print(f'Total SVG chars: {total} across 10 chart/table generators')

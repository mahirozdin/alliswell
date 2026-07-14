#!/usr/bin/env python3
"""WCAG contrast guard for the AllisWell Glass palette (docs/DESIGN.md §7).

Checks every documented foreground/background pair against its threshold:
text >= 4.5:1, icons & interactive borders >= 3:1. Keep this file in sync
with apps/app/lib/src/theme/{tokens,theme}.dart — a palette change ships
only when this prints `FAILURES: 0`.
"""


def _lum(hexc: str) -> float:
    hexc = hexc.lstrip('#')
    r, g, b = (int(hexc[i : i + 2], 16) / 255 for i in (0, 2, 4))

    def f(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def ratio(a: str, b: str) -> float:
    la, lb = _lum(a), _lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


# (name, fg, bg, minimum)
PAIRS = [
    # ── Light ── text (>= 4.5)
    ('L body on background', '#101828', '#F4F6FB', 4.5),
    ('L body on surface', '#101828', '#FFFFFF', 4.5),
    ('L secondary on surface', '#43516C', '#FFFFFF', 4.5),
    ('L secondary on input fill', '#43516C', '#E9EEF7', 4.5),
    ('L onPrimary on primary', '#FFFFFF', '#2563EB', 4.5),
    ('L link on background', '#1D4ED8', '#F4F6FB', 4.5),
    ('L error on surface', '#B42318', '#FFFFFF', 4.5),
    ('L onPrimaryContainer', '#1E3A8A', '#DBEAFE', 4.5),
    ('L success on surface', '#047857', '#FFFFFF', 4.5),
    ('L snackbar text', '#EFF3FA', '#1D2739', 4.5),
    # ── Light ── icons/borders (>= 3)
    ('L input border vs fill', '#697D9E', '#E9EEF7', 3.0),
    ('L input border vs surface', '#697D9E', '#FFFFFF', 3.0),
    ('L prio low flag', '#047857', '#FFFFFF', 3.0),
    ('L prio medium flag', '#B45309', '#FFFFFF', 3.0),
    ('L prio high flag', '#C2410C', '#FFFFFF', 3.0),
    ('L prio urgent flag', '#DC2626', '#FFFFFF', 3.0),
    ('L warning star', '#B45309', '#FFFFFF', 3.0),
    ('L tertiary dot', '#0F766E', '#FFFFFF', 3.0),
    ('L primary icon on surface', '#2563EB', '#FFFFFF', 3.0),
    # ── Dark ── text (>= 4.5)
    ('D body on background', '#E7ECF6', '#0B1020', 4.5),
    ('D body on surface', '#E7ECF6', '#131C31', 4.5),
    ('D secondary on surface', '#A8B4CE', '#131C31', 4.5),
    ('D secondary on input fill', '#A8B4CE', '#1C2842', 4.5),
    ('D primary text on surface', '#8AB4FF', '#131C31', 4.5),
    ('D onPrimary on primary', '#0A1E4A', '#8AB4FF', 4.5),
    ('D error on surface', '#F97066', '#131C31', 4.5),
    ('D onPrimaryContainer', '#DBE6FF', '#284B8F', 4.5),
    ('D snackbar text', '#131C31', '#E7ECF6', 4.5),
    # ── Dark ── icons/borders (>= 3)
    ('D input border vs fill', '#6A7CA5', '#1C2842', 3.0),
    ('D input border vs surface', '#6A7CA5', '#131C31', 3.0),
    ('D prio low flag', '#34D399', '#131C31', 3.0),
    ('D prio medium flag', '#FBBF24', '#131C31', 3.0),
    ('D prio high flag', '#FB923C', '#131C31', 3.0),
    ('D prio urgent flag', '#F87171', '#131C31', 3.0),
    ('D warning star', '#FBBF24', '#131C31', 3.0),
    ('D tertiary dot', '#2DD4BF', '#131C31', 3.0),
    # ── Glass chrome (effective blends over the wash)
    ('L text on glass chrome', '#101828', '#EFF3FA', 4.5),
    ('D text on glass chrome', '#E7ECF6', '#121A2D', 4.5),
]


def main() -> int:
    failures = 0
    for name, fg, bg, need in PAIRS:
        r = ratio(fg, bg)
        ok = r >= need
        failures += 0 if ok else 1
        print(f"{'OK  ' if ok else 'FAIL'} {r:5.2f} (need {need})  {name}: {fg} on {bg}")
    print(f'\nFAILURES: {failures}')
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())

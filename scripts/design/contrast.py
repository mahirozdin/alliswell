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


# (name, fg, bg, minimum) — "Liquid Glass v2" palette (design round 8).
# Effective backgrounds model the veil/glass tint blended over the aurora
# wash (worst-case colorful sample under the layer): L background = #F5F9FF
# @58% over #E3EDFF, L glass = #F6F9FF@74% over a saturated wash sample
# #D6E5FF; D background = #0A102A@48% over #0C1436, D glass = #111A38@72%
# over #101A40.
PAIRS = [
    # ── Light ── text (>= 4.5)
    ('L body on background', '#0F1B2E', '#EDF4FF', 4.5),
    ('L body on surface', '#0F1B2E', '#FFFFFF', 4.5),
    ('L secondary on surface', '#44536F', '#FFFFFF', 4.5),
    ('L secondary on input fill', '#44536F', '#E7EEFA', 4.5),
    ('L onPrimary on primary', '#FFFFFF', '#0A5CFF', 4.5),
    ('L onSecondary on secondary', '#FFFFFF', '#5A50E0', 4.5),
    ('L link on background', '#0B54D0', '#EDF4FF', 4.5),
    ('L error on surface', '#D70015', '#FFFFFF', 4.5),
    ('L onPrimaryContainer', '#0A3FBF', '#D6E5FF', 4.5),
    ('L onSecondaryContainer', '#3A32A8', '#E4E1FF', 4.5),
    ('L onErrorContainer', '#99000F', '#FFE3E0', 4.5),
    ('L success on surface', '#0D7A33', '#FFFFFF', 4.5),
    ('L onTertiary on tertiary', '#FFFFFF', '#0C7D6C', 4.5),
    ('L snackbar text', '#EFF3FA', '#1D2739', 4.5),
    # ── Light ── icons/borders (>= 3)
    ('L input border vs fill', '#63789E', '#E7EEFA', 3.0),
    ('L input border vs surface', '#63789E', '#FFFFFF', 3.0),
    ('L prio low flag', '#0F9D46', '#FFFFFF', 3.0),
    ('L prio medium flag', '#C77700', '#FFFFFF', 3.0),
    ('L prio high flag', '#E8500A', '#FFFFFF', 3.0),
    ('L prio urgent flag', '#E3261A', '#FFFFFF', 3.0),
    ('L warning star', '#C77700', '#FFFFFF', 3.0),
    ('L tertiary dot', '#0C7D6C', '#FFFFFF', 3.0),
    ('L primary icon on surface', '#0A5CFF', '#FFFFFF', 3.0),
    # ── Dark ── text (>= 4.5)
    ('D body on background', '#EAF0FD', '#0B1230', 4.5),
    ('D body on surface', '#EAF0FD', '#151F3C', 4.5),
    ('D secondary on surface', '#AAB6D6', '#151F3C', 4.5),
    ('D secondary on input fill', '#AAB6D6', '#1F2C51', 4.5),
    ('D primary text on surface', '#3E9BFF', '#151F3C', 4.5),
    ('D onPrimary on primary', '#04234E', '#3E9BFF', 4.5),
    ('D onSecondary on secondary', '#241B66', '#B9AFFF', 4.5),
    ('D error on surface', '#FF5147', '#151F3C', 4.5),
    ('D onPrimaryContainer', '#D9E8FF', '#1D4FA6', 4.5),
    ('D onSecondaryContainer', '#E6E1FF', '#3B3583', 4.5),
    ('D onErrorContainer', '#FFD9D5', '#7A1F18', 4.5),
    ('D success on surface', '#30D158', '#151F3C', 4.5),
    ('D onTertiary on tertiary', '#04352D', '#35D6C2', 4.5),
    ('D snackbar text', '#151F3C', '#EAF0FD', 4.5),
    # ── Dark ── icons/borders (>= 3)
    ('D input border vs fill', '#7186B5', '#1F2C51', 3.0),
    ('D input border vs surface', '#7186B5', '#151F3C', 3.0),
    ('D prio low flag', '#30D158', '#151F3C', 3.0),
    ('D prio medium flag', '#FFC400', '#151F3C', 3.0),
    ('D prio high flag', '#FF8A1E', '#151F3C', 3.0),
    ('D prio urgent flag', '#FF453A', '#151F3C', 3.0),
    ('D warning star', '#FFC400', '#151F3C', 3.0),
    ('D tertiary dot', '#35D6C2', '#151F3C', 3.0),
    # ── Glass chrome (effective blends over the wash)
    ('L text on glass chrome', '#0F1B2E', '#EEF4FF', 4.5),
    ('L variant text on glass', '#44536F', '#EEF4FF', 4.5),
    ('D text on glass chrome', '#EAF0FD', '#111A3A', 4.5),
    ('D variant text on glass', '#AAB6D6', '#111A3A', 4.5),
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

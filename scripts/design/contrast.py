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
    # OPH-199/DESIGN §23 Q8a — the quick-access colour dot carries its contrast
    # in a 1 px `outline` ring, because half the palette cannot clear 3:1 as a
    # bare fill and project colour is not even bounded to the palette. These
    # two pairs are the ring, on the surfaces the rail actually sits on.
    ('L quick dot ring on surface', '#63789E', '#FFFFFF', 3.0),
    ('L quick dot ring on glass', '#63789E', '#D6E5FF', 3.0),
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
    ('D quick dot ring on surface', '#7186B5', '#151F3C', 3.0),
    ('D quick dot ring on glass', '#7186B5', '#111A38', 3.0),
    ('D tertiary dot', '#35D6C2', '#151F3C', 3.0),
    # ── Glass chrome (effective blends over the wash)
    ('L text on glass chrome', '#0F1B2E', '#EEF4FF', 4.5),
    ('L variant text on glass', '#44536F', '#EEF4FF', 4.5),
    ('D text on glass chrome', '#EAF0FD', '#111A3A', 4.5),
    ('D variant text on glass', '#AAB6D6', '#111A3A', 4.5),
    # ── Completed rows (OPH-185, DESIGN §20 C2/C3). The calm treatment is
    # built from tokens precisely so it can be measured here; an `Opacity`
    # wrapper would have made these four pairs impossible to state.
    ('L done title on done row', '#44536F', '#F6F9FF', 4.5),
    ('L done body on done row', '#0F1B2E', '#F6F9FF', 4.5),
    ('D done title on done row', '#AAB6D6', '#121B36', 4.5),
    ('D done body on done row', '#EAF0FD', '#121B36', 4.5),
    # The filled check circle keeps its full-strength success fill: muting it
    # toward the surface would drop the check glyph below 3:1 (measured), and a
    # done row that cannot be read as done is not calm, it is broken.
    # EE-097 — the SLA badge on a ticket card. Registered by NAME even where
    # the colour pair already appears above, because DESIGN §7.1's failure mode
    # is a surface nobody listed: a chip whose colour changes must break a line
    # that says "chip", not silently inherit somebody else's pass.
    #
    # The amber state is a MARK, not a sentence, and the numbers are why:
    # `warning` #C77700 on the light surface measures 3.46 — enough for a 3.0
    # icon and short of the 4.5 a label needs. So the warned label is drawn in
    # ordinary body colour and only the icon takes the accent.
    ('L SLA breach label on card', '#D70015', '#FFFFFF', 4.5),
    ('D SLA breach label on card', '#FF5147', '#151F3C', 4.5),
    ('L SLA met label on card', '#0D7A33', '#FFFFFF', 4.5),
    ('D SLA met label on card', '#30D158', '#151F3C', 4.5),
    ('L SLA warning mark on card', '#C77700', '#FFFFFF', 3.0),
    ('D SLA warning mark on card', '#FFC400', '#151F3C', 3.0),
    ('L SLA countdown label on card', '#44536F', '#FFFFFF', 4.5),
    ('D SLA countdown label on card', '#AAB6D6', '#151F3C', 4.5),
    # EE-098 — the SLA dashboard's headline figure, on a card. Named for the
    # same reason the chip's pairs are: a surface nobody listed is the gate's
    # blind spot, and this number is the one a customer is shown.
    ('L SLA compliance below target', '#D70015', '#FFFFFF', 4.5),
    ('D SLA compliance below target', '#FF5147', '#151F3C', 4.5),
    ('L SLA compliance on target', '#0D7A33', '#FFFFFF', 4.5),
    ('D SLA compliance on target', '#30D158', '#151F3C', 4.5),
    ('L SLA dashboard row label', '#0F1B2E', '#FFFFFF', 4.5),
    ('D SLA dashboard row label', '#EAF0FD', '#151F3C', 4.5),
    ('L check glyph on success fill', '#FFFFFF', '#0D7A33', 3.0),
    ('D check glyph on success fill', '#052E1B', '#30D158', 3.0),
    ('L success fill on done row', '#0D7A33', '#F6F9FF', 3.0),
    ('D success fill on done row', '#30D158', '#121B36', 3.0),
    # ── Swipe-to-delete action pane (OPH-184, DESIGN §19 D5)
    ('L delete label on error pane', '#FFFFFF', '#D70015', 4.5),
    ('D delete label on error pane', '#450603', '#FF5147', 4.5),
    # ── Rendered markdown (round 17, OPH-247, DESIGN §29 D7/D9)
    # The code panel is `surfaceContainerHighest`, which both themes define
    # outright — so these are exact backgrounds, not blended estimates.
    ('L code body on code panel', '#0F1B2E', '#DEE8F8', 4.5),
    ('D code body on code panel', '#EAF0FD', '#26345E', 4.5),
    ('L code keyword', '#8B2FA8', '#DEE8F8', 4.5),
    ('L code string', '#0A6E3D', '#DEE8F8', 4.5),
    ('L code comment', '#5A6782', '#DEE8F8', 4.5),
    ('L code number', '#9A4A05', '#DEE8F8', 4.5),
    ('L code name', '#0B54D0', '#DEE8F8', 4.5),
    ('L code meta', '#00636E', '#DEE8F8', 4.5),
    ('D code keyword', '#E5A8FF', '#26345E', 4.5),
    ('D code string', '#7EE8A8', '#26345E', 4.5),
    ('D code comment', '#A8B6D4', '#26345E', 4.5),
    ('D code number', '#FFC07A', '#26345E', 4.5),
    ('D code name', '#8FC4FF', '#26345E', 4.5),
    ('D code meta', '#5FE0F0', '#26345E', 4.5),
    # Table header row (`surfaceContainerLow`).
    ('L table header ink', '#0F1B2E', '#F6F9FF', 4.5),
    ('D table header ink', '#EAF0FD', '#121B36', 4.5),
    # GFM alerts (DESIGN §29). The five types reuse EXISTING roles rather than
    # growing the palette. The backgrounds below are not estimates: they are
    # the accent composited at **10%** over `surface` (#FFFFFF light,
    # #151F3C dark) — the exact value `md_callout.dart` paints.
    #
    # The split matters and was measured. The accent colours the ICON and the
    # left edge (>= 3:1); the TEXT stays `onSurface` (>= 4.5:1). Colouring the
    # body text with the accent fails outright — `warning` #C77700 on its own
    # tint is 2.96 — which is what `AwTokens.warning`'s own doc comment has
    # said all along: it is an ICON colour. 10% rather than 14% for the same
    # reason: at 14% the light warning ICON lands on 2.96 too.
    ('L alert note text on tint', '#0F1B2E', '#E6EFFF', 4.5),
    ('L alert note icon on tint', '#0A5CFF', '#E6EFFF', 3.0),
    ('L alert tip text on tint', '#0F1B2E', '#E7F2EB', 4.5),
    ('L alert tip icon on tint', '#0D7A33', '#E7F2EB', 3.0),
    ('L alert important text on tint', '#0F1B2E', '#EEEEFC', 4.5),
    ('L alert important icon on tint', '#5A50E0', '#EEEEFC', 3.0),
    ('L alert warning text on tint', '#0F1B2E', '#F9F1E6', 4.5),
    ('L alert warning icon on tint', '#C77700', '#F9F1E6', 3.0),
    ('L alert caution text on tint', '#0F1B2E', '#FBE6E8', 4.5),
    ('L alert caution icon on tint', '#D70015', '#FBE6E8', 3.0),
    ('D alert note text on tint', '#EAF0FD', '#192B50', 4.5),
    ('D alert note icon on tint', '#3E9BFF', '#192B50', 3.0),
    ('D alert tip text on tint', '#EAF0FD', '#18313F', 4.5),
    ('D alert tip icon on tint', '#30D158', '#18313F', 3.0),
    ('D alert important text on tint', '#EAF0FD', '#252D50', 4.5),
    ('D alert important icon on tint', '#B9AFFF', '#252D50', 3.0),
    ('D alert warning text on tint', '#EAF0FD', '#2C3036', 4.5),
    ('D alert warning icon on tint', '#FFC400', '#2C3036', 3.0),
    ('D alert caution text on tint', '#EAF0FD', '#2C243D', 4.5),
    ('D alert caution icon on tint', '#FF5147', '#2C243D', 3.0),

    # ── Note colours (OPH-259, DESIGN §33 R4) ──
    # Stored by NAME and resolved per theme, which is the whole point: no single
    # hex clears 4.5 against both #FFFFFF and #151F3C (measured: 0 of 18
    # candidates), and no single highlight fill carries both body inks — those
    # two ratios multiply to at most 21, so the best case is ~4.6 at one exact
    # lightness, and mid-grey #808080 measured 4.37/3.46 and failed both.
    # Text: against the surface each theme actually paints.
    ('L note text red', '#B3261E', '#FFFFFF', 4.5),
    ('L note text orange', '#A8410A', '#FFFFFF', 4.5),
    ('L note text green', '#1B6E2F', '#FFFFFF', 4.5),
    ('L note text teal', '#0F6E6E', '#FFFFFF', 4.5),
    ('L note text blue', '#0B54D0', '#FFFFFF', 4.5),
    ('L note text purple', '#6D28D9', '#FFFFFF', 4.5),
    ('L note text pink', '#9D174D', '#FFFFFF', 4.5),
    ('L note text grey', '#4A5568', '#FFFFFF', 4.5),
    ('D note text red', '#FF9E96', '#151F3C', 4.5),
    ('D note text orange', '#FFB07A', '#151F3C', 4.5),
    ('D note text green', '#6FE08A', '#151F3C', 4.5),
    ('D note text teal', '#5FD9D9', '#151F3C', 4.5),
    ('D note text blue', '#8FBEFF', '#151F3C', 4.5),
    ('D note text purple', '#C4A7FF', '#151F3C', 4.5),
    ('D note text pink', '#FF9EC4', '#151F3C', 4.5),
    ('D note text grey', '#AEB9D4', '#151F3C', 4.5),
    # Highlights: the BODY ink that will sit on the fill, not the fill itself.
    ('L note mark yellow', '#0F1B2E', '#FFF3A3', 4.5),
    ('L note mark green', '#0F1B2E', '#CDEFD4', 4.5),
    ('L note mark blue', '#0F1B2E', '#CFE3FF', 4.5),
    ('L note mark pink', '#0F1B2E', '#FFD6E4', 4.5),
    ('L note mark purple', '#0F1B2E', '#E6D9FF', 4.5),
    ('L note mark grey', '#0F1B2E', '#DFE4EC', 4.5),
    ('D note mark yellow', '#EAF0FD', '#5A4A12', 4.5),
    ('D note mark green', '#EAF0FD', '#1E4A2C', 4.5),
    ('D note mark blue', '#EAF0FD', '#1B3A63', 4.5),
    ('D note mark pink', '#EAF0FD', '#5A2340', 4.5),
    ('D note mark purple', '#EAF0FD', '#3B2A66', 4.5),
    ('D note mark grey', '#EAF0FD', '#333B52', 4.5),

    # ── Shared raised surfaces (round 18 follow-up, Epic 24 + OPH-269) ──
    # `surfaceContainerHigh` (#E7EEFA / #1F2C51) was already here, but only ever
    # as "input fill" — so the OTHER things drawn on it were outside the guard:
    # the external-document band, `MdToolbar`, `MdSlashMenu`, the find/replace
    # bar and the export sheet. A surface is not measured because its name
    # appears once; it is measured when the pairs somebody actually PAINTS on it
    # appear. These are exact colours (opaque `Color`s), not blended estimates,
    # so OPH-247's "hand-invented ground" trap does not apply.
    ('L body on raised container', '#0F1B2E', '#E7EEFA', 4.5),
    ('D body on raised container', '#EAF0FD', '#1F2C51', 4.5),
    # find/replace puts a TextButton on this surface.
    ('L link on raised container', '#0B54D0', '#E7EEFA', 4.5),
    ('D link on raised container', '#3E9BFF', '#1F2C51', 4.5),
    # `surfaceContainerHighest` beyond the code panel: file tiles, the command
    # palette's selected row. Secondary ink, not measured here before.
    ('L variant ink on highest container', '#44536F', '#DEE8F8', 4.5),
    ('D variant ink on highest container', '#AAB6D6', '#26345E', 4.5),

    # ── Note conflict banner (OPH-269, DESIGN §35) ──
    # This whole block exists because the banner shipped with a real failure
    # nobody could see: `tertiaryContainer` was in NO pair, so the surface was
    # not green, it was unmeasured. The banner's TEXT was checked by hand and
    # passed (7.71 / 6.68) — but its four ACTION BUTTONS inherited the global
    # `tokens.link`, which lands on **2.79:1** over the dark container. Fixed in
    # `note_conflict_banner.dart` by taking the container's own ink; both the
    # ink and the action label are pinned below so the next surface added to
    # this banner cannot repeat it.
    # EE-068 — the assignee avatar (item 9's round icons under a task card).
    #
    # The roster palette ships one colour per person and its own comment claims
    # every entry clears contrast in both themes. Measured with the function
    # above, it does not: white initials fail 4.5 on five of the ten fills
    # (worst #CA8A04 at 2.94), picking the better ink per fill still leaves
    # #0284C7 at 4.22, and as a BARE SHAPE the fills fail 3:1 on both surfaces
    # (2.94 light, 2.58 dark). So the avatar takes OPH-199's answer for an
    # arbitrary colour: the colour is a 20% TINT, a neutral `outline` ring
    # carries the shape, and the initials are ordinary surface ink.
    #
    # The two ink rows below are the WORST tint of the ten in each theme —
    # #DC2626 on light, #CA8A04 on dark — so nothing in the palette can be
    # worse than what is pinned here.
    ('L avatar initials on worst tint', '#0F1B2E', '#F8D4D4', 4.5),
    ('D avatar initials on worst tint', '#EAF0FD', '#393431', 4.5),
    ('L avatar ring on surface', '#63789E', '#FFFFFF', 3.0),
    ('D avatar ring on surface', '#7186B5', '#151F3C', 3.0),
    # EE-077 — the unread badge. Small, coloured, and carrying a NUMBER, which
    # is the exact shape of the thing that passes an eye and fails a
    # measurement. E07 learned that twice on the avatar directly above: half
    # the roster palette could not carry white initials, and the comment above
    # that code said it could.
    #
    # The badge takes no hand-picked red. It uses the scheme's own error/onError
    # pair, so the number is measured here and nowhere else has to be trusted.
    ('L unread badge label', '#FFFFFF', '#D70015', 4.5),
    ('D unread badge label', '#450603', '#FF5147', 4.5),
    # The unread DOT is a bare shape with no text in it, so 3:1 — the same
    # threshold the avatar ring takes, for the same reason.
    ('L unread dot on surface', '#0A5CFF', '#FFFFFF', 3.0),
    ('D unread dot on surface', '#3E9BFF', '#151F3C', 3.0),
    # The tombstone avatar: somebody who left the unit but still holds the
    # assignment. Neutral fill, so it is a plain ink-on-container pair.
    ('L former-member avatar ink', '#44536F', '#DEE8F8', 4.5),
    ('D former-member avatar ink', '#AAB6D6', '#26345E', 4.5),
    ('L former-member avatar ring', '#63789E', '#DEE8F8', 3.0),
    ('D former-member avatar ring', '#7186B5', '#26345E', 3.0),
    ('L banner ink on tertiary container', '#084F44', '#BFF2E6', 4.5),
    ('D banner ink on tertiary container', '#BDF6EC', '#0E5B4F', 4.5),
    ('L banner action label', '#084F44', '#BFF2E6', 4.5),
    ('D banner action label', '#BDF6EC', '#0E5B4F', 4.5),
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

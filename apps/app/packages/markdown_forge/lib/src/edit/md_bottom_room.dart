/// Empty space under the last line, and why a document needs it.
///
/// Two different failures wear the same face, and only one of them is about
/// comfort.
///
/// ## Reach — the last lines are not awkward, they are gone
///
/// A host may float its chrome over the document: AllisWell's shell uses
/// `Scaffold(extendBody: true)` with a floating glass bar, so the body extends
/// UNDER it and the final lines of a long note cannot be read or tapped at all.
/// Flutter reports that overlap to the body as `MediaQuery.padding.bottom`,
/// which makes it the one part of this number that is not a preference —
/// without it, content is unreachable, which is a defect rather than a taste.
///
/// ## Aim — the end of a document is a bad tap target
///
/// Even clear of the chrome, the last line of a scrolled document sits at the
/// very bottom edge of the screen: a ~20 px strip under the thumb's own knuckle.
/// Every editor that is pleasant to write in leaves room to scroll PAST the
/// end. VS Code calls it `editor.scrollBeyondLastLine` and ships it **on**;
/// iA Writer and Ulysses take the same idea to its limit with typewriter
/// scrolling, which keeps the caret near the middle of the screen and therefore
/// implies at least half a viewport of trailing room. Obsidian users reach for
/// a `padding-bottom: 50vh` snippet for exactly this reason.
///
/// So the reach is a FRACTION OF THE VIEWPORT rather than a constant: it has to
/// mean the same thing on a phone and on a desktop, and — because the caller
/// measures the real box — it shrinks on its own when a keyboard takes half the
/// screen, which is the moment trailing room is least wanted and viewport is
/// most precious.
///
/// ## The part that is easy to get wrong
///
/// The room has to be **scrollable content**, not a fixed inset. A `TextField`
/// with `expands: true` scrolls inside itself, so `contentPadding.bottom` would
/// permanently shrink the visible text area instead of letting you scroll
/// further — the blank strip would sit there in every state, and the end of the
/// document would still be pinned to the bottom of a shorter box. `SourceMode`
/// therefore puts the field inside a scroll view and the room after it.
///
/// And blank space that places no caret is a dead affordance (DESIGN §22): the
/// room is wrapped in a tap target that puts the caret at the end of the
/// document, which is what Apple Notes does and what makes "tap below the text
/// to keep writing" work at all.
library;

import 'package:flutter/widgets.dart';

import '../seams.dart';

/// How much of the viewport the editor leaves after the last line.
///
/// Half a screen is the figure the reports and the prior art agree on; the
/// value is a shade under it so the room plus the host's chrome still leaves
/// the majority of the box to the document.
const double kMdEditorReachFraction = 0.45;

/// Reading needs less: there is no caret to place, only a last paragraph that
/// should not have to be read off the bottom edge of the screen.
const double kMdReadingReachFraction = 0.2;

/// Never more than this share of the viewport, whatever the fraction asks for.
/// A document whose blank tail outweighs its text has a scrollbar that lies.
const double _kMaxShare = 0.6;

/// The host chrome floating over the document — 0 where nothing floats.
double mdChromeInset(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom;

/// Trailing room for a document laid out in a [viewportHeight]-tall box.
///
/// [reachFraction] is the scroll-past-end share; pass 0 for a surface that only
/// needs to clear the chrome.
double mdBottomRoom({
  required double viewportHeight,
  required double chromeInset,
  required double reachFraction,
  double gap = MdSpace.x6,
}) {
  if (!viewportHeight.isFinite || viewportHeight <= 0) {
    return chromeInset + gap;
  }
  final reach = viewportHeight * reachFraction;
  final room = chromeInset + gap + reach;
  return room.clamp(0.0, viewportHeight * _kMaxShare);
}

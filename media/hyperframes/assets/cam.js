/**
 * Camera framing for a full-frame screenshot plate (ADR-0061).
 * focus(scale, cx, cy) returns the GSAP x/y/scale that centres the point
 * (cx, cy) of a W×H plate in a W×H frame, clamped so the plate always covers
 * the frame. Coordinates are in plate pixels at scale 1.
 */
window.focusOn = function focusOn(scale, cx, cy, W, H) {
  const w = W || 1600;
  const h = H || 1000;
  let x = w / 2 - scale * cx;
  let y = h / 2 - scale * cy;
  x = Math.min(0, Math.max(w - w * scale, x));
  y = Math.min(0, Math.max(h - h * scale, y));
  return { scale, x, y };
};

// Landmark coaching only; this is not an identity or anti-spoofing verdict.
export function faceMetrics(result, aspect = 4 / 3) {
  const faces = result?.faceLandmarks ?? [];
  const sample = {count:faces.length, centered:false, blink:0, yaw:0};
  if (faces.length !== 1) return sample;
  const points = faces[0], left = points[33], right = points[263], nose = points[1];
  if (!left || !right || !nose || !Number.isFinite(aspect) || aspect <= 0) return sample;
  // Project onto the eye axis in image pixels. Horizontal-only measurements
  // misinterpret head tilt as a turn, especially in portrait camera streams.
  const dx = (right.x-left.x)*aspect, dy = right.y-left.y;
  const squared = dx*dx + dy*dy;
  if (squared < .001) return sample;
  sample.yaw = (((nose.x-(left.x+right.x)/2)*aspect)*dx +
    (nose.y-(left.y+right.y)/2)*dy) / squared;
  let minX=1, maxX=0, minY=1, maxY=0;
  for (const point of points) {
    if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) return sample;
    minX=Math.min(minX,point.x); maxX=Math.max(maxX,point.x);
    minY=Math.min(minY,point.y); maxY=Math.max(maxY,point.y);
  }
  // Use the whole face size: eye distance shrinks during a valid head turn.
  sample.centered = maxX-minX > .18 && maxY-minY > .25 &&
    maxX-minX < .9 && minX > .015 && maxX < .985 && minY > .01 && maxY < .99;
  const scores = Object.fromEntries((result.faceBlendshapes?.[0]?.categories ?? [])
    .map(c => [c.categoryName,c.score]));
  // Missing blendshapes cannot supply evidence that the eyes opened.
  // Mean, not min: the model scores the two eyes unevenly (glasses, side
  // light, a slight turn), and min let the weaker eye veto a real blink.
  sample.blink = Number.isFinite(scores.eyeBlinkLeft) && Number.isFinite(scores.eyeBlinkRight)
    ? (scores.eyeBlinkLeft+scores.eyeBlinkRight)/2 : NaN;
  return sample;
}

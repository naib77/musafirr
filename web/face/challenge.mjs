// Capture coaching, not a security verdict. All evidence still needs admin review.
export class FaceChallenge {
  constructor(actions) {
    if (!Array.isArray(actions) || actions.length !== 3 || new Set(actions).size !== 3 ||
        actions.some(a => !['blink', 'left', 'right'].includes(a))) throw Error('Invalid challenge');
    this.actions = actions;
    this.reset();
  }
  reset() {
    this.index = 0; this.phase = 'neutral'; this.since = null; this.lastTime = null;
    this.missingSince = null; this.baseline = null; this.neutralSum = 0; this.neutralCount = 0;
  }
  get complete() { return this.index === this.actions.length; }
  get instruction() {
    if (this.complete) return 'Capture complete';
    if (this.phase === 'neutral') return 'Look straight ahead';
    if (this.phase === 'return') return this.actions[this.index] === 'blink' ? 'Open your eyes' : 'Look straight ahead again';
    return {blink: 'Blink naturally', left: 'Slowly turn your head left', right: 'Slowly turn your head right'}[this.actions[this.index]];
  }
  update({count, centered = true, blink = 0, yaw = 0}, time) {
    if (!Number.isFinite(time) || !Number.isFinite(blink) || !Number.isFinite(yaw)) { this.reset(); return; }
    if (this.lastTime !== null && (time <= this.lastTime || time - this.lastTime > 800)) this.reset();
    this.lastTime = time;
    if (count > 1) { this.reset(); return; }
    if (count !== 1 || !centered) {
      this.missingSince ??= time;
      // A dropped detection cannot finish a gesture or preserve its hold.
      this.since = null; this.neutralSum = 0; this.neutralCount = 0;
      this.phase = 'neutral';
      if (time - this.missingSince >= 400) this.reset();
      return;
    }
    if (this.missingSince !== null && time - this.missingSince >= 400) this.reset();
    this.missingSince = null;
    if (this.complete) return;
    const relativeYaw = yaw - (this.baseline ?? 0);
    const neutral = Math.abs(relativeYaw) < (this.baseline === null ? .18 : .10) && blink < 0.3;
    const action = this.actions[this.index];
    let matches = false, hold = 220;
    if (this.phase === 'neutral' || this.phase === 'return') matches = neutral;
    else if (action === 'blink') { matches = blink > 0.65 && Math.abs(relativeYaw) < 0.15; hold = 0; }
    else {
      // Enter at a clear turn, then tolerate small tracking fluctuations while
      // holding it. Returning toward center still breaks the hold immediately.
      const threshold = this.since === null ? .20 : .16;
      matches = action === 'left' ? relativeYaw > threshold : relativeYaw < -threshold;
    }
    if (!matches) { this.since = null; this.neutralSum = 0; this.neutralCount = 0; return; }
    if (this.phase === 'neutral' && this.baseline === null) {
      this.neutralSum += yaw; this.neutralCount++;
    }
    this.since ??= time;
    if (time - this.since < hold) return;
    this.since = null;
    if (this.phase === 'neutral') {
      this.baseline ??= this.neutralSum / this.neutralCount;
      this.phase = 'action';
    }
    else if (this.phase === 'action') { this.phase = 'return'; }
    else { this.index++; this.phase = 'neutral'; }
  }
}

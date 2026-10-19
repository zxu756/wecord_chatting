/** Counts events per key in a sliding window kept in memory. */
export class WindowLimiter {
  #hits = new Map<string, { start: number; count: number }>();

  constructor(
    private readonly limit: number,
    private readonly windowMs: number,
    private readonly maxKeys = 5000,
  ) {}

  /** Records one hit; false when [key] is over the limit. */
  hit(key: string, nowMs: number): boolean {
    const entry = this.#hits.get(key);
    if (!entry || nowMs - entry.start >= this.windowMs) {
      if (this.#hits.size >= this.maxKeys) this.#sweep(nowMs);
      this.#hits.set(key, { start: nowMs, count: 1 });
      return true;
    }
    entry.count++;
    return entry.count <= this.limit;
  }

  /** Whether [key] has used up its hits in the current window. */
  isBlocked(key: string, nowMs: number): boolean {
    const entry = this.#hits.get(key);
    return entry !== undefined && nowMs - entry.start < this.windowMs &&
      entry.count >= this.limit;
  }

  retryAfterSeconds(key: string, nowMs: number): number {
    const entry = this.#hits.get(key);
    if (!entry) return 1;
    return Math.max(1, Math.ceil((entry.start + this.windowMs - nowMs) / 1000));
  }

  #sweep(nowMs: number) {
    for (const [key, entry] of this.#hits) {
      if (nowMs - entry.start >= this.windowMs) this.#hits.delete(key);
    }
    // Still full of live keys: start over rather than grow without bound.
    if (this.#hits.size >= this.maxKeys) this.#hits.clear();
  }
}

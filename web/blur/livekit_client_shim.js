// Stands in for livekit-client where @livekit/track-processors asks it for a logger.
const noop = () => {};

export function getLogger(name) {
  return {
    name,
    setLevel: noop,
    setDefaultLevel: noop,
    getLevel: () => 2,
    methodFactory: (method) => (console[method] ?? console.log).bind(console),
    trace: noop,
    debug: noop,
    info: noop,
    log: noop,
    warn: console.warn.bind(console),
    error: console.error.bind(console),
  };
}

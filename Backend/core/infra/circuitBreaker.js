const { env } = require("../../all_imports");

const circuits = new Map();

function getState(name) {
  const existing = circuits.get(name);
  if (existing) {
    return existing;
  }
  const fresh = {
    failures: 0,
    openUntil: 0,
  };
  circuits.set(name, fresh);
  return fresh;
}

function canExecute(name) {
  const state = getState(name);
  return {
    allowed: state.openUntil <= Date.now(),
    retryAfterMs: Math.max(state.openUntil - Date.now(), 0),
  };
}

function onSuccess(name) {
  const state = getState(name);
  state.failures = 0;
  state.openUntil = 0;
}

function onFailure(name) {
  const state = getState(name);
  state.failures += 1;
  if (state.failures >= env.aiCircuitBreakerThreshold) {
    state.openUntil = Date.now() + env.aiCircuitBreakerCooldownMs;
  }
}

const resetCircuitState = () => {
  circuits.clear();
};

module.exports = {
  canExecute,
  onSuccess,
  onFailure,
  resetCircuitState,
};

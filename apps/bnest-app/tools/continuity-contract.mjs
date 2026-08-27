export class ResumableSessionStore {
  constructor() {
    this.sessions = new Map();
  }

  apply(sessionId, commandId, payload) {
    const session = this.#session(sessionId);
    const duplicate = session.commands.get(commandId);
    if (duplicate) return duplicate;

    const event = {
      commandId,
      payload: structuredClone(payload),
      sequence: session.events.length + 1,
    };
    session.events.push(event);
    session.commands.set(commandId, event);
    return structuredClone(event);
  }

  resume(sessionId, lastAcknowledgedSequence) {
    const session = this.#session(sessionId);
    if (
      !Number.isInteger(lastAcknowledgedSequence) ||
      lastAcknowledgedSequence < 0 ||
      lastAcknowledgedSequence > session.events.length
    )
      throw new Error("Acknowledged sequence is outside the session history");

    return {
      sessionId,
      version: session.events.length,
      snapshot: structuredClone(session.events),
      events: structuredClone(session.events.slice(lastAcknowledgedSequence)),
    };
  }

  #session(sessionId) {
    if (!/^[a-z0-9-]+$/u.test(sessionId))
      throw new Error("Session identifier is invalid");
    if (!this.sessions.has(sessionId))
      this.sessions.set(sessionId, { commands: new Map(), events: [] });
    return this.sessions.get(sessionId);
  }
}

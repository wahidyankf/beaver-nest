# Business Requirements

## Goal

Prevent repository-owned development and release work from materially increasing host-restart risk while preserving the routed household service.

## Roles

- **Maintainer:** runs normal Nx commands and receives clear defer/shed outcomes.
- **Repository guard:** admits, observes, serializes, and sheds only processes it owns.
- **Routed service:** remains healthy and outside development process control.

## Required Outcomes

- Compute-heavy Nx work cannot start during unsafe host pressure or overlap another guarded heavy session.
- A guarded ephemeral task stops gracefully during sustained warning or immediate critical pressure.
- Development serve sheds later than ephemeral work; production, Caddy, and unrelated applications are never signalled.
- Managed release and development use the same correctly named measurements and bounded evidence lifecycle.
- Codex, Claude Code, OpenCode, and maintainers reach the same repository rule.

## Non-goals

- A host-wide daemon, controlling unrelated applications, or proving all future restarts impossible.
- Treating undocumented numeric thresholds as Apple, Node, or Erlang standards.
- Changing public Bnest product behavior or storage data.

## Risks and Controls

- **False safety:** fail closed on essential measurement errors and use OS pressure/compressor availability as hard signals.
- **Data corruption:** never shed transactional storage or recovery commands after admission.
- **Service interruption:** address only verified child process groups and continuously check routed health during delivery.
- **Evidence growth:** private bounded retention and safe aggregate fields only.

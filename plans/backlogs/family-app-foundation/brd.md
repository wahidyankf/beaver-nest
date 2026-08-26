# Business Requirements Document

## Business Goal

Provide approved family members with a continuously available private application for shared information and document-assisted activities, while keeping personal data recoverable and operational control bounded.

## Rationale

The current Bnest experiences are local-first and browser-persisted. They do not provide authenticated family identity, cross-device shared records, server-side document storage, durable job state, or release-time data recovery. Those gaps prevent the application from safely becoming a dependable shared family service.

## Affected Roles

- **Family member:** uses private shared activities and submits supported documents.
- **Family administrator:** manages access and performs explicit recovery operations.
- **Maintainer:** evolves and releases the application without exposing live family data or arbitrary host control.

## Required Business Outcomes

- Only approved family members can access protected activities and records.
- Shared data and documents survive application restarts and releases.
- Document work exposes understandable progress and recoverable failure states.
- A permitted administrator can perform bounded recovery actions.
- A faulty release can be reverted without losing accepted family data.

## Success Measures

Success is demonstrated by observable acceptance evidence rather than a fabricated adoption target:

1. An authorized family member reaches the app through its stable private route and an unauthorized visitor cannot access protected content.
2. Shared data and documents remain available after restart and release exercises.
3. A document job reaches queued, running, complete, or failed state and preserves a useful result or error.
4. An administrator can recover a failed worker without gaining a shell or unrestricted process launcher.
5. A tested rollback restores the previous application release while preserving production data.

## Business Non-Goals

- Public internet availability.
- General-purpose document automation or arbitrary uploaded executables.
- Enterprise identity administration, multi-tenant billing, or public self-registration.
- Using live family data as development or test fixtures.

## Business Risks and Mitigations

| Risk                                      | Mitigation direction                                                                                 |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Private information becomes exposed       | Keep access private, enforce application authorization, and apply least privilege at every boundary. |
| Releases corrupt or lose family data      | Require tested backups, explicit migrations, health checks, and rollback before risky releases.      |
| Document processing becomes host control  | Accept a fixed job schema and invoke only allowlisted executables without a shell.                   |
| A broad foundation delays useful delivery | Ship independently recoverable vertical slices and split the plan if a slice cannot remain bounded.  |

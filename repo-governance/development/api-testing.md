# API Testing

Apply this standard to every change that can affect an externally reachable API, including REST endpoints, GraphQL queries and mutations, webhooks, RPC-style HTTP operations, streaming responses, and subscriptions.

## Automated Proof

API behaviour follows the repository [BDD](behaviour-driven-development.md), [test boundaries](quality-gates.md#test-boundaries), 99% coverage, and [test-data iron rule](test-identities.md#iron-rule).

- Unit tests prove business rules, validation, authorization decisions, mapping, and error behaviour through injected dependencies without OS or network access.
- Integration tests exercise routing, request parsing, schema validation, serialization, middleware, and real isolated local stores, either in-process or through a loopback listener the test starts, owns, and stops. They never observe the routed public origin.
- E2E tests exercise representative operations through the exact served public origin. They prove transport configuration and cross-boundary behaviour that narrower layers cannot.
- Contract assertions cover request method or operation, path, headers, content type, payload or variables, response status, response headers, body shape, declared errors, and observable side effects.
- Cover success, malformed or invalid input, expected failure, and authentication or authorization boundaries when applicable. Test idempotency and duplicate delivery for operations that promise them.
- For GraphQL, assert both the HTTP contract and the `data`/`errors` envelope. HTTP `200` alone never proves GraphQL success.

Use consumer or schema contract tests when another maintained component depends on a declared API contract. Generated schema or client checks supplement, never replace, behavioural tests.

## Mandatory Manual Curl

Before completing any API-affecting change, manually invoke every affected HTTP operation with `curl` against the exact isolated served origin. This required evidence is mandatory even when unit, integration, contract, and E2E tests pass.

- For REST, exercise the affected method, path, headers, and payload; verify status, content type, response contract, and independently observed side effects.
- For GraphQL, send each affected named query or mutation with representative variables and verify HTTP status, `data`, `errors`, and the operation outcome.
- Exercise a successful request and each materially changed validation or error path. When authentication or authorization applies, use authorized and unauthenticated or unauthorized synthetic identities and confirm both outcomes.
- Never use production users, data, credentials, cookies, tokens, or runtime roots. Start with validated isolated test state and clean it under the test-identity standard.
- For subscriptions, WebSockets, or streams, use `curl` for the meaningful HTTP handshake or initial response, then use a protocol-capable client for lifecycle evidence. A handshake alone is insufficient.

Record the redacted command shape, exact origin, operation, observed status and response shape, side-effect result, and pass/fail in the delivery evidence. Never record secrets or private payloads. A plan that can affect an API must include this as a `delivery.md` task. If an assessed change cannot affect an API, record `API impact: none`; do not run an unrelated probe.

Manual confirmation supplements automated layers and does not authorize bypassing a failed gate. Run repository commands through Nx; invoke `curl` directly only for this required public-boundary observation.

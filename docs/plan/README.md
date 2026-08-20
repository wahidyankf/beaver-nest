# Planning Documents

These documents define the intended system before implementation begins.

| Document | Purpose |
| --- | --- |
| [Problem statement](problem-statement.md) | User needs, constraints, and success criteria |
| [Architecture](architecture.md) | System boundaries, data flow, and security model |
| [Testing strategy](testing.md) | Test layers and release confidence |
| [Operations](operations.md) | Development-in-production model, recovery, and control boundaries |

## Chosen direction

The initial direction is a private, self-hosted **Phoenix LiveView** application running on an always-on home host. It uses Elixir/OTP supervision, Postgres, supervised Python document-processing workers, Playwright browser E2E tests, and Tailscale Serve for private HTTPS access.

This is a planning decision, not an implementation commitment. Revisit it after the first vertical slice if the product needs contradict it.

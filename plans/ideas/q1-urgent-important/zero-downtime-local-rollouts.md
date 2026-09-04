# Zero-Downtime Local Rollouts

Make a stable, repeatable Bnest promotion path so working-tree changes cannot take the tailnet application offline. Provenance: execution learning captured 2026-08-26 during `bnest-centralized-data` delivery.

## Problem / Context

The active Phoenix code reloader detected changed dependency and configuration inputs and returned 500 responses until the server was restarted. The proxy stayed healthy, so proxy status alone did not reveal application availability. Recovery required a same-pane restart, local and routed health checks, then a temporary warm backend on another loopback port. This evidence contains no private hostname, user data, or runtime value.

## Why Now

Bnest remains in use while centralized-data work changes configuration, supervision, authentication, and storage. A watched working tree is therefore not a safe stable backend. The immediate containment is operational and temporary; it needs an Nx-owned lifecycle with deterministic promotion, rollback, and cleanup.

## Prior Art / Precedents

- [Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve) can reverse-proxy one tailnet HTTPS mount to a chosen loopback backend; reviewed 2026-08-26.
- [Kubernetes rolling updates](https://kubernetes.io/docs/tasks/run-application/update-deployment-rolling/) warm replacement instances before retiring old ones and retain rollback history; reviewed 2026-08-26. The concept is useful, but adopting Kubernetes for this single-machine internal app would be disproportionate.
- [Phoenix deployment guidance](https://hexdocs.pm/phoenix/deployment.html) separates build/start preparation from the serving process and supports an explicit port; reviewed 2026-08-26.

## Proposed Direction (Sketch)

Add Nx targets around a small local promoter. It should build or snapshot an immutable candidate outside the watched tree, compile and start it with one matching stable environment on an unused loopback port, use the production root only when schema/write compatibility is proven, and run local health plus a critical LiveView journey. Only then should it switch the existing Tailscale Serve root mount. Keep the previous backend alive until routed verification passes; one command switches back on failure. Record only ports, versions, and pass/fail—not tailnet or user identifiers.

## Rough Scope & Non-Goals

Scope includes stable/candidate process ownership, port selection, readiness, proxy promotion, rollback, stale-process cleanup, and an Nx verification target. It does not introduce Kubernetes, public hosting, Funnel, replicas that concurrently mutate incompatible flat-file schemas, or a general deployment platform.

## Risks & Open Questions

- Two app versions must not write incompatible records to the same flat-file root.
- LiveView connections on the old backend need drain behaviour or an explicit reconnect proof.
- Candidate artifacts and processes need bounded, ownership-checked cleanup.
- The promoter must distinguish a healthy HTML response from a usable authenticated/legacy journey.

## What Success Looks Like + Promotion Signal

A scripted test deliberately breaks the working-tree server while the routed Bnest root, chat route, and LiveView interaction remain available from the stable backend. Candidate promotion and rollback both pass through Nx, leave one declared active backend plus one bounded rollback candidate, and never modify production data merely to test availability. Promote this idea to a formal plan when centralized-data delivery finishes or before another restart-triggering feature begins, whichever comes first.

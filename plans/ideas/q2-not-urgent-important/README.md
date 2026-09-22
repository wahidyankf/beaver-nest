# Q2 — Important, Not Urgent

This quadrant contains valuable ideas with meaningful impact but no current deadline, active blocker, or immediate failure pressure.

## Ideas

- [RHINO adoption across the OSE repositories](rhino-adoption-across-ose.md) extends the completed cutover to
  `ose-public` and the private operations repository, and settles whether `ose-public`'s own `rhino-cli` merges into RHINO.
- [Real-production-cutover GraphQL subscription continuity proof](family-chat-real-cutover-subscription-proof.md)
  proves family chat's live subscription survives a real `release:run` Caddy promotion, descoped from v1.
- [Family chat reply flag retirement](family-chat-reply-flag-retirement.md) removes the reply feature flag and its
  branches once the rollback window has closed.
- [Family chat swipe to reply](family-chat-swipe-to-reply.md) adds a one-step reply gesture without making the fast
  path the inaccessible one.
- [Family chat room reading on a phone](family-chat-room-reading-on-a-phone.md) addresses six usability findings
  about density, repetition, and getting back to the newest message.
- [Shared token claims and layer tags](shared-token-claims-and-layer-tags.md) settles what a shared-token
  specification line promises and what a scenario's layer tag obliges.

## Directory Map

- [RHINO adoption across the OSE repositories](rhino-adoption-across-ose.md) records the alignment evidence, the
  three questions a merge must answer in order, and the two triggers that would promote it to a plan.
- [Real-production-cutover GraphQL subscription continuity proof](family-chat-real-cutover-subscription-proof.md)
  records the missing service-account auth path, probe room, and telemetry mechanism, and the two triggers that
  would promote it to a plan.
- [Family chat reply flag retirement](family-chat-reply-flag-retirement.md) records the branches to delete, the
  scenarios that describe a posture the product would no longer have, and the one-cycle promotion signal.
- [Family chat swipe to reply](family-chat-swipe-to-reply.md) records the accessibility constraint the gesture must
  satisfy and the two collision risks it carries.
- [Family chat room reading on a phone](family-chat-room-reading-on-a-phone.md) records the measured 320px budget,
  the six grouped findings, and the promotion signal.
- [Shared token claims and layer tags](shared-token-claims-and-layer-tags.md) records the focus-ring and
  inline-longhand evidence, the corpus-pruning obligation, and the two proposed convention lines.

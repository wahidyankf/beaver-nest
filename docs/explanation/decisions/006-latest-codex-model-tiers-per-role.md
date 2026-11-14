# 006. Latest Codex model tiers, and model and effort per role

Status: Accepted (2026-11-14). The owner decided these rules. They replace the role rules of the Codex chat that
[README](../../../README.md) and `specs/apps/bnest/app-be/architecture.md` described: parents fixed to Terra, children
fixed to Luna, and an admin's effort falling back to medium. The chat's other rules, from ADR 002 to ADR 005, stand.

## Context

- The local Codex installation lists eight models. Three of them are the latest of their tier: Sol (`gpt-6.1-sol`),
  Terra (`gpt-6.1-terra`) and Luna (`gpt-6-luna`). Astra (`gpt-6-astra`) and the older ids (`gpt-6-sol`, `gpt-5.6-*`)
  are not offered.
- The app offered every discovered model to an admin. Its default and its discovery-failure fallback named
  `gpt-5.6-terra`, an older id.
- Parents were fixed to Terra and children to Luna, both at medium effort, with no picker. A parent may now choose
  between Luna and Terra, so the rules have to say what a parent can change, and the server must refuse anything else.
- A user may already have saved a chat with an older model or an effort the new rules do not allow. Such a chat must
  still open and work, without a data migration and without a schema change.

## Decision 1. Only the latest model of each tier is offered

`BnestApp.CodexChat.Domain.ModelAccess.offered?/1` lists the three ids: `gpt-6-luna`, `gpt-6.1-terra` and
`gpt-6.1-sol`. `BnestApp.CodexChat.ModelCatalog` filters the discovered list by id first: it keeps only the entries whose id is one of
these, and ignores every other entry whatever its shape. So a malformed Astra or older entry cannot empty the catalog.
The kept entries are then checked for shape, and the first entry of each id is kept, in the order Codex lists them. If a
kept entry is malformed, or no entry is kept, the catalog is the Terra fallback below. Every surface that reads the
catalog (the picker, the default model, and each lookup by id) sees the same entries. The catalog is the one place where
the filter sits, because it is where every reader gets its models. A filter only at access time would leave older ids
visible to any other reader.

Names are the ones the local Codex returns: "GPT-6-Luna", "GPT-6.1 Terra" and "GPT-6.1-Sol". The header chip shows
only the tier name and the effort, for example "Terra · medium".

Discovery itself is unchanged. If discovery fails, or returns no offered model, the catalog falls back to a single
Terra entry: `gpt-6.1-terra`, named "GPT-6.1 Terra", with the six efforts Codex lists for it (low to ultra). The entry
carries the default effort "low", as Codex lists it, but both roles use the constant medium effort (Decision 2), so the
stored default is not what a conversation runs with. A failed discovery never offers an older id.

## Decision 2. Role rules, checked in this order: admin, parents, children

| Role          | Model                                  | Effort                                                     |
| ------------- | -------------------------------------- | ---------------------------------------------------------- |
| admin         | picks any offered model; default Terra | picks any effort the chosen model supports; default medium |
| parents       | picks Luna or Terra; default Terra     | always medium; no effort picker                            |
| children      | Luna, fixed; no model picker           | always medium; no effort picker                            |
| no known role | the admin's access                     | the admin's access                                         |

Roles are checked in the order admin, parents, children. An account that holds several roles follows the first matching
role in that order, so a child who also holds the admin role gets the admin's pickers. This is the existing behaviour,
and the owner is asked to review it.

A parent's choices are Terra, then Luna, in that order whatever order Codex lists the models in. Only a choice that
supports medium effort is offered, so a parent never picks a model without medium effort. The admin's picker lists Sol,
Terra and Luna in that order, highest tier first, whatever order Codex lists the models in.

## Decision 3. Effort rules

- An admin's effort list is the selected model's supported efforts. Luna has no "ultra".
- When an admin switches to a model that does not support the current effort, the effort becomes "max". Luna supports
  "max", and so do Sol and Terra. A switch that keeps a supported effort keeps it.
- The server applies these rules to every switch. A parent or child who sends an effort, or a model outside the role's
  choices, gets no change. An admin who sends an effort the model does not support gets no change either.

## Decision 4. Saved settings resolve at read time, without a migration

A chat saved with an older model or an effort the role may not use still opens. Resolution happens each time the chat
is read, and nothing in storage changes.

- A saved model that the role does not offer resolves to the role's default: Terra for admins and parents, Luna for
  children.
- A parent's or child's effort is always medium, whatever was saved.
- An admin keeps a saved effort that the resolved model supports. Otherwise the effort becomes "max".

## Decision 5. A locked or unavailable role never falls back to another model

Children are locked to Luna. Parents may choose Luna or Terra, but their default is Terra, so they are available only
when Terra is offered at medium effort. When a required model is missing, or does not support medium effort, that role's
chat shows "<name> is not available in local Codex.", and the composer stays disabled. Nothing switches the role to
another model automatically. When Codex removes a model, the locked roles see the unavailable message until the model
returns. Parents who cannot use Terra see the same message, and Luna is not offered in its place.

An admin's default is Terra. When Terra is absent, the admin gets the model Codex flags as its default, or else the
first offered model. This is the existing admin behaviour, and the admin keeps a picker.

## Consequences

- Parents now see a model picker with two choices, and the effort picker stays hidden. Children see neither.
- The header badge shows short names such as "Terra · medium" without the words "model" or "effort". This wording is
  kept as it is in this change.
- The effort option "xhigh" is labelled "XHigh". This label is kept as it is in this change.
- Behaviour that the previous rules fixed changes in these places: the admin's switch fallback, the discovery-failure
  fallback, and the parent's model. The Gherkin in `specs/apps/bnest/app-fe/behaviours/chat.feature` and the
  architecture in `specs/apps/bnest/app-be/architecture.md` follow these rules.
- Tests use the real Codex ids, copied from the local list into a fixture, not synthetic ids. The unit and integration suites check that
  Astra and the older ids are never offered, and that the server refuses forged events from each role.
- Not built: a migration of old saved chats. None is needed, because each read resolves them.

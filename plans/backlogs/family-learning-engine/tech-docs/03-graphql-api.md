# GraphQL API

One authenticated endpoint at `POST /api/graphql` answers the same facts the learning UI renders. Its purpose is exploration and verification: a maintainer can inspect state without a new controller, and a browser journey can assert across the API boundary in the same test that drives the UI.

## Dependency Decision

Adding GraphQL means adding `absinthe` and `absinthe_plug`, so the [dependency-selection standard](../../../../repo-governance/development/dependency-selection.md) applies and its four required records follow.

**Requirement.** Reads are served entirely from the projections described in [the data model](02-data-model.md); the API never queries the event log to answer a request. The projected model is a graph whose useful questions are nested and varied: a course with its topics with each mission and this learner's progress and coin balance; a review queue with mission bodies; a pending verification queue across learners. Serving those from hand-written JSON controllers means either many narrow endpoints that grow with each screen, or one endpoint with ad-hoc query parameters that drifts into a worse query language.

**Built-in alternatives considered and rejected.** Phoenix JSON controllers with the standard library need no dependency and were the first choice, but they push per-screen shaping into route design and leave no schema for a maintainer to explore; each new question becomes a code change. An `iex` session against the context functions covers exploration but cannot be used as an assertion boundary from a browser test, which is the second half of the requirement. A single generic `POST /api/query` endpoint accepting a field list is a private query language with none of the tooling and all of the maintenance.

**Community and maintenance evidence.** Absinthe is the established GraphQL implementation for Elixir and the one the Phoenix ecosystem documents. Before execution, delivery re-checks current primary sources for release recency, supported Elixir and OTP range against this repository's toolchain, and open security advisories, and records the pinned versions in `mix.exs` and `mix.lock`. If that check fails, the fallback is Phoenix JSON controllers scoped to the screens that exist, and this document is revised rather than the check waived.

**Ownership impact.** Two runtime dependencies, a schema and resolver layer to keep aligned with the context, and per-field authorization that must be tested rather than assumed. The cost is bounded by keeping the schema small and read-mostly: no content mutations, no file uploads, no subscriptions. Absinthe's subscription support is deliberately unused; live updates come from the LiveView and the event bus described in [the event model](01-event-model.md), so the API stays request-response.

## Schema

```graphql
type Query {
  courses: [Course!]!
  course(courseId: ID!): Course
  mission(missionId: ID!): Mission
  learner(userId: ID): Learner!
  reviewQueue(userId: ID, limit: Int = 20): [MissionProgress!]!
  verificationQueue(limit: Int = 50): [PendingVerification!]!
}

type Mutation {
  acknowledgeMission(missionId: ID!): MissionProgress!
  answerMission(missionId: ID!, answer: AnswerInput!): AnswerResult!
  submitForVerification(missionId: ID!): MissionProgress!
  decideVerification(
    userId: ID!
    missionId: ID!
    attemptNo: Int!
    approved: Boolean!
  ): MissionProgress!
  resetMissionProgress(missionId: ID!): MissionProgress!
}

type Course {
  courseId: ID!
  title: String!
  summary: String!
  position: Int!
  topics: [TopicPlacement!]!
}

type TopicPlacement {
  position: Int!
  topic: Topic!
}

type Topic {
  topicId: ID!
  title: String!
  summary: String!
  sequencing: Sequencing!
  missions: [MissionPlacement!]!
}

type MissionPlacement {
  position: Int!
  mission: Mission!
}

type Mission {
  missionId: ID!
  kind: MissionKind!
  title: String!
  passRule: PassRule!
  reviewPolicy: ReviewPolicy!
  coinReward: Int!
  payload: JSON!
  progress: MissionProgress
}

type MissionProgress {
  missionId: ID!
  state: ProgressState!
  attemptCount: Int!
  correctCount: Int!
  correctStreak: Int!
  reviewStep: Int!
  masteredAt: DateTime
  nextReviewAt: DateTime
}

type AnswerResult {
  correct: Boolean!
  progress: MissionProgress!
  coinsEarned: Int!
  balance: Int!
}

type PendingVerification {
  userId: ID!
  missionId: ID!
  attemptNo: Int!
  answeredAt: DateTime!
  mission: Mission!
}

type Learner {
  userId: ID!
  coinBalance: Int!
  masteredCount: Int!
  dueForReviewCount: Int!
  progress: [MissionProgress!]!
}

enum Sequencing {
  FREE
  SEQUENTIAL
}
enum MissionKind {
  READING
  VIDEO
  MULTIPLE_CHOICE
  SHORT_TEXT
  FLASHCARD
  PARENT_CHECK
}
enum PassRule {
  ACKNOWLEDGE
  FIRST_CORRECT
  STREAK_TWO
  STREAK_THREE
  PARENT_VERIFIED
}
enum ReviewPolicy {
  NONE
  SPACED
}
enum ProgressState {
  STARTED
  ANSWERED
  AWAITING_VERIFICATION
  MASTERED
}
```

`Mission.payload` is an opaque JSON scalar because its shape depends on `kind`; the runner and the sync share the kind contract in [the data model](02-data-model.md), and the API does not re-declare six payload types it would have to keep in step.

There is no `createCourse`, `updateMission`, or any other content mutation, and no mutation that appends a raw event. Content changes enter through the sync command and every learner change enters through a command handler that decides before it appends, so a client can never dictate a fact. Absence from the schema, not a permission check, is what AC-08 asserts.

## Authorization

Every request resolves a viewer from the existing session cookie through `BnestAppWeb.UserAuth`; there is no token, header, or API key path. An unauthenticated request is refused before parsing, and the response body carries no schema detail.

| Field                                                                                  | Allowed viewer                                         | Denial behaviour                  |
| -------------------------------------------------------------------------------------- | ------------------------------------------------------ | --------------------------------- |
| `courses`, `course`, `mission` (content fields)                                        | Any authenticated user                                 | —                                 |
| `Mission.progress`, `learner`, `reviewQueue` with no `userId`                          | The viewer, resolved to themselves                     | —                                 |
| `learner`, `reviewQueue` with another `userId`                                         | `parents` or `admin`                                   | Value-free error, no partial data |
| `verificationQueue`                                                                    | `parents` or `admin`                                   | Value-free error                  |
| `acknowledgeMission`, `answerMission`, `submitForVerification`, `resetMissionProgress` | The viewer, for their own progress only                | Value-free error                  |
| `decideVerification`                                                                   | `parents` or `admin`, and never for their own `userId` | Value-free error                  |

Authorization is enforced in the resolver against the domain context, not in the schema shape, and the same rule is enforced again by the context function, so a resolver defect cannot widen access. Errors carry a stable category and no learner value, no display name, and no host path.

## Limits and safety

Depth is capped at 10 and complexity at 500, which comfortably covers `courses → topics → missions → progress` and rejects a pathological nested query. Introspection is enabled only when `dev_routes` is enabled. GraphiQL is mounted at `/dev/graphiql` under the existing `dev_routes` block beside LiveDashboard, and is absent from production entirely; the production endpoint still answers an authenticated operation, which is what makes it useful for verification against the routed origin.

Batched operations are not accepted. A request carries one operation, which keeps complexity accounting and authorization auditing simple.

## Test Strategy

The exhaustive contract belongs in Elixir integration tests, not in the browser, because it is cheap there, runs in-process, and is part of `test:quick`. The browser project owns only what cannot be proven in-process: that the endpoint is reachable through the real router at the exact origin with a real session cookie.

| Layer             | Project                      | What it proves                                                                                                                                                                                                                   |
| ----------------- | ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Unit              | `bnest-app/test/unit`        | Review interval arithmetic, pass-rule evaluation, slug and payload validation                                                                                                                                                    |
| Integration       | `bnest-app/test/integration` | Every query and mutation, every authorization row above, error categories, depth and complexity limits, absence of content and raw-event mutations, and that a mutation's effect is visible to a query in the same request cycle |
| Behaviour         | `bnest-app/test/behaviour`   | The shared Gherkin corpus through the context and LiveView                                                                                                                                                                       |
| E2E `api` project | `bnest-app-e2e`              | Routed reachability, session acceptance, unauthenticated refusal, GraphiQL absent without `dev_routes`                                                                                                                           |
| E2E browser       | `bnest-app-e2e`              | Learner and parent journeys, with API assertions inside the journey                                                                                                                                                              |

The `api` Playwright project uses the `request` fixture and starts no browser, so it runs in seconds. It stays inside `test:e2e` rather than `test:quick`, because it still needs a running server, per the repository rule that keeps end-to-end work out of the quick gate.

The corpus is not split into API and UI feature files. One `.feature` describes a behaviour and each adapter binds what it can, following the project rule that incapable adapters are exempted rather than duplicated. In a browser journey, the API is used for assertion and for cheap setup — for example, mastering thirty missions before testing the review screen — but never for the action under test, so a passing journey always exercised the real interface.

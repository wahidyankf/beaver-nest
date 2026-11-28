// Binding record for family_chat_graphql.feature's transport scenarios: the
// unauthenticated push refusals and the 405/415 transport refusals. The step
// definitions live with their siblings (family-chat-web-push-visitor and
// family-chat-transport); this file carries the coverage markers so the two
// scenarios stay bound without duplicating their steps.
//
// @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: Push queries and mutations refuse unauthenticated callers
// @scenario specs/apps/bnest/app-be/behaviours/family_chat_graphql.feature: A non-POST request is 405, a non-JSON content type is 415

// The scenarios bound above, kept beside their markers.
export const GRAPHQL_TRANSPORT_SCENARIOS: readonly string[] = [
  "Push queries and mutations refuse unauthenticated callers",
  "A non-POST request is 405, a non-JSON content type is 415",
];

Feature: Family chat GraphQL API

  Background:
    Given an approved user is logged in

  Rule: Authorized room query

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / A member queries the authorized room list
  @e2e-exempt
  Scenario: A member queries the authorized room list
    When the user queries the family chat room list
    Then the response lists exactly the active "Ruang Keluarga" room

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / A member queries Ruang Keluarga by its slug
  @e2e-exempt
  Scenario: A member queries Ruang Keluarga by its slug
    When the user queries the family chat room "ruang-keluarga"
    Then the response returns the "Ruang Keluarga" room

  Rule: Bounded message pagination

  Background:
    Given an approved user is logged in
    And the family chat room holds a known ordered history of messages

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / The latest page is returned without a cursor
  @e2e-exempt
  Scenario: The latest page is returned without a cursor
    When the user queries family chat messages with no cursor
    Then the response returns at most 50 messages ascending by server ID
    And "hasOlder" reflects whether an older message exists

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / A beforeId page returns older history
  @e2e-exempt
  Scenario: A beforeId page returns older history
    When the user queries family chat messages before a known message ID
    Then the response returns older messages ascending by server ID

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / An afterId page returns catch-up history
  @e2e-exempt
  Scenario: An afterId page returns catch-up history
    When the user queries family chat messages after a known committed message ID
    Then the response returns newer messages ascending by server ID
    And "hasNewer" reflects whether another page remains

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / Supplying both cursors is rejected
  @e2e-exempt
  Scenario: Supplying both cursors is rejected
    When the user queries family chat messages with both a beforeId and an afterId
    Then the response is a safe "VALIDATION_FAILED" error

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / A limit outside the accepted range is rejected
  @e2e-exempt
  Scenario Outline: A limit outside the accepted range is rejected
    When the user queries family chat messages with limit <limit>
    Then the response is a safe "VALIDATION_FAILED" error

    Examples:
      | limit |
      | 0     |
      | -1    |
      | 51    |

  Rule: Idempotent message send

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / A member sends a durable message
  @e2e-exempt
  Scenario: A member sends a durable message
    When the user sends the family chat message "Dinner is ready" with a fresh client message ID
    Then the response returns the committed message with a server ID and commit time
    And the family chat room holds exactly one message with that client message ID

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / Retrying the same client message ID returns the original commit
  @e2e-exempt
  Scenario: Retrying the same client message ID returns the original commit
    Given the user already sent the family chat message "Dinner is ready" with a known client message ID
    When the user resends a different body with the same client message ID
    Then the response returns the original committed message unchanged
    And the family chat room still holds exactly one message for that client message ID

  Rule: Safe errors for unauthenticated, forbidden, invalid, and missing-room operations

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / An unauthenticated visitor is denied family chat data
  @e2e-exempt
  Scenario: An unauthenticated visitor is denied family chat data
    Given a visitor has no authenticated Bnest session
    When the visitor queries the family chat room list
    Then the response is a safe "UNAUTHENTICATED" error

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / A user without family chat capability is forbidden from the room query
  @e2e-exempt
  Scenario: A user without family chat capability is forbidden from the room query
    Given an approved user without family chat capability is logged in
    When the user queries the family chat room "ruang-keluarga"
    Then the response is a safe "FORBIDDEN" error
    And the response reveals no hidden room state

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / A user without family chat capability is forbidden from sending a message
  @e2e-exempt
  Scenario: A user without family chat capability is forbidden from sending a message
    Given an approved user without family chat capability is logged in
    When the user sends the family chat message "Not allowed" with a fresh client message ID
    Then the response is a safe "FORBIDDEN" error

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / Invalid message text is rejected before commit
  @e2e-exempt
  Scenario Outline: Invalid message text is rejected before commit
    When the user sends the family chat message "<body>" with a fresh client message ID
    Then the response is a safe "VALIDATION_FAILED" error
    And the family chat room gains no new message

    Examples:
      | body                                 |
      | whitespace-only-body                 |
      | over-4000-graphemes-normalized-body  |
      | over-16-kib-body                     |

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / A missing room is reported safely without enumerating hidden rooms
  @e2e-exempt
  Scenario: A missing room is reported safely without enumerating hidden rooms
    When the user queries the family chat room "no-such-room"
    Then the response is a safe "ROOM_NOT_FOUND" error

  Rule: Post-commit subscription and catch-up

  # Exemption(integration): a live Absinthe subscription push over a socket process is not observable through Phoenix.ConnTest/LiveViewTest; alternative-proof: bnest-app-be-e2e:test:e2e / A subscriber receives exactly one event per committed message
  @integration-exempt
  Scenario: A subscriber receives exactly one event per committed message
    Given the user holds an authorized "familyChatMessageCommitted" subscription for "ruang-keluarga"
    When another member sends the family chat message "Subscribed event" with a fresh client message ID
    Then the subscriber receives exactly one committed-message event matching that message
    And a duplicate retry of the same client message ID publishes no second event

  # Exemption(integration): a live Absinthe subscription push over a socket process is not observable through Phoenix.ConnTest/LiveViewTest; alternative-proof: bnest-app-be-e2e:test:e2e / A subscriber catches up a missed event through afterId
  @integration-exempt
  Scenario: A subscriber catches up a missed event through afterId
    Given a message committed before the user's subscription started
    When the user establishes the "familyChatMessageCommitted" subscription for "ruang-keluarga"
    And the user queries family chat messages after their last known committed message ID
    Then the response includes the message committed before the subscription started

  Rule: Web Push configuration and subscription through GraphQL

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / A member reads the Web Push configuration
  @e2e-exempt
  Scenario: A member reads the Web Push configuration
    When the user queries the Web Push configuration
    Then the response reports whether Web Push is available
    And the response includes the public application server key only when configured and safe

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / A member reads their current Web Push subscription state
  @e2e-exempt
  Scenario: A member reads their current Web Push subscription state
    When the user queries their current Web Push subscription
    Then the response reports enabled state and expiration only

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / A member enables Web Push on this device
  @e2e-exempt
  Scenario: A member enables Web Push on this device
    When the user upserts a valid Web Push subscription for this session
    Then the response reports the subscription enabled
    And the stored subscription is bound to the current user and session only

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / A member disables Web Push on this device
  @e2e-exempt
  Scenario: A member disables Web Push on this device
    Given the user has an enabled Web Push subscription for this session
    When the user disables their current Web Push subscription
    Then the response reports the subscription disabled
    When the user disables their current Web Push subscription again
    Then the response still reports the subscription disabled

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / An unsafe subscription endpoint is rejected before storage
  @e2e-exempt
  Scenario Outline: An unsafe subscription endpoint is rejected before storage
    When the user upserts a Web Push subscription with endpoint "<endpoint>"
    Then the response is a safe "VALIDATION_FAILED" error
    And no subscription row is stored or requested over the network

    Examples:
      | endpoint                                   |
      | http://push.example.com/unapproved-host    |
      | https://203.0.113.7/ip-literal-endpoint     |
      | https://push.allowed.example.com:8443/nondefault-port |
      | https://user@push.allowed.example.com/userinfo-present |

  Rule: Cookie/CSRF and session-derived identity

  # Exemption(e2e): the routed HTTP pipeline is already exercised through Phoenix.ConnTest against the same GraphQL endpoint; alternative-proof: bnest-app:test:integration / A mutation without a valid CSRF token is rejected
  @e2e-exempt
  Scenario: A mutation without a valid CSRF token is rejected
    When the user sends a family chat message mutation with a missing CSRF token
    Then the response is a 403 envelope with a safe "CSRF_REJECTED" error

  # Exemption(e2e): the socket handshake and its context are already exercised through Phoenix.ChannelTest.connect/3 against the same UserSocket; alternative-proof: bnest-app:test:integration / The subscription socket resolves identity only from the server session
  @e2e-exempt
  Scenario: The subscription socket resolves identity only from the server session
    When the user's browser opens the family chat GraphQL socket with the authenticated session
    Then the socket context carries the server-resolved current user and session digest
    And socket parameters claiming another identity or role are ignored

  # Exemption(e2e): the socket handshake rejection is already exercised through Phoenix.ChannelTest.connect/3 against the same UserSocket; alternative-proof: bnest-app:test:integration / The socket rejects a connection with no valid session
  @e2e-exempt
  Scenario: The socket rejects a connection with no valid session
    Given a visitor has no authenticated Bnest session
    When the visitor's browser opens the family chat GraphQL socket
    Then the socket handshake is rejected

  Rule: GraphiQL disabled in production

  # Exemption(e2e): a production-compiled release is not started for exact-origin E2E; alternative-proof: bnest-app:test:integration / GraphiQL is absent from a production-configured endpoint
  @e2e-exempt
  Scenario: GraphiQL is absent from a production-configured endpoint
    Given the endpoint is configured for the production environment
    When the router's compiled routes are inspected
    Then no GraphiQL route is compiled or mounted

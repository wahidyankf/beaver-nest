Feature: Bnest operator configuration

  Rule: Production refuses missing or unsafe push configuration

  # Carries BN-CFG-13 and the BN-CFG-14 group row (subject not a mailto:/https: contact).
  # Integration is exempt because the prod push configuration is release-boot
  # configuration for the production supervision tree, which no integration
  # boundary boots; the unit adapter proves it over doubles.
  # Exemption(integration): the prod push configuration is release-boot configuration for the production supervision tree, which no integration boundary boots; alternative-proof: bnest-app:test:unit / A production start refuses missing or unsafe push configuration
  @integration-exempt
  # Exemption(e2e): a production boot refusal is below every public application boundary; alternative-proof: bnest-app:test:unit / A production start refuses missing or unsafe push configuration
  @e2e-exempt
  Scenario Outline: A production start refuses missing or unsafe push configuration
    Given the push env has public key file "<public-file>" and private key file "<private-file>" and subject "<subject>"
    When the push configuration is derived
    Then the push boot is "<boot>"

    Examples:
      | public-file | private-file | subject               | boot                                                                            |
      | (unset)     | /keys/private | mailto:ops@example.com | environment variable BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE is missing          |
      | /keys/public | (unset)     | mailto:ops@example.com | environment variable BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE is missing         |
      | /keys/public | /keys/private | (unset)              | environment variable BNEST_WEB_PUSH_SUBJECT is missing                          |
      | /keys/public | /keys/private | ops@example.com      | BNEST_WEB_PUSH_SUBJECT must be a mailto: or https: contact                      |
      | /keys/public | /keys/private | mailto:ops@example.com | BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE/BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE must not be empty |

  Rule: Stable mode turns off code reload and asset watchers

  # Carries BN-CFG-17.
  # Exemption(integration): dev.exs is compile-time configuration for the developer shell, which no integration boundary boots; alternative-proof: bnest-app:test:unit / Stable mode turns off code reload and asset watchers
  @integration-exempt
  # Exemption(e2e): the E2E harness boots the test profile, never the stable dev profile; alternative-proof: bnest-app:test:unit / Stable mode turns off code reload and asset watchers
  @e2e-exempt
  Scenario Outline: Stable mode turns off code reload and asset watchers
    Given BNEST_STABLE is "<stable>"
    When the dev configuration is derived
    Then code reload is "<reload>" and the watchers are "<watchers>"

    Examples:
      | stable  | reload | watchers |
      | true    | off    | none     |
      | (unset) | on     | esbuild,Tailwind |
      | false   | on     | esbuild,Tailwind |

  Rule: Readiness fails closed while the named peer slot does not answer

  # Carries BN-CFG-18.
  # Exemption(e2e): the exact origin cannot name an unreachable peer slot; alternative-proof: bnest-app:test:integration / Readiness fails closed while the named peer slot does not answer
  @e2e-exempt
  Scenario Outline: Readiness fails closed while the named peer slot does not answer
    Given the deploy peer is "<peer>" and it is "<reachable>"
    When readiness is checked
    Then liveness is "<live>" and readiness is "<ready>" and health ready answers "<health>"

    Examples:
      | peer               | reachable | live | ready      | health      |
      | (unset)            | (n/a)     | live | ready      | 200 ready   |
      | test-peer@test-host | no       | live | not_ready  | 503 not_ready |
      | test-peer@test-host | yes      | live | ready      | 200 ready   |

  Rule: A slot deployment refuses to start without its deployment files and origin

  # Carries BN-CFG-19.
  # Integration is exempt because deploy:prepare runs below every Elixir
  # boundary as a Node child process; the unit adapter proves it through the
  # reviewed model and the Node suite proves the real script.
  # Exemption(integration): deploy:prepare runs as a Node child process below every Elixir boundary, so no integration boundary observes the refusal; alternative-proof: bnest-app:test:unit / A slot deployment refuses to start without its deployment files and origin
  @integration-exempt
  # Exemption(e2e): a slot deployment runs on the host service manager, below every public boundary; alternative-proof: bnest-app:test:unit / A slot deployment refuses to start without its deployment files and origin
  @e2e-exempt
  Scenario Outline: A slot deployment refuses to start without its deployment files and origin
    Given the deploy env misses "<missing>" and the production origin is "<origin>"
    When deploy prepare is attempted
    Then it exits 1 with "<message>" and writes no service definition and a prepared slot carries RELEASE_DISTRIBUTION none with the cookie from file

    Examples:
      | missing                              | origin                  | message                                                              |
      | BNEST_DEPLOY_COOKIE_FILE             | https://service.example | BNEST_DEPLOY_COOKIE_FILE must point to machine-local deployment state. |
      | BNEST_DEPLOY_SECRET_KEY_BASE_FILE    | https://service.example | BNEST_DEPLOY_SECRET_KEY_BASE_FILE must point to machine-local deployment state. |
      | BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE | https://service.example | BNEST_DEPLOY_WEB_PUSH_PUBLIC_KEY_FILE must point to machine-local deployment state. |
      | BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE | https://service.example | BNEST_DEPLOY_WEB_PUSH_PRIVATE_KEY_FILE must point to machine-local deployment state. |
      | (none)                               | (unset)                 | BNEST_PRODUCTION_ORIGIN must identify the routed HTTPS origin.       |
      | (none)                               | http://service.example  | Production origin must be a bare HTTPS origin                        |

  Rule: A production node joins the cluster named by DNS_CLUSTER_QUERY

  # Carries BN-CFG-20.
  # Exemption(integration): the DNS cluster query is read once before the supervision tree starts, which no integration boundary boots; alternative-proof: bnest-app:test:unit / A production node joins the cluster named by DNS_CLUSTER_QUERY
  @integration-exempt
  # Exemption(e2e): cluster membership is host distribution state below every public boundary; alternative-proof: bnest-app:test:unit / A production node joins the cluster named by DNS_CLUSTER_QUERY
  @e2e-exempt
  Scenario Outline: A production node joins the cluster named by DNS_CLUSTER_QUERY
    Given DNS_CLUSTER_QUERY is "<query>"
    When the cluster child spec is derived
    Then the endpoint carries "<cluster>"

    Examples:
      | query              | cluster            |
      | bnest-prod.example | DNS bnest-prod.example |
      | (unset)            | no cluster         |

  Rule: Production listens on loopback and redirects plain HTTP to HTTPS

  # Carries BN-CFG-27.
  # Exemption(integration): force_ssl is compile-time endpoint configuration with no integration read-back beyond the unit proof; alternative-proof: bnest-app:test:unit / Production listens on loopback and redirects plain HTTP to HTTPS
  @integration-exempt
  # Exemption(e2e): loopback bind and HSTS redirect are transport properties below the exact-origin browser boundary; alternative-proof: bnest-app:test:unit / Production listens on loopback and redirects plain HTTP to HTTPS
  @e2e-exempt
  Scenario Outline: Production listens on loopback and redirects plain HTTP to HTTPS
    Given the request host is "<host>" over "<scheme>"
    When the production transport is derived
    Then it binds "<bind>" and answers "<answer>"

    Examples:
      | host            | scheme | bind      | answer                  |
      | service.example | http   | 127.0.0.1 | redirect to HTTPS + HSTS |
      | service.example | https  | 127.0.0.1 | serve                   |
      | localhost       | http   | 127.0.0.1 | serve                   |
      | 127.0.0.1       | http   | 127.0.0.1 | serve                   |

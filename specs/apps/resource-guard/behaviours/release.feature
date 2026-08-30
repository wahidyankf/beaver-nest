Feature: Release resource ownership
  Release orchestration delegates host resource decisions and monitoring to the Go guard.

  @e2e-exempt
  Scenario: Release admission preserves the requested capacity envelope
    Given a release host below its requested balanced capacity
    When release admission is assessed
    Then the release requires replanning instead of automatic fallback

  @e2e-exempt
  Scenario: Release overlap rejects failed health evidence
    Given a release summary with one health failure
    When release overlap evidence is assessed
    Then the release evidence is rejected

  @e2e-exempt
  Scenario: Release overlap rejects an unresponsive routed journey
    Given a release summary outside the routed responsiveness budget
    When release overlap evidence is assessed
    Then the release evidence is rejected

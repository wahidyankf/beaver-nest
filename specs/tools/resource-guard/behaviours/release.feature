Feature: Release resource ownership
  Release orchestration delegates host resource decisions and monitoring to the Go guard.

  @e2e-exempt
  Scenario: Release admission reserves six CPU units
    Given a release host with eight execution units and safe memory
    When release admission is assessed
    Then three CPU samples at or below 25 percent are required

  @e2e-exempt
  Scenario: Release overlap rejects failed health evidence
    Given a release summary with one health failure
    When release overlap evidence is assessed
    Then the release evidence is rejected

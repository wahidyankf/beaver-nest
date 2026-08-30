Feature: Portable host evidence
  Host-specific signals are normalized without requiring unavailable capabilities.

  @e2e-exempt
  Scenario: Linux cgroup memory limits host capacity
    Given Linux reports 16 GiB host memory and a 4 GiB cgroup limit
    When the Linux evidence is collected
    Then effective memory is 4 GiB

  @e2e-exempt
  Scenario: Linux without swap remains usable
    Given Linux reports no usable swap
    When development pressure is assessed
    Then swap is unavailable without causing critical pressure

  @e2e-exempt
  Scenario: Linux PSI detects active memory contention
    Given Linux memory PSI some average is 10 percent
    When development pressure is assessed
    Then the state is warning because of memory PSI

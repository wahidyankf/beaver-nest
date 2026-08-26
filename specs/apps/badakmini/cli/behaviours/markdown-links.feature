Feature: Markdown internal-link validation

  Scenario: Existing local links and non-local links pass
    Given file "README.md" contains this Markdown:
      """
      # Root
      """
    And file "docs/target.md" contains this Markdown:
      """
      # Target
      """
    And file "docs/guide/entry.txt" contains this Markdown:
      """
      Guide entry
      """
    And file "docs/source.md" contains this Markdown:
      """
      [Target](target.md?raw=1#section), [root](../README.md), and [guide](guide/).
      [External](https://example.com/docs), [email](mailto:docs@example.com), and [section](#local) remain valid.
      [Reference target][target-ref].

      [target-ref]: target.md
      """
    When I run the "links" validator
    Then the exit code is 0

  Scenario Outline: Missing or out-of-repository local targets fail
    Given the repository contains:
      | path           | content               |
      | docs/source.md | [Missing](<target>)   |
    When I run the "links" validator
    Then the exit code is 1

    Examples:
      | target                 |
      | missing.md             |
      | ../../outside.md       |
      | /outside.md            |

  Scenario: A reference-style definition with a missing target fails
    Given file "docs/source.md" contains this Markdown:
      """
      [Missing reference][missing-ref]

      [missing-ref]: missing.md
      """
    When I run the "links" validator
    Then the exit code is 1

  Scenario: Fragment links and fenced Markdown examples are ignored
    Given file "docs/source.md" contains this Markdown:
      """
      [Current section](#details)

      ```markdown
      [Example only](missing.md)
      ```
      """
    When I run the "links" validator
    Then the exit code is 0

  Scenario: A malformed local target fails without stopping inspection
    Given file "docs/source.md" contains this Markdown:
      """
      [Malformed](bad{nul}path.md)
      """
    When I run the "links" validator
    Then the exit code is 1

  Scenario: Archived plans are not link-validation sources
    Given file "plans/done/historical.md" contains this Markdown:
      """
      [Retired document](missing.md)
      """
    When I run the "links" validator
    Then the exit code is 0

Feature: Governance directory-map rules

  Scenario: Directory-map inspection ignores other governance concerns
    Given file "AGENTS.md" contains 501 words
    And the repository contains:
      | path                      | content                                                 |
      | repo-governance/README.md | {hash} Governance                                       |
      | docs/diagram.md           | ```mermaid\nflowchart LR\nclassDef unsafe fill:red\n``` |
    When I inspect directory maps
    Then 1 directories were inspected
    And the only violation is a missing directory map at "repo-governance/README.md"

  Scenario: Complete maps cover direct files and directories
    Given the repository contains:
      | path                                 | content                                                                                                         |
      | repo-governance/README.md             | {hash} Governance\n\n{hash}{hash} Directory Map\n\n- [Nested](nested/README.md)\n- [Rules](rules.md) |
      | repo-governance/nested/README.md      | {hash} Nested\n\n{hash}{hash} Directory Map\n\nThis directory currently has no other entries.            |
      | repo-governance/rules.md              | {hash} Rules                                                                                                    |
    When I inspect directory maps
    Then 2 directories were inspected
    And there are no violations

  Scenario Outline: The selected directory must stay relative and inside the repository
    Given an empty repository
    When I inspect directory maps under the invalid "<location>" location
    Then an argument error is raised

    Examples:
      | location                 |
      | empty path               |
      | absolute repository root |
      | outside repository       |

  Scenario: Query and fragment suffixes do not change a sibling target
    Given the repository contains:
      | path                         | content                                                                                   |
      | repo-governance/README.md    | {hash} Governance\n\n{hash}{hash} Directory Map\n\n- [Rules](rules.md?raw=1{hash}details) |
      | repo-governance/rules.md     | {hash} Rules                                                                              |
    When I inspect directory maps
    Then there are no violations

  Scenario: Absolute URL and malformed map links are invalid
    Given the repository contains:
      | path                      | content                                                                                                                                                 |
      | repo-governance/README.md | {hash} Governance\n\n{hash}{hash} Directory Map\n\n- [Absolute](/rules.md)\n- [URL](https://example.com/rules.md)\n- [Malformed](bad{nul}path.md) |
    When I inspect directory maps
    Then there are 3 violations
    And all violations are "invalid map entry"

  Scenario: Every governance directory needs a README
    Given the repository contains:
      | path                            | content                                                                        |
      | repo-governance/README.md       | {hash} Governance\n\n{hash}{hash} Directory Map\n\n- [Nested](nested) |
      | repo-governance/nested/rules.md | {hash} Rules                                                                   |
    When I inspect directory maps
    Then the only violation is a missing README at "repo-governance/nested"

  Scenario: Every README needs a Directory Map section
    Given the repository contains:
      | path                      | content           |
      | repo-governance/README.md | {hash} Governance |
    When I inspect directory maps
    Then the only violation is a missing directory map at "repo-governance/README.md"

  Scenario: Every direct sibling must appear in the map
    Given file "repo-governance/README.md" has title "Governance" and an empty directory map
    And the repository contains:
      | path                     | content      |
      | repo-governance/rules.md | {hash} Rules |
    When I inspect directory maps
    Then the only violation is a missing map entry from "repo-governance/README.md" to "repo-governance/rules.md"

  Scenario: Independent inspections report independent violations
    Given file "repo-governance/README.md" has an empty "Governance" directory map followed by 501 words
    And the repository contains:
      | path                     | content      |
      | repo-governance/rules.md | {hash} Rules |
    When I inspect directory maps
    Then the violations include an overlong "repo-governance/README.md" and its missing map entry for "repo-governance/rules.md"

  Scenario: A map entry must exist
    Given the repository contains:
      | path                      | content                                                                                 |
      | repo-governance/README.md | {hash} Governance\n\n{hash}{hash} Directory Map\n\n- [Old rules](old-rules.md) |
    When I inspect directory maps
    Then the only violation is an invalid map entry from "repo-governance/README.md" to "old-rules.md"

  Scenario: A map entry must be a direct sibling
    Given the repository contains:
      | path                                | content                                                                                |
      | repo-governance/README.md            | {hash} Governance\n\n{hash}{hash} Directory Map\n\n- [Nested](nested/README.md) |
      | repo-governance/nested/README.md     | {hash} Nested\n\n{hash}{hash} Directory Map\n\n- [Parent](../README.md)      |
    When I inspect directory maps
    Then the only violation is an invalid map entry from "repo-governance/nested/README.md" to "../README.md"

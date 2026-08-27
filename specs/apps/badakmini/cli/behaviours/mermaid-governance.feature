Feature: Mermaid governance inspection

  Scenario: Mermaid inspection ignores other governance concerns
    Given file "AGENTS.md" contains 751 words
    And the repository contains:
      | path                      | content           |
      | repo-governance/README.md | {hash} Governance |
    And an unsafe "flowchart LR" Mermaid diagram exists at "docs/diagram.md" using backtick fences
    When I inspect Mermaid accessibility
    Then 1 Mermaid diagrams were inspected
    And the only violation is a Mermaid accessibility issue at "docs/diagram.md"

  Scenario: Mermaid diagnostics identify the Markdown source line
    Given file "docs/diagram.md" contains this Markdown:
      """
      {hash} Diagram

      ```mermaid
      flowchart LR
          A[Node]
          classDef unsafe fill:{hash}FF0000,stroke:{hash}000000,color:{hash}FFFFFF
      ```
      """
    When I inspect Mermaid accessibility
    Then the formatted violation starts with "docs/diagram.md:6:"

  Scenario Outline: Every supported diagram type rejects an overlong visible node label
    Given the repository contains Mermaid sample "<sample>" at "docs/diagram.md"
    When I invoke the CLI with "md|mermaid|validate|--format|json"
    Then the exit code is 1
    And the first stdout JSON violation kind is "mermaid-legibility"

    Examples:
      | sample                         |
      | overlong flowchart node        |
      | overlong graph node            |
      | overlong class node            |
      | overlong state node            |
      | overlong state-v2 node         |
      | overlong ER entity             |
      | overlong requirement node      |
      | overlong block node            |

  Scenario Outline: Label segments use deterministic grapheme boundaries
    Given the repository contains Mermaid sample "<sample>" at "docs/diagram.md"
    When I run the "mermaid" validator
    Then the exit code is <exit>

    Examples:
      | sample                              | exit |
      | node label at 32 graphemes           | 0    |
      | node label at 33 graphemes           | 1    |
      | edge label at 24 graphemes           | 0    |
      | edge label at 25 graphemes           | 1    |
      | text edge at 25 graphemes            | 1    |
      | split node labels at the boundary    | 0    |
      | split node labels with br             | 0    |
      | split node labels with newline        | 0    |
      | combining grapheme node at boundary  | 0    |
      | encoded node at boundary              | 0    |

  Scenario: State transition semicolons are rejected
    Given the repository contains Mermaid sample "state transition semicolon" at "docs/diagram.md"
    When I invoke the CLI with "md|mermaid|validate|--format|json"
    Then the exit code is 1
    And the first stdout JSON violation kind is "mermaid-legibility"

  Scenario: Legibility JSON reports deterministic measurement fields
    Given the repository contains Mermaid sample "node label at 33 graphemes" at "docs/diagram.md"
    When I invoke the CLI with "md|mermaid|validate|--format|json"
    Then the first stdout JSON legibility fields are "node", 33, and 32

  Scenario: Non-label Mermaid declarations are excluded
    Given the repository contains Mermaid sample "legibility exclusions" at "docs/diagram.md"
    When I run the "mermaid" validator
    Then the exit code is 0

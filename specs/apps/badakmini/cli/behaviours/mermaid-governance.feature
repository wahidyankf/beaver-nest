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

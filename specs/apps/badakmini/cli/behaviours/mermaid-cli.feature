Feature: Mermaid accessibility command behavior

  Scenario Outline: Compatible diagram types enforce class colors
    Given an unsafe "<header>" Mermaid diagram exists at "docs/diagram.md" using backtick fences
    When I run the "mermaid" validator
    Then the exit code is 1

    Examples:
      | header             |
      | flowchart LR       |
      | graph TD           |
      | classDiagram       |
      | stateDiagram       |
      | stateDiagram-v2    |
      | erDiagram          |
      | requirementDiagram |
      | block              |

  Scenario Outline: Incompatible diagram types are skipped
    Given an unsafe "<header>" Mermaid diagram exists at "docs/diagram.md" using backtick fences
    When I run the "mermaid" validator
    Then the exit code is 0

    Examples:
      | header            |
      | sequenceDiagram   |
      | mindmap           |
      | timeline          |
      | kanban            |
      | architecture-beta |
      | treeView          |
      | gantt             |
      | pie               |
      | quadrantChart     |
      | treemap-beta      |
      | swimlane-beta     |
      | futureDiagram     |

  Scenario: Tilde-fenced Mermaid diagrams are extracted
    Given an unsafe "flowchart LR" Mermaid diagram exists at "plans/diagram.md" using tilde fences
    When I run the "mermaid" validator
    Then the exit code is 1

  Scenario: Diagram type is found after YAML front matter
    Given the repository contains Mermaid sample "YAML front matter before an unsafe flowchart" at "docs/diagram.md"
    When I run the "mermaid" validator
    Then the exit code is 1

  Scenario: A Mermaid block without a diagram type is skipped
    Given the repository contains Mermaid sample "no diagram declaration" at "docs/diagram.md"
    When I run the "mermaid" validator
    Then the exit code is 0

  Scenario: Generated and dependency directories are excluded
    Given each excluded directory contains an unsafe Mermaid diagram:
      * .git
      * .nx
      * node_modules
      * bin
      * obj
      * _build
      * deps
      * coverage
      * playwright-report
      * test-results
    When I run the "mermaid" validator
    Then the exit code is 0

  Scenario: An accessible colored class passes
    Given the repository contains Mermaid sample "accessible colored class" at "docs/diagram.md"
    When I run the "mermaid" validator
    Then the exit code is 0

  Scenario Outline: Colors outside classDef are rejected
    Given the repository contains Mermaid sample "<sample>" at "docs/diagram.md"
    When I run the "mermaid" validator
    Then the exit code is 1

    Examples:
      | sample                         |
      | style declaration color        |
      | linkStyle declaration color    |
      | initialization directive color |

  Scenario Outline: Unsupported color formats are rejected
    Given the repository contains Mermaid sample "<sample>" at "docs/diagram.md"
    When I run the "mermaid" validator
    Then the exit code is 1

    Examples:
      | sample                  |
      | named color             |
      | three-digit hex color   |
      | eight-digit hex color   |
      | RGB function color      |
      | HSL function color      |

  Scenario Outline: Colored diagrams require one accurate palette comment
    Given the repository contains Mermaid sample "<sample>" at "docs/diagram.md"
    When I run the "mermaid" validator
    Then the exit code is 1

    Examples:
      | sample                     |
      | missing palette comment    |
      | duplicate palette comments |
      | inaccurate palette comment |

  Scenario Outline: Node color roles and normal-text contrast are enforced
    Given the repository contains Mermaid sample "<sample>" at "docs/diagram.md"
    When I run the "mermaid" validator
    Then the exit code is 1

    Examples:
      | sample                     |
      | identical fill and stroke  |
      | missing stroke             |
      | non-black node stroke      |
      | missing text color         |
      | unsupported text color     |
      | insufficient text contrast |

  Scenario: An accessible stroke-only class passes
    Given the repository contains Mermaid sample "accessible stroke-only class" at "docs/diagram.md"
    When I run the "mermaid" validator
    Then the exit code is 0

  Scenario Outline: Text-only and inaccessible stroke-only classes fail
    Given the repository contains Mermaid sample "<sample>" at "docs/diagram.md"
    When I run the "mermaid" validator
    Then the exit code is 1

    Examples:
      | sample                         |
      | text-only class                |
      | inaccessible stroke-only class |

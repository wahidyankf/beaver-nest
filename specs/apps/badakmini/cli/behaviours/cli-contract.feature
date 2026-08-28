Feature: badakmini-cli command contract

  Scenario: Every canonical nested command path succeeds
    Given an empty repository
    When I run the "word-budget" validator
    Then the exit code is 0
    When I run the "directory-map" validator
    Then the exit code is 0
    When I run the "mermaid" validator
    Then the exit code is 0
    When I run the "harness-contract" validator
    Then the exit code is 1

  Scenario: Word-budget validation is isolated
    Given file "AGENTS.md" contains 751 words
    When I run the "word-budget" validator
    Then the exit code is 1
    When I run the "directory-map" validator
    Then the exit code is 0
    When I run the "mermaid" validator
    Then the exit code is 0

  Scenario: Directory-map validation is isolated
    Given the repository contains:
      | path                      | content           |
      | repo-governance/README.md | {hash} Governance |
    When I run the "word-budget" validator
    Then the exit code is 0
    When I run the "directory-map" validator
    Then the exit code is 1
    When I run the "mermaid" validator
    Then the exit code is 0

  Scenario: A complete selected docs tree passes directory-map validation
    Given the repository contains:
      | path                  | content                                                                                          |
      | docs/README.md        | {hash} Docs\n\n{hash}{hash} Directory Map\n\n- [Nested](nested/README.md) |
      | docs/nested/README.md | {hash} Nested\n\n{hash}{hash} Directory Map\n\nNo other entries.           |
    When I run the directory-map validator for "docs"
    Then the exit code is 0

  Scenario: A selected docs directory without a README fails
    Given the repository contains:
      | path                 | content                                                                                          |
      | docs/README.md       | {hash} Docs\n\n{hash}{hash} Directory Map\n\n- [Nested](nested/README.md) |
      | docs/nested/guide.md | {hash} Guide                                                                                     |
    When I run the directory-map validator for "docs"
    Then the exit code is 1

  Scenario: An omitted selected docs sibling fails
    Given file "docs/README.md" has title "Docs" and an empty directory map
    And the repository contains:
      | path          | content        |
      | docs/guide.md | {hash} Guide   |
    When I run the directory-map validator for "docs"
    Then the exit code is 1

  Scenario: A selected plans tree requires recursive README directory maps
    Given the repository contains:
      | path                                      | content                                                                                                       |
      | plans/README.md                           | {hash} Plans\n\n{hash}{hash} Directory Map\n\n- [Backlogs](backlogs/README.md)                  |
      | plans/backlogs/README.md                  | {hash} Backlogs\n\n{hash}{hash} Directory Map\n\n- [Family app](family-app/README.md)              |
      | plans/backlogs/family-app/README.md       | {hash} Family App                                                                                             |
      | plans/backlogs/family-app/delivery.md     | {hash} Delivery                                                                                               |
    When I run the directory-map validator for "plans"
    Then the exit code is 1

  Scenario: Mermaid accessibility validation is isolated
    Given an unsafe "flowchart LR" Mermaid diagram exists at "docs/diagram.md" using backtick fences
    When I run the "word-budget" validator
    Then the exit code is 0
    When I run the "directory-map" validator
    Then the exit code is 0
    When I run the "mermaid" validator
    Then the exit code is 1

  Scenario: Root defaults to the current directory
    Given an empty repository
    When I invoke the CLI from the repository directory with "governance|word-budget|validate"
    Then the exit code is 0

  Scenario: Root is accepted before and after nested commands
    Given an empty repository
    When I invoke the CLI with "--root|{root}|governance|word-budget|validate"
    Then the exit code is 0
    When I invoke the CLI with "governance|word-budget|validate|--root|{root}"
    Then the exit code is 0

  Scenario: Leaf output has an atomic command-category prefix
    Given an empty repository
    When I run the "word-budget" validator
    Then the exit code is 0
    And stdout lines start with "[word-budget] "
    When I run the "directory-map" validator
    Then the exit code is 0
    And stdout lines start with "[directory-map] "
    When I run the "mermaid" validator
    Then the exit code is 0
    And stdout lines start with "[mermaid] "
    Given file "AGENTS.md" contains 751 words
    When I run the "word-budget" validator
    Then the exit code is 1
    And stderr lines start with "[word-budget] "

  Scenario Outline: Inspection errors use command-specific diagnostics
    Given the governed files are exclusively locked
    When I run the "<validator>" validator
    Then the exit code is 2
    And stdout is empty
    And stderr lines start with "[<validator>] "

    Examples:
      | validator     |
      | word-budget   |
      | directory-map |
      | mermaid       |

  Scenario Outline: Help and version requests succeed
    Given an empty repository
    When I invoke the CLI with "<arguments>"
    Then the exit code is 0

    Examples:
      | arguments                                  |
      | --help                                     |
      | --version                                  |
      | governance\|--help                         |
      | governance\|word-budget\|--help             |
      | governance\|word-budget\|validate\|--help    |
      | governance\|harness-contract\|--help         |
      | governance\|harness-contract\|validate\|--help |
      | md\|--help                                 |
      | md\|links\|--help                          |
      | md\|links\|validate\|--help               |
      | md\|mermaid\|--help                        |
      | md\|mermaid\|validate\|--help               |

  Scenario Outline: Invalid invocations return usage failure
    Given an empty repository
    When I invoke the CLI with "<arguments>"
    Then the exit code is 2

    Examples:
      | arguments                                                    |
      | {root}                                                       |
      | governance                                                   |
      | governance\|word-budget                                      |
      | governance\|harness-contract                                 |
      | md\|mermaid                                                  |
      | md\|links                                                    |
      | unknown                                                      |
      | governance\|word-budget\|validate\|extra                      |
      | governance\|word-budget\|validate\|--root\|{missing-root}     |

  Scenario: A governed file above the limit returns validation failure
    Given file "AGENTS.md" contains 751 words
    When I run the "word-budget" validator
    Then the exit code is 1

  Scenario: Invalid governance navigation returns validation failure
    Given the repository contains:
      | path                      | content           |
      | repo-governance/README.md | {hash} Governance |
    When I run the "directory-map" validator
    Then the exit code is 1

  Scenario Outline: Output format is recursive for every validator
    Given an empty repository
    When I invoke the CLI with "<arguments>|--format|json"
    Then the exit code is 0
    And stdout lines start with "{"

    Examples:
      | arguments                                 |
      | governance\|word-budget\|validate          |
      | governance\|directory-map\|validate        |
      | md\|links\|validate                        |
      | md\|mermaid\|validate                      |

  Scenario: A file word count is observable as JSON
    Given Markdown text containing a heading marker, Hello, can't-stop, naïve, and 42
    When I invoke the CLI with "md|word-count|inspect|--file|subject.md|--format|json"
    Then the exit code is 0
    And stdout JSON property "wordCount" is 4

  Scenario: JSON validation failures retain the validation exit code
    Given file "AGENTS.md" contains 751 words
    When I invoke the CLI with "governance|word-budget|validate|--format|json|--root|{root}"
    Then the exit code is 1
    And the first stdout JSON violation kind is "word-limit-exceeded"

  Scenario Outline: Unsupported output formats return usage failure
    Given an empty repository
    When I invoke the CLI with "<arguments>|--format|xml"
    Then the exit code is 2

    Examples:
      | arguments                                             |
      | governance\|word-budget\|validate                      |
      | governance\|directory-map\|validate                    |
      | md\|links\|validate                                    |
      | md\|word-count\|inspect\|--file\|missing.md             |

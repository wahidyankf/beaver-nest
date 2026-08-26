Feature: Governance word-budget rules

  Scenario: Markdown punctuation does not create extra words
    Given Markdown text containing a heading marker, Hello, can't-stop, naïve, and 42
    When I count the words in "subject.md"
    Then the word count is 4

  Scenario: Only governed Markdown is scanned
    Given the repository contains:
      | path                            | content      |
      | AGENTS.md                       | agents rules |
      | repo-governance/nested/RULES.MD | nested rules |
      | repo-governance/notes.txt       | not Markdown |
      | docs/long-form.md               | outside docs |
      | README.md                       | outside root |
    When I scan governed Markdown
    Then the scanned Markdown paths are:
      * AGENTS.md
      * repo-governance/nested/RULES.MD

  Scenario: The 500-word boundary is inclusive
    Given file "AGENTS.md" contains 500 words
    And file "repo-governance/too-long.md" contains 501 words
    When I find word-limit violations
    Then the only violation is a 501-word limit for "repo-governance/too-long.md"

  Scenario: Optional governed paths may be absent
    Given an empty repository
    When I scan governed Markdown
    Then no Markdown files are scanned

  Scenario: Specification Markdown has no word limit
    Given file "specs/apps/bnest/app/architecture.md" contains 501 words
    When I inspect the word budget
    Then no Markdown files are scanned
    And there are no violations

  Scenario: Planning Markdown has no word limit
    Given file "plans/ideas/q2-not-urgent-important/family-calendar.md" contains 501 words
    When I inspect the word budget
    Then no Markdown files are scanned
    And there are no violations

  Scenario: Word-budget inspection ignores other governance concerns
    Given file "AGENTS.md" contains 501 words
    And the repository contains:
      | path                      | content                                                 |
      | repo-governance/README.md | {hash} Governance                                       |
      | docs/diagram.md           | ```mermaid\nflowchart LR\nclassDef unsafe fill:red\n``` |
    When I inspect the word budget
    Then the scanned Markdown paths are:
      * AGENTS.md
      * repo-governance/README.md
    And the only violation is a 501-word limit for "AGENTS.md"

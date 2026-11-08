Feature: Bnest test instance isolation

  Scenario: A fresh test instance serves its own storage and forgets the previous account
    Given an approved admin is logged in
    When the test replaces the current test instance with a fresh one
    Then Bnest reports the fresh instance's storage generation
    And the previous instance's admin account cannot log in

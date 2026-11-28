Feature: Bnest test instance isolation

  Scenario: A fresh test instance reports its own storage generation
    Given an approved admin is logged in
    When the test replaces the current test instance with a fresh one
    Then Bnest reports the fresh instance's storage generation

  Scenario: A fresh test instance does not know the previous instance's admin account
    Given an approved admin is logged in
    When the test replaces the current test instance with a fresh one
    Then the previous instance's admin account cannot log in

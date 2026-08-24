Feature: Revising the 20 attributes of Allah

  Scenario: A child opens the revision dashboard
    When a visitor opens "/apps/sifat-allah"
    Then the page displays the heading "Misi Hafal 40 Sifat Allah"
    And the page displays the text "20 pasangan untuk kamu hafal"
    And the study mode is available
    And the quiz mode is available

  Scenario: A child learns a pair and keeps the progress after a reload
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts learning
    Then the study card shows "Wujud" and "Ada"
    When the visitor marks the current pair as remembered
    Then the progress shows "1 dari 20 pasangan sudah kenal"
    When the visitor reloads the page
    Then the progress shows "1 dari 20 pasangan sudah kenal"
    And the study card shows "Wujud" and "Ada"

  Scenario: A child swipes through a learning session
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts learning
    And the visitor swipes left on the study card
    Then the study card shows "Qidam" and "Dahulu"
    When the visitor swipes right on the study card
    Then the study card shows "Wujud" and "Ada"

  Scenario: A child can return to the mission while learning
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts learning
    And the visitor returns to the mission
    Then the study mode is available
    And the quiz mode is available

  Scenario: A child receives kind feedback for a correct quiz answer
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts a quiz
    And the visitor answers "Ada"
    Then the page displays the text "Betul!"
    And the progress shows "1 jawaban benar"

  Scenario: A child keeps the current quiz question after a reload
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts a quiz
    And the visitor continues to the next quiz question
    Then the page displays the text "Apa lawan dari Qidam?"
    When the visitor reloads the page
    Then the page displays the text "Apa lawan dari Qidam?"

  Scenario: A child swipes through quiz questions
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts a quiz
    And the visitor swipes left on the quiz question
    Then the page displays the text "Apa lawan dari Qidam?"
    When the visitor swipes right on the quiz question
    Then the page displays the text "Apa arti Wujud?"

  Scenario: A child practises the opposite attribute too
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts a quiz
    And the visitor continues to the next quiz question
    Then the page displays the text "Apa lawan dari Qidam?"
    When the visitor answers "Hudus"
    Then the page displays the text "Betul!"

  Scenario: A difficult pair is kept for another try
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts a quiz
    And the visitor answers "Lemah"
    Then the page displays the text "Belum tepat. Nanti kita ulang lagi, ya."
    And the revision list contains "Wujud"

  Scenario: A child retests a difficult pair until it is correct
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts a quiz
    And the visitor answers "Lemah"
    And the visitor returns to the mission
    And the visitor starts focused review
    Then the page displays the text "Apa arti Wujud?"
    When the visitor answers "Lemah" in focused review
    Then the page displays the text "Belum tepat. Coba sekali lagi, ya."
    When the visitor continues focused review
    Then the page displays the text "Apa arti Wujud?"
    When the visitor answers "Ada" in focused review
    Then the page displays the text "Mantap! Wujud sudah kamu kuasai."
    When the visitor continues focused review
    Then the page displays the text "Ulangi yang masih bikin bingung (0)"

  Scenario: A child gets another difficult pair before repeating one
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts a quiz
    And the visitor answers "Lemah"
    And the visitor continues to the next quiz question
    And the visitor answers "Fana’"
    And the visitor returns to the mission
    And the visitor starts focused review
    Then the page displays the text "Apa arti Wujud?"
    When the visitor answers "Lemah" in focused review
    And the visitor continues focused review
    Then the page displays the text "Apa lawan dari Qidam?"
    When the visitor answers "Fana’" in focused review
    And the visitor continues focused review
    Then the page displays the text "Apa arti Wujud?"

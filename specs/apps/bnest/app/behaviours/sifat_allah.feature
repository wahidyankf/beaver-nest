Feature: Revising the 20 attributes of Allah

  Scenario: A child opens the revision dashboard
    When a visitor opens "/apps/sifat-allah"
    Then the page displays the heading "Misi Hafal 40 Sifat Allah"
    And the page displays the text "20 pasangan: nama, arti, dan lawannya"
    And the page displays the text "40 nama sifat, 120 soal hafalan"
    And the page displays the text "6 soal tiap pasangan"
    And the page displays the text "0% hafal"
    And the progress shows "0 dari 120 soal sudah hafal"
    And the progress shows "120 soal masih perlu diulang"
    And the study mode is available
    And the quiz mode is available

  Scenario: A child learns a pair and keeps the progress after a reload
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts learning
    Then the study card shows "Wujud" and "Ada"
    And the study card uses green for wajib and orange for mustahil
    When the visitor marks the current pair as remembered
    Then the progress shows "6 dari 120 soal sudah hafal"
    And the progress shows "114 soal masih perlu diulang"
    When the visitor reloads the page
    Then the progress shows "6 dari 120 soal sudah hafal"
    And the study card shows "Wujud" and "Ada"

  Scenario: A child learns the earliest pair that is not remembered yet
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts learning
    And the visitor marks the current pair as remembered
    And the visitor returns to the mission
    And the visitor starts learning
    Then the study card shows "Qidam" and "Dahulu"

  Scenario: A quiz prioritizes pairs that are not remembered yet
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts learning
    And the visitor marks the current pair as remembered
    And the visitor returns to the mission
    And the visitor starts learning
    And the visitor marks the current pair as remembered
    And the visitor returns to the mission
    And the visitor starts a quiz
    Then the page displays the text "Apa arti Baqa’?"

  Scenario: A quiz continues as reinforcement after every pair is remembered
    Given a visitor opens "/apps/sifat-allah"
    And the visitor has remembered every Sifat Allah pair
    When the visitor starts a quiz
    Then the page displays the text "Apa arti Wujud?"
    When the visitor continues to the next quiz question
    Then the page displays the text "Apa lawan dari Qidam?"

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

  Scenario: Browser Back returns a child from a quiz to the mission
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts a quiz
    And the visitor goes back in the browser
    Then the study mode is available
    And the quiz mode is available

  Scenario: A child receives kind feedback for a correct quiz answer
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts a quiz
    And the visitor answers "Ada"
    Then the page displays the text "Betul!"
    And the progress shows "1 jawaban benar"
    And the progress shows "1 dari 120 soal sudah hafal"
    And the progress shows "119 soal masih perlu diulang"

  Scenario: A child sees correct answers in varied positions
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts a quiz
    Then the quiz puts correct answers in varied positions

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

  Scenario: A child practises the meaning of an opposite attribute too
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts a quiz
    And the visitor continues to the next quiz question
    And the visitor continues to the next quiz question
    Then the page displays the text "Apa arti Fana’?"
    When the visitor answers "Binasa"
    Then the page displays the text "Betul!"

  Scenario: A child practises every relationship from the reverse direction too
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts a quiz
    And the visitor continues to the next quiz question
    And the visitor continues to the next quiz question
    And the visitor continues to the next quiz question
    Then the page displays the text "Sifat wajib apa yang artinya Berbeda dengan makhluk?"
    When the visitor answers "Mukhalafatuhu lil hawaditsi"
    Then the page displays the text "Betul!"
    When the visitor continues to the next quiz question
    Then the page displays the text "Apa lawan dari Qiyamuhu bighairihi?"
    When the visitor answers "Qiyamuhu binafsihi"
    Then the page displays the text "Betul!"

  Scenario: A difficult pair is kept for another try
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts a quiz
    And the visitor answers "Lemah"
    Then the page displays the text "Belum tepat. Jawaban yang benar: Ada. Nanti kita ulang lagi, ya."
    And the revision list contains "Wujud"

  Scenario: A child retests a difficult pair until it is correct
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts a quiz
    And the visitor answers "Lemah"
    And the visitor returns to the mission
    And the visitor starts focused review
    Then the page displays the text "Apa arti Wujud?"
    When the visitor answers "Lemah" in focused review
    Then the page displays the text "Belum tepat. Jawaban yang benar: Ada. Coba sekali lagi, ya."
    When the visitor continues focused review
    Then the page displays the text "Apa arti Wujud?"
    When the visitor answers "Ada" in focused review
    Then the page displays the text "Mantap! Wujud sudah kamu kuasai."
    When the visitor continues focused review
    Then the page displays the text "Ulangi yang masih bikin bingung (0)"

  Scenario: A child retests a pair that is already remembered
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts learning
    And the visitor marks the current pair as remembered
    And the visitor returns to the mission
    And the visitor starts learned review
    Then the page displays the text "Apa arti Wujud?"
    When the visitor answers "Lemah"
    Then the revision list contains "Wujud"

  Scenario: A pair moves between remembered and difficult review
    Given a visitor opens "/apps/sifat-allah"
    When the visitor starts learning
    And the visitor marks the current pair as remembered
    And the visitor returns to the mission
    And the visitor starts learned review
    And the visitor answers "Lemah"
    And the visitor returns to the mission
    Then the page displays the text "Ulangi yang sudah hafal (0)"
    And the page displays the text "Ulangi yang masih bikin bingung (1)"
    When the visitor starts focused review
    And the visitor answers "Ada" in focused review
    And the visitor continues focused review
    Then the page displays the text "Ulangi yang sudah hafal (1)"
    And the page displays the text "Ulangi yang masih bikin bingung (0)"

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
    Then the page displays the text "Apa arti ‘Adam?"

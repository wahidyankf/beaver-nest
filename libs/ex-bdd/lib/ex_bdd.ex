defmodule ExBdd do
  @moduledoc """
  A behaviour-driven development (BDD) testing framework for Elixir using ExBdd.Gherkin syntax.

  ExBdd is a testing framework that allows you to write executable specifications
  in natural language. It bridges the gap between technical and non-technical stakeholders
  by allowing tests to be written in plain language while being executed as code.

  ## Setup

  Add to your `test_helper.exs`:

      ExBdd.compile_features!()

  ## File Structure

  By default, ExBdd expects the following structure:

      test/
        features/
          authentication.feature
          shopping.feature
          step_definitions/
            authentication_steps.exs
            shopping_steps.exs
            common_steps.exs
          support/
            hooks.exs

  ## Configuration

  You can customize paths in `config/test.exs`:

      config :ex_bdd,
        features: ["test/features/**/*.feature"],
        steps: ["test/features/step_definitions/**/*.exs"]

  Setting `messages: "cucumber-messages.ndjson"` additionally writes a
  [ExBdd Messages](https://github.com/cucumber/messages) NDJSON stream
  describing the run — see `ExBdd.Messages`.

  ## Step Definitions

  Create step definition modules using `ExBdd.StepDefinition`:

      defmodule AuthenticationSteps do
        use ExBdd.StepDefinition

        step "I am logged in as {string}", %{args: [username]} = context do
          {:ok, Map.put(context, :current_user, username)}
        end
      end

  ## Running Tests

  ExBdd tests run with `mix test` and can be filtered using tags:

      # Run all tests including ExBdd
      mix test

      # Run only ExBdd tests
      mix test --only ex_bdd

      # Exclude ExBdd tests
      mix test --exclude ex_bdd

  ## Key Features

  * Auto-discovery of features and step definitions
  * Integration with ExUnit's tagging system
  * Context passing between steps
  * Support for data tables and doc strings
  * Rich error reporting with suggestions
  """

  @doc """
  Discovers and compiles all configured Gherkin features into ExUnit tests.

  This function should be called in your `test_helper.exs` file.

  ## Options

    * `:features` - List of patterns for feature files
    * `:steps` - List of patterns for step definition files
    * `:support` - List of patterns for support files

  ## Examples

      # Use default paths
      ExBdd.compile_features!()

      # Use custom paths
      ExBdd.compile_features!(
        features: ["test/acceptance/**/*.feature"],
        steps: ["test/acceptance/steps/**/*.exs"]
      )
  """
  @spec compile_features!(keyword()) :: [module()]
  def compile_features!(opts \\ []) do
    modules = ExBdd.Compiler.compile_features!(opts)

    # Return the compiled module names for debugging
    modules
  end

  @doc """
  Verifies that the configured feature corpus and step bindings are complete.

  Accepts the same `:features`, `:steps`, and `:support` discovery options as
  `compile_features!/1` and returns an `ExBdd.Verification` summary.
  """
  @spec verify_features!(keyword()) :: ExBdd.Verification.t()
  def verify_features!(opts \\ []) do
    opts
    |> ExBdd.Discovery.discover()
    |> ExBdd.Verifier.verify!()
  end

  @doc """
  Attaches data to the current step (or hook execution) for reporting.

  Mirrors the `attach` API of reference ExBdd implementations: useful
  for capturing screenshots, response payloads, or logs while a scenario
  runs. Attachments are recorded against the step that attached them; until
  a step fails they are invisible, then they are listed in the failure
  output. (ExBdd Messages formatters will render them in reports, #28.)

  `data` is either a string (attached as-is) or `{:bytes, binary}` for
  binary data, which is Base64-encoded — Elixir can't tell text from bytes
  by type, so binary data is marked explicitly.

  Returns the context unchanged, so it composes with any step return style.

  ## Options

    * `:filename` - a file name for the attachment (e.g. `"screenshot.png"`)

  ## Examples

      step "I take a screenshot", context do
        ExBdd.attach(context, {:bytes, screenshot()}, "image/png",
          filename: "checkout.png"
        )
      end

      step "the API responds", context do
        context
        |> ExBdd.attach(response.body, "application/json")
        |> Map.put(:response, response)
      end
  """
  @spec attach(map(), String.t() | {:bytes, binary()}, String.t(), keyword()) :: map()
  def attach(context, data, media_type, opts \\ [])

  def attach(context, {:bytes, binary}, media_type, opts) when is_binary(binary) do
    record_attachment(context, Base.encode64(binary), media_type, :base64, opts)
  end

  def attach(context, text, media_type, opts) when is_binary(text) do
    record_attachment(context, text, media_type, :identity, opts)
  end

  @doc """
  Attaches a log message to the current step.

  Convenience for `attach(context, text, "text/x.cucumber.log+plain")` —
  the media type reference ExBdd implementations use for `log`.
  Returns the context unchanged.
  """
  @spec log(map(), String.t()) :: map()
  def log(context, text) when is_binary(text) do
    attach(context, text, "text/x.cucumber.log+plain")
  end

  @doc """
  Attaches a link to the current step.

  Convenience for `attach(context, uri, "text/uri-list")` — the media type
  reference ExBdd implementations use for `link`. Returns the context
  unchanged.
  """
  @spec link(map(), String.t()) :: map()
  def link(context, uri) when is_binary(uri) do
    attach(context, uri, "text/uri-list")
  end

  defp record_attachment(context, body, media_type, encoding, opts) do
    step = if context[:ex_bdd_phase] == :step, do: context[:step]

    attachment = %ExBdd.Attachment{
      body: body,
      media_type: media_type,
      encoding: encoding,
      filename: opts[:filename],
      feature_file: Map.get(context, :feature_file),
      scenario_name: Map.get(context, :scenario_name),
      step_text: step && step.text,
      step_line: step && step.line,
      phase: Map.get(context, :ex_bdd_phase),
      attempt: Map.get(context, :retry_attempt)
    }

    # The message ref (current testCaseStarted/testStep ids, set by the
    # runner) places the attachment envelope in the message stream
    ExBdd.RunCoordinator.record_attachment(
      attachment,
      Map.get(context, :ex_bdd_message_ref)
    )

    context
  end
end

defmodule ExBdd.Gherkin.Feature do
  @moduledoc """
  Represents a parsed ExBdd.Gherkin feature file (minimal subset).

  A Feature is the top-level element in a ExBdd.Gherkin file, containing a name,
  optional description, optional background, scenarios, and rules.
  It can also have tags that apply to all scenarios in the feature.

  `tag_lines` records each tag's own source line (parallel to `tags`) and
  `comments` collects every comment line in the file as `{line, text}` —
  both for ExBdd Messages locations; the published `tags` shape is
  unchanged.
  """
  defstruct name: "",
            description: "",
            background: nil,
            scenarios: [],
            rules: [],
            tags: [],
            line: nil,
            tag_lines: [],
            comments: []

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          background: ExBdd.Gherkin.Background.t() | nil,
          scenarios: [ExBdd.Gherkin.Scenario.t() | ExBdd.Gherkin.ScenarioOutline.t()],
          rules: [ExBdd.Gherkin.Rule.t()],
          tags: [String.t()],
          line: non_neg_integer() | nil,
          tag_lines: [non_neg_integer()],
          comments: [{non_neg_integer(), String.t()}]
        }
end

defmodule ExBdd.Gherkin.Rule do
  @moduledoc """
  Represents a ExBdd.Gherkin Rule section.

  A Rule groups related scenarios under a feature to express a business rule.
  It can have its own description, tags, and Background; rule-background steps
  run after the feature-background steps for each scenario in the rule, and
  rule tags are inherited by those scenarios.
  """
  defstruct name: "",
            description: "",
            background: nil,
            scenarios: [],
            tags: [],
            line: nil,
            tag_lines: []

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          background: ExBdd.Gherkin.Background.t() | nil,
          scenarios: [ExBdd.Gherkin.Scenario.t() | ExBdd.Gherkin.ScenarioOutline.t()],
          tags: [String.t()],
          line: non_neg_integer() | nil,
          tag_lines: [non_neg_integer()]
        }
end

defmodule ExBdd.Gherkin.Background do
  @moduledoc """
  Represents a ExBdd.Gherkin Background section.

  A Background contains steps that are run before each scenario in the feature.
  It allows you to define common setup steps that apply to all scenarios.
  """
  defstruct name: "", steps: [], description: "", line: nil

  @type t :: %__MODULE__{
          name: String.t(),
          steps: [ExBdd.Gherkin.Step.t()],
          description: String.t(),
          line: non_neg_integer() | nil
        }
end

defmodule ExBdd.Gherkin.Scenario do
  @moduledoc """
  Represents a ExBdd.Gherkin Scenario section.

  A Scenario is a concrete example that illustrates a business rule.
  It consists of a name, an optional free-form description, a list of steps,
  optional tags for filtering, and the line number where it appears in the
  source file. Rule provenance for scenarios defined inside a `Rule` lives
  on `ExBdd.Gherkin.Pickle.rule_name`.
  """
  defstruct name: "",
            description: "",
            steps: [],
            tags: [],
            line: nil,
            keyword: "Scenario",
            tag_lines: []

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          steps: [ExBdd.Gherkin.Step.t()],
          tags: [String.t()],
          line: non_neg_integer() | nil,
          keyword: String.t(),
          tag_lines: [non_neg_integer()]
        }
end

defmodule ExBdd.Gherkin.ScenarioOutline do
  @moduledoc """
  Represents a ExBdd.Gherkin Scenario Outline section.

  A Scenario Outline is a template that runs multiple times with different data
  from Examples tables. Placeholders in step text use `<name>` syntax and are
  substituted with values from each row of the Examples table.
  """
  defstruct name: "",
            description: "",
            steps: [],
            tags: [],
            examples: [],
            line: nil,
            keyword: "Scenario Outline",
            tag_lines: []

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          steps: [ExBdd.Gherkin.Step.t()],
          tags: [String.t()],
          examples: [ExBdd.Gherkin.Examples.t()],
          line: non_neg_integer() | nil,
          keyword: String.t(),
          tag_lines: [non_neg_integer()]
        }
end

defmodule ExBdd.Gherkin.Examples do
  @moduledoc """
  Represents an Examples block within a Scenario Outline.

  Each Examples block contains a table of data used to parameterize the outline.
  The first row contains headers (placeholder names), and subsequent rows contain
  values to substitute. Examples blocks can have optional names, descriptions,
  and tags.
  """
  defstruct name: "",
            description: "",
            tags: [],
            table_header: [],
            table_body: [],
            line: nil,
            keyword: "Examples",
            table_header_line: nil,
            table_body_lines: nil,
            tag_lines: []

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          tags: [String.t()],
          table_header: [String.t()],
          table_body: [[String.t()]],
          line: non_neg_integer() | nil,
          keyword: String.t(),
          table_header_line: non_neg_integer() | nil,
          table_body_lines: [non_neg_integer()] | nil,
          tag_lines: [non_neg_integer()]
        }
end

defmodule ExBdd.Gherkin.Step do
  @moduledoc """
  Represents a ExBdd.Gherkin step (Given/When/Then/And/But/*).

  A Step is a single action or assertion in a scenario. It consists of:
  - keyword: The step type (Given, When, Then, And, But, or *)
  - text: The step text that matches step definitions
  - docstring: Optional multi-line text block (delimited by `\"\"\"` or triple backticks)
  - docstring_media_type: Optional media type annotation on the opening
    docstring delimiter (e.g. `json` in `\"\"\"json`)
  - datatable: Optional table data (pipe-delimited)
  - line: Line number in the source file

  `docstring_line`, `docstring_delimiter`, and `datatable_lines` record the
  source line of the docstring's opening delimiter, the delimiter style used
  (`\"\"\"` or triple backticks), and each datatable row's line (parallel to
  `datatable`) for ExBdd Messages; the published `docstring` and
  `datatable` shapes are unchanged.
  """
  defstruct keyword: "",
            text: "",
            docstring: nil,
            docstring_media_type: nil,
            datatable: nil,
            line: nil,
            docstring_line: nil,
            docstring_delimiter: nil,
            datatable_lines: nil

  @type t :: %__MODULE__{
          keyword: String.t(),
          text: String.t(),
          docstring: String.t() | nil,
          docstring_media_type: String.t() | nil,
          datatable: [[String.t()]] | nil,
          line: non_neg_integer() | nil,
          docstring_line: non_neg_integer() | nil,
          docstring_delimiter: String.t() | nil,
          datatable_lines: [non_neg_integer()] | nil
        }
end

defmodule ExBdd.Gherkin.Parser do
  @moduledoc """
  ExBdd.Gherkin parser using NimbleParsec.

  This module parses ExBdd.Gherkin feature files into Elixir structs, supporting:
  - Feature with name, description, and tags
  - Background with steps
  - Scenarios with steps and tags
  - Scenario Outlines with Examples
  - Steps with keywords, text, docstrings, and datatables

  It implements a subset of the ExBdd.Gherkin language focused on core BDD concepts.
  """

  alias ExBdd.Gherkin.{Markdown, NimbleParser}

  @doc """
  Parses a ExBdd.Gherkin feature file from a string into structured data.

  This function takes a string containing ExBdd.Gherkin syntax and parses it into a
  structured `ExBdd.Gherkin.Feature` struct with its associated components.

  ## Parameters

  * `gherkin_string` - A string containing ExBdd.Gherkin syntax

  ## Returns

  Returns a `%ExBdd.Gherkin.Feature{}` struct containing:
  * `name` - The feature name
  * `description` - The feature description
  * `tags` - List of feature-level tags
  * `background` - Background steps (if present)
  * `scenarios` - List of scenarios

  ## Examples

      # Parse a string containing ExBdd.Gherkin syntax
      ExBdd.Gherkin.Parser.parse("Feature: Shopping Cart\\nScenario: Adding an item")
      # Returns %ExBdd.Gherkin.Feature{} struct with parsed data
  """
  @spec parse(String.t()) :: ExBdd.Gherkin.Feature.t()
  defdelegate parse(gherkin_string), to: ExBdd.Gherkin.NimbleParser

  @doc """
  Parses feature file content, choosing the parser by the file's path.

  `.feature.md` files parse as Markdown with ExBdd.Gherkin (see
  `ExBdd.Gherkin.Markdown`); everything else parses as plain ExBdd.Gherkin, exactly
  like `parse/1`.

  ## Examples

      ExBdd.Gherkin.Parser.parse("# Feature: Cheese", "cheese.feature.md")
      # Returns %ExBdd.Gherkin.Feature{} struct with parsed data
  """
  @spec parse(String.t(), String.t()) :: ExBdd.Gherkin.Feature.t()
  def parse(content, path) do
    if Markdown.markdown_path?(path) do
      Markdown.parse(content)
    else
      NimbleParser.parse(content)
    end
  end
end

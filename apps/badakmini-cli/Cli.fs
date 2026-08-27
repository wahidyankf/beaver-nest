namespace Badakmini.Cli

open System
open System.CommandLine
open System.CommandLine.Parsing
open System.IO
open System.Text.Json
open System.Text.Json.Serialization

type OutputFormat =
    | Text
    | Json

type JsonViolation =
    { Kind: string
      Path: string
      RelatedPath: string
      Target: string
      WordCount: Nullable<int>
      Line: Nullable<int>
      LabelRole: string
      ActualLength: Nullable<int>
      Limit: Nullable<int>
      Message: string }

module Cli =
    let private jsonOptions =
        JsonSerializerOptions(
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
        )

    let private writeOutput runtime category message =
        runtime.Output.WriteLine($"[{category}] {message}")

    let private writeError runtime category message =
        runtime.Error.WriteLine($"[{category}] {message}")

    let private writeJson (writer: TextWriter) value =
        writer.WriteLine(JsonSerializer.Serialize(value, jsonOptions))

    let private parseFormat (value: string) =
        match value.ToLowerInvariant() with
        | "text" -> Ok Text
        | "json" -> Ok Json
        | _ -> Error(ArgumentException("Format must be either 'text' or 'json'.", "format"))

    let private jsonViolation violation =
        let emptyText = null
        let noNumber = Nullable<int>()

        match violation with
        | WordLimitExceeded file ->
            { Kind = "word-limit-exceeded"
              Path = file.Path
              RelatedPath = emptyText
              Target = emptyText
              WordCount = Nullable file.WordCount
              Line = noNumber
              LabelRole = emptyText
              ActualLength = noNumber
              Limit = noNumber
              Message = Governance.formatViolation violation }
        | MissingReadme path ->
            { Kind = "missing-readme"
              Path = path
              RelatedPath = emptyText
              Target = emptyText
              WordCount = noNumber
              Line = noNumber
              LabelRole = emptyText
              ActualLength = noNumber
              Limit = noNumber
              Message = Governance.formatViolation violation }
        | MissingDirectoryMap path ->
            { Kind = "missing-directory-map"
              Path = path
              RelatedPath = emptyText
              Target = emptyText
              WordCount = noNumber
              Line = noNumber
              LabelRole = emptyText
              ActualLength = noNumber
              Limit = noNumber
              Message = Governance.formatViolation violation }
        | MissingMapEntry(readme, sibling) ->
            { Kind = "missing-map-entry"
              Path = readme
              RelatedPath = sibling
              Target = emptyText
              WordCount = noNumber
              Line = noNumber
              LabelRole = emptyText
              ActualLength = noNumber
              Limit = noNumber
              Message = Governance.formatViolation violation }
        | InvalidMapEntry(readme, target) ->
            { Kind = "invalid-map-entry"
              Path = readme
              RelatedPath = emptyText
              Target = target
              WordCount = noNumber
              Line = noNumber
              LabelRole = emptyText
              ActualLength = noNumber
              Limit = noNumber
              Message = Governance.formatViolation violation }
        | InvalidMarkdownLink issue ->
            { Kind = "invalid-markdown-link"
              Path = issue.Path
              RelatedPath = emptyText
              Target = issue.Target
              WordCount = noNumber
              Line = noNumber
              LabelRole = emptyText
              ActualLength = noNumber
              Limit = noNumber
              Message = Governance.formatViolation violation }
        | MermaidAccessibilityViolation issue ->
            { Kind = "mermaid-accessibility"
              Path = issue.Path
              RelatedPath = emptyText
              Target = emptyText
              WordCount = noNumber
              Line = Nullable issue.Line
              LabelRole = emptyText
              ActualLength = noNumber
              Limit = noNumber
              Message = Governance.formatViolation violation }
        | MermaidLegibilityViolation issue ->
            { Kind = "mermaid-legibility"
              Path = issue.Path
              RelatedPath = emptyText
              Target = emptyText
              WordCount = noNumber
              Line = Nullable issue.Line
              LabelRole = issue.LabelRole
              ActualLength = Nullable issue.ActualLength
              Limit = Nullable issue.Limit
              Message = Governance.formatViolation violation }

    let private printViolations runtime category violations =
        for violation in violations do
            Governance.formatViolation violation |> writeError runtime category

    let private operationalError runtime format command category (ex: exn) =
        match format with
        | Text -> writeError runtime category $"badakmini-cli: {ex.Message}"
        | Json ->
            writeJson
                runtime.Error
                {| schemaVersion = 1
                   command = command
                   error = ex.Message |}

        2

    let private runWordBudget runtime format root =
        try
            let inspection = Governance.inspectWordBudgetWith runtime.FileSystem root
            let exitCode = if List.isEmpty inspection.Violations then 0 else 1

            match format with
            | Json ->
                writeJson
                    runtime.Output
                    {| schemaVersion = 1
                       command = "governance word-budget validate"
                       markdownFiles = inspection.MarkdownFiles
                       violations = inspection.Violations |> List.map jsonViolation |}
            | Text when exitCode = 0 ->
                sprintf
                    "Checked %d governed Markdown file(s); all are within the %d-word limit."
                    inspection.MarkdownFiles.Length
                    Governance.WordLimit
                |> writeOutput runtime "word-budget"
            | Text ->
                printViolations runtime "word-budget" inspection.Violations

                sprintf "Found %d word-budget violation(s)." inspection.Violations.Length
                |> writeError runtime "word-budget"

            exitCode
        with ex ->
            operationalError runtime format "governance word-budget validate" "word-budget" ex

    let private runDirectoryMaps runtime format root directory =
        try
            let inspection =
                Governance.inspectDirectoryMapsAtWith runtime.FileSystem root directory

            let exitCode = if List.isEmpty inspection.Violations then 0 else 1

            match format with
            | Json ->
                writeJson
                    runtime.Output
                    {| schemaVersion = 1
                       command = "governance directory-map validate"
                       directoryCount = inspection.DirectoryCount
                       violations = inspection.Violations |> List.map jsonViolation |}
            | Text when exitCode = 0 ->
                sprintf
                    "Checked %d directory map(s) under %s; all directory-map checks passed."
                    inspection.DirectoryCount
                    directory
                |> writeOutput runtime "directory-map"
            | Text ->
                printViolations runtime "directory-map" inspection.Violations

                sprintf "Found %d directory-map violation(s)." inspection.Violations.Length
                |> writeError runtime "directory-map"

            exitCode
        with ex ->
            operationalError runtime format "governance directory-map validate" "directory-map" ex

    let private runMermaidAccessibility runtime format root files =
        try
            let inspection =
                Governance.inspectMermaidAccessibilityAtWith runtime.FileSystem root files

            let exitCode = if List.isEmpty inspection.Violations then 0 else 1

            match format with
            | Json ->
                writeJson
                    runtime.Output
                    {| schemaVersion = 1
                       command = "md mermaid validate"
                       diagramCount = inspection.DiagramCount
                       violations = inspection.Violations |> List.map jsonViolation |}
            | Text when exitCode = 0 ->
                sprintf
                    "Checked %d compatible Mermaid diagram(s); all Mermaid accessibility checks passed."
                    inspection.DiagramCount
                |> writeOutput runtime "mermaid"
            | Text ->
                printViolations runtime "mermaid" inspection.Violations

                sprintf "Found %d Mermaid accessibility violation(s)." inspection.Violations.Length
                |> writeError runtime "mermaid"

            exitCode
        with ex ->
            operationalError runtime format "md mermaid validate" "mermaid" ex

    let private runMarkdownLinks runtime format root =
        try
            let inspection = Governance.inspectMarkdownLinksWith runtime.FileSystem root
            let exitCode = if List.isEmpty inspection.Violations then 0 else 1

            match format with
            | Json ->
                writeJson
                    runtime.Output
                    {| schemaVersion = 1
                       command = "md links validate"
                       markdownFileCount = inspection.MarkdownFileCount
                       violations = inspection.Violations |> List.map jsonViolation |}
            | Text when exitCode = 0 ->
                sprintf "Checked %d Markdown file(s); all local link targets exist." inspection.MarkdownFileCount
                |> writeOutput runtime "links"
            | Text ->
                printViolations runtime "links" inspection.Violations

                sprintf "Found %d invalid Markdown link(s)." inspection.Violations.Length
                |> writeError runtime "links"

            exitCode
        with ex ->
            operationalError runtime format "md links validate" "links" ex

    let private runWordCount runtime format root file =
        try
            let result = Governance.inspectFileWordCountWith runtime.FileSystem root file

            match format with
            | Json ->
                writeJson
                    runtime.Output
                    {| schemaVersion = 1
                       command = "md word-count inspect"
                       path = result.Path
                       wordCount = result.WordCount |}
            | Text -> writeOutput runtime "word-count" $"{result.Path}: {result.WordCount} word(s)."

            0
        with ex ->
            operationalError runtime format "md word-count inspect" "word-count" ex

    let private requireRoot runtime root =
        if not (runtime.FileSystem.DirectoryExists root) then
            invalidArg "root" $"Directory does not exist: {root}"

        Path.GetFullPath root

    let private createLeaf
        runtime
        name
        description
        (rootOption: Option<string>)
        (formatOption: Option<string>)
        command
        category
        action
        =
        let leaf = Command(name, description)

        leaf.SetAction(
            Func<ParseResult, int>(fun parseResult ->
                match parseResult.GetRequiredValue(formatOption) |> parseFormat with
                | Error ex -> operationalError runtime Text command category ex
                | Ok format ->
                    try
                        parseResult.GetRequiredValue(rootOption) |> requireRoot runtime |> action format
                    with ex ->
                        operationalError runtime format command category ex)
        )

        leaf

    let private createDirectoryMapLeaf runtime (rootOption: Option<string>) (formatOption: Option<string>) =
        let command =
            Command("validate", "Validate README presence, sibling coverage, and directory-map links.")

        let directoryOption = Option<string>("--directory")
        directoryOption.Description <- "Repository-relative directory tree. Defaults to repo-governance."
        directoryOption.DefaultValueFactory <- Func<ArgumentResult, string>(fun _ -> "repo-governance")
        command.Options.Add directoryOption

        command.SetAction(
            Func<ParseResult, int>(fun parseResult ->
                match parseResult.GetRequiredValue(formatOption) |> parseFormat with
                | Error ex -> operationalError runtime Text "governance directory-map validate" "directory-map" ex
                | Ok format ->
                    try
                        runDirectoryMaps
                            runtime
                            format
                            (parseResult.GetRequiredValue(rootOption) |> requireRoot runtime)
                            (parseResult.GetRequiredValue directoryOption)
                    with ex ->
                        operationalError runtime format "governance directory-map validate" "directory-map" ex)
        )

        command

    let private createWordCountLeaf runtime (rootOption: Option<string>) (formatOption: Option<string>) =
        let command = Command("inspect", "Count words in one repository-relative file.")
        let fileOption = Option<string>("--file")
        fileOption.Description <- "Repository-relative file to inspect."
        fileOption.Required <- true
        command.Options.Add fileOption

        command.SetAction(
            Func<ParseResult, int>(fun parseResult ->
                match parseResult.GetRequiredValue(formatOption) |> parseFormat with
                | Error ex -> operationalError runtime Text "md word-count inspect" "word-count" ex
                | Ok format ->
                    try
                        runWordCount
                            runtime
                            format
                            (parseResult.GetRequiredValue(rootOption) |> requireRoot runtime)
                            (parseResult.GetRequiredValue fileOption)
                    with ex ->
                        operationalError runtime format "md word-count inspect" "word-count" ex)
        )

        command

    let private createMermaidLeaf runtime (rootOption: Option<string>) (formatOption: Option<string>) =
        let command =
            Command("validate", "Validate accessible colors in compatible Mermaid diagrams.")

        let fileOption = Option<string array>("--file")
        fileOption.Description <- "Repository-relative Markdown file to inspect; repeat to select multiple files."
        fileOption.AllowMultipleArgumentsPerToken <- true
        command.Options.Add fileOption

        command.SetAction(
            Func<ParseResult, int>(fun parseResult ->
                match parseResult.GetRequiredValue(formatOption) |> parseFormat with
                | Error ex -> operationalError runtime Text "md mermaid validate" "mermaid" ex
                | Ok format ->
                    try
                        let files =
                            parseResult.GetValue fileOption
                            |> Option.ofObj
                            |> Option.defaultValue [||]
                            |> Array.toList

                        runMermaidAccessibility
                            runtime
                            format
                            (parseResult.GetRequiredValue(rootOption) |> requireRoot runtime)
                            files
                    with ex ->
                        operationalError runtime format "md mermaid validate" "mermaid" ex)
        )

        command

    let createRootCommandWith runtime =
        let root = RootCommand("Validate repository governance and Markdown conventions.")
        let rootOption = Option<string>("--root")
        rootOption.Description <- "Repository root to inspect. Defaults to the current directory."
        rootOption.Recursive <- true
        rootOption.DefaultValueFactory <- Func<ArgumentResult, string>(fun _ -> runtime.FileSystem.CurrentDirectory())
        root.Options.Add rootOption

        let formatOption = Option<string>("--format")
        formatOption.Description <- "Output format: text or json. Defaults to text."
        formatOption.Recursive <- true
        formatOption.DefaultValueFactory <- Func<ArgumentResult, string>(fun _ -> "text")
        root.Options.Add formatOption

        let governance = Command("governance", "Validate repository governance structures.")
        let wordBudget = Command("word-budget", "Validate governed Markdown word limits.")

        wordBudget.Subcommands.Add(
            createLeaf
                runtime
                "validate"
                "Validate governed Markdown against the repository word limit."
                rootOption
                formatOption
                "governance word-budget validate"
                "word-budget"
                (runWordBudget runtime)
        )

        let directoryMap = Command("directory-map", "Validate README directory maps.")
        directoryMap.Subcommands.Add(createDirectoryMapLeaf runtime rootOption formatOption)
        governance.Subcommands.Add wordBudget
        governance.Subcommands.Add directoryMap

        let markdown = Command("md", "Validate repository-owned Markdown.")
        let links = Command("links", "Validate internal Markdown links.")
        let mermaid = Command("mermaid", "Validate compatible Mermaid diagrams.")

        links.Subcommands.Add(
            createLeaf
                runtime
                "validate"
                "Validate that local Markdown link targets exist."
                rootOption
                formatOption
                "md links validate"
                "links"
                (runMarkdownLinks runtime)
        )

        mermaid.Subcommands.Add(createMermaidLeaf runtime rootOption formatOption)

        let wordCount = Command("word-count", "Inspect Markdown word counts.")
        wordCount.Subcommands.Add(createWordCountLeaf runtime rootOption formatOption)
        markdown.Subcommands.Add links
        markdown.Subcommands.Add mermaid
        markdown.Subcommands.Add wordCount
        root.Subcommands.Add governance
        root.Subcommands.Add markdown
        root

    let invokeWith runtime (args: string array) =
        let parseResult = createRootCommandWith runtime |> _.Parse(args)

        let invocationConfiguration =
            InvocationConfiguration(Output = runtime.Output, Error = runtime.Error)

        let exitCode = parseResult.Invoke(invocationConfiguration)

        if parseResult.Errors.Count > 0 then 2 else exitCode

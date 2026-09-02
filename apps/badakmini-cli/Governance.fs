namespace Badakmini.Cli

open System
open System.Collections.Generic
open System.Globalization
open System.IO
open System.Text.RegularExpressions

type MarkdownFile = { Path: string; WordCount: int }

type MermaidBlock =
    { Path: string
      StartLine: int
      Lines: (int * string) list }

type MermaidAccessibilityIssue =
    { Path: string
      Line: int
      Message: string }

type MermaidLegibilityIssue =
    { Path: string
      Line: int
      LabelRole: string
      ActualLength: int
      Limit: int
      Message: string }

type MarkdownLinkIssue = { Path: string; Target: string }

type GovernanceViolation =
    | WordLimitExceeded of MarkdownFile
    | MissingReadme of directoryPath: string
    | MissingDirectoryMap of readmePath: string
    | MissingMapEntry of readmePath: string * siblingPath: string
    | InvalidMapEntry of readmePath: string * target: string
    | InvalidMarkdownLink of MarkdownLinkIssue
    | MermaidAccessibilityViolation of MermaidAccessibilityIssue
    | MermaidLegibilityViolation of MermaidLegibilityIssue

type WordBudgetInspection =
    { MarkdownFiles: MarkdownFile list
      Violations: GovernanceViolation list }

type DirectoryMapInspection =
    { DirectoryCount: int
      Violations: GovernanceViolation list }

type MermaidInspection =
    { DiagramCount: int
      Violations: GovernanceViolation list }

type MarkdownLinkInspection =
    { MarkdownFileCount: int
      Violations: GovernanceViolation list }

module Governance =
    [<Literal>]
    let WordLimit = 750

    [<Literal>]
    let DirectoryMapHeading = "## Directory Map"

    let private wordPattern =
        Regex(@"[\p{L}\p{M}\p{N}]+(?:['’_-][\p{L}\p{M}\p{N}]+)*", RegexOptions.Compiled)

    let private markdownLinkPattern =
        Regex(@"(?<!!)\[[^\]]+\]\(\s*(?<target><[^>]+>|[^)\s]+)", RegexOptions.Compiled)

    let private markdownReferenceLinkPattern =
        Regex(@"^\s*\[[^\]]+\]:\s*(?<target><[^>]+>|[^\s]+)", RegexOptions.Compiled)

    let private markdownFencePattern =
        Regex(@"^\s*(?<fence>`{3,}|~{3,})", RegexOptions.Compiled)

    let private sectionHeadingPattern = Regex(@"^\s*#{1,2}\s+", RegexOptions.Compiled)

    let private mermaidFencePattern =
        Regex(@"^\s*(?<fence>`{3,}|~{3,})mermaid\s*$", RegexOptions.Compiled ||| RegexOptions.IgnoreCase)

    let private hexColorPattern = Regex(@"#[0-9a-fA-F]{3,8}\b", RegexOptions.Compiled)

    let private colorFunctionPattern =
        Regex(@"\b(?:rgb|rgba|hsl|hsla)\s*\(", RegexOptions.Compiled ||| RegexOptions.IgnoreCase)

    let private classDefPattern =
        Regex(@"^\s*classDef\s+\S+\s+(?<properties>.+?)\s*;?\s*$", RegexOptions.Compiled ||| RegexOptions.IgnoreCase)

    let private nodeLabelPattern =
        Regex(
            @"\b[A-Za-z_][\w-]*\s*(?:\(\[|\[\[|\[\(|\{\{|\(\(|\[|\{|\()(?<label>.*?)(?:\]\)|\]\]|\)\]|\}\}|\)\)|\]|\}|\))",
            RegexOptions.Compiled
        )

    let private stateNodePattern =
        Regex(@"^\s*state\s+[\""'](?<label>.+?)[\""']\s+as\s+", RegexOptions.Compiled ||| RegexOptions.IgnoreCase)

    let private namedBlockPattern =
        Regex(
            @"^\s*(?:requirement|functionalRequirement|performanceRequirement|interfaceRequirement|physicalRequirement|designConstraint)?\s*(?<label>[A-Za-z_][\w-]*)\s*\{\s*$",
            RegexOptions.Compiled ||| RegexOptions.IgnoreCase
        )

    let private pipeEdgeLabelPattern =
        Regex(@"\|(?<label>[^|]+)\|", RegexOptions.Compiled)

    let private textEdgeLabelPattern =
        Regex(@"(?:--|-\.|==)\s+(?<label>.+?)\s+(?:-->|-\.->|==>)", RegexOptions.Compiled)

    let private colonEdgeLabelPattern =
        Regex(@"(?:-->|--|\.\.|\|\||\}\|)[^:]*:\s*(?<label>.+?)\s*$", RegexOptions.Compiled)

    let private labelBreakPattern =
        Regex(@"(?:<br\s*/?>|\\n)", RegexOptions.Compiled ||| RegexOptions.IgnoreCase)

    let private markupPattern = Regex(@"<[^>]+>", RegexOptions.Compiled)
    let private whitespacePattern = Regex(@"\s+", RegexOptions.Compiled)

    let private htmlEntityPattern =
        Regex(@"&(?:amp|lt|gt|quot|apos|#39|#x[0-9a-f]+|#[0-9]+);", RegexOptions.Compiled ||| RegexOptions.IgnoreCase)

    let private stylePropertyPattern =
        Regex(@"(?<name>[a-zA-Z-]+)\s*:\s*(?<value>[^,\s;]+)", RegexOptions.Compiled)

    let private fillColors =
        set [ "#0173B2"; "#DE8F05"; "#029E73"; "#CC78BC"; "#CA9161"; "#808080" ]

    let private edgeColors = Set.add "#000000" fillColors
    let private textColors = set [ "#000000"; "#FFFFFF" ]

    let private compatibleMermaidHeaders =
        set
            [ "flowchart"
              "graph"
              "classDiagram"
              "stateDiagram"
              "stateDiagram-v2"
              "erDiagram"
              "requirementDiagram"
              "block" ]

    let private excludedMarkdownDirectories =
        HashSet<string>(
            [ ".git"
              ".nx"
              "node_modules"
              "bin"
              "obj"
              "_build"
              "deps"
              "coverage"
              "playwright-report"
              "test-results"
              "worktrees" ],
            StringComparer.OrdinalIgnoreCase
        )

    let countWords content = wordPattern.Matches(content).Count

    let private isMarkdown (path: string) =
        String.Equals(Path.GetExtension path, ".md", StringComparison.OrdinalIgnoreCase)

    let private normalizeRelativePath root path =
        Path.GetRelativePath(root, path).Replace(Path.DirectorySeparatorChar, '/')

    let private isWithinRoot fullRoot path =
        let relativePath = Path.GetRelativePath(fullRoot, path)

        relativePath <> ".."
        && not (relativePath.StartsWith($"..{Path.DirectorySeparatorChar}", StringComparison.Ordinal))

    let private isReparsePoint fileSystem (path: string) =
        fileSystem.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint)

    let private enumerateFilesRecursively fileSystem directory =
        seq {
            let directories = Stack<string>()
            directories.Push(directory)

            while directories.Count > 0 do
                let currentDirectory = directories.Pop()
                yield! fileSystem.EnumerateFiles currentDirectory

                for child in fileSystem.EnumerateDirectories currentDirectory do
                    directories.Push(child)
        }

    let private enumerateDirectoriesRecursively fileSystem directory =
        seq {
            let directories = Stack<string>()
            directories.Push(directory)

            while directories.Count > 0 do
                let currentDirectory = directories.Pop()

                for child in fileSystem.EnumerateDirectories currentDirectory do
                    yield child
                    directories.Push(child)
        }

    let private enumerateOwnedMarkdown fileSystem directory =
        seq {
            let directories = Stack<string>()
            directories.Push(directory)

            while directories.Count > 0 do
                let currentDirectory = directories.Pop()

                yield! fileSystem.EnumerateFiles currentDirectory |> Seq.filter isMarkdown

                for child in fileSystem.EnumerateDirectories currentDirectory do
                    if
                        not (excludedMarkdownDirectories.Contains(Path.GetFileName child))
                        && not (isReparsePoint fileSystem child)
                    then
                        directories.Push(child)
        }

    let private extractMermaidBlocks relativePath content =
        let lines = Regex.Split(content, "\r?\n")
        let blocks = ResizeArray<MermaidBlock>()
        let mutable openingFence = ""
        let mutable blockLines = ResizeArray<int * string>()

        for index, line in Array.indexed lines do
            if String.IsNullOrEmpty openingFence then
                let opening = mermaidFencePattern.Match line

                if opening.Success then
                    openingFence <- opening.Groups["fence"].Value
                    blockLines <- ResizeArray<int * string>()
            else
                let trimmed = line.Trim()

                let closesBlock =
                    trimmed.Length >= openingFence.Length
                    && trimmed |> Seq.forall ((=) openingFence[0])

                if closesBlock then
                    blocks.Add(
                        { Path = relativePath
                          StartLine = blockLines |> Seq.tryHead |> Option.map fst |> Option.defaultValue (index + 1)
                          Lines = blockLines |> Seq.toList }
                    )

                    openingFence <- ""
                else
                    blockLines.Add(index + 1, line)

        blocks |> Seq.toList

    let private diagramHeader block =
        let lines = block.Lines |> List.map (snd >> _.Trim()) |> List.toArray

        let rec findHeader index =
            if index >= lines.Length then
                None
            elif String.IsNullOrWhiteSpace lines[index] || lines[index].StartsWith("%%") then
                findHeader (index + 1)
            elif lines[index] = "---" then
                lines
                |> Array.indexed
                |> Array.tryFind (fun (lineIndex, line) -> lineIndex > index && line = "---")
                |> Option.bind (fun (closingIndex, _) -> findHeader (closingIndex + 1))
            else
                lines[index].Split([| ' '; '\t' |], StringSplitOptions.RemoveEmptyEntries)[0]
                |> Some

        findHeader 0

    let private isCompatibleMermaidBlock block =
        diagramHeader block |> Option.exists compatibleMermaidHeaders.Contains

    let private normalizeHexColor (value: string) =
        let value = value.ToUpperInvariant()

        if Regex.IsMatch(value, @"^#[0-9A-F]{6}$") then
            Some value
        else
            None

    let private parseStyleProperties (properties: string) =
        stylePropertyPattern.Matches(properties)
        |> Seq.cast<Match>
        |> Seq.map (fun property -> property.Groups["name"].Value.ToLowerInvariant(), property.Groups["value"].Value)
        |> Map.ofSeq

    let private parseHexChannel (value: string) (offset: int) =
        Int32.Parse(value.Substring(offset, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture)
        |> float
        |> fun channel -> channel / 255.0

    let private linearChannel channel =
        if channel <= 0.04045 then
            channel / 12.92
        else
            Math.Pow((channel + 0.055) / 1.055, 2.4)

    let private relativeLuminance (color: string) =
        0.2126 * linearChannel (parseHexChannel color 1)
        + 0.7152 * linearChannel (parseHexChannel color 3)
        + 0.0722 * linearChannel (parseHexChannel color 5)

    let private contrastRatio (left: string) (right: string) =
        let lighter = max (relativeLuminance left) (relativeLuminance right)
        let darker = min (relativeLuminance left) (relativeLuminance right)
        (lighter + 0.05) / (darker + 0.05)

    let private issue (block: MermaidBlock) (line: int) (message: string) =
        MermaidAccessibilityViolation
            { Path = block.Path
              Line = line
              Message = message }

    [<Literal>]
    let private NodeLabelLimit = 32

    [<Literal>]
    let private EdgeLabelLimit = 24

    let private graphemeLength (value: string) =
        StringInfo.ParseCombiningCharacters(value).Length

    let private decodeHtmlEntities (value: string) =
        htmlEntityPattern.Replace(
            value,
            MatchEvaluator(fun matched ->
                match matched.Value.ToLowerInvariant() with
                | "&amp;" -> "&"
                | "&lt;" -> "<"
                | "&gt;" -> ">"
                | "&quot;" -> "\""
                | "&apos;"
                | "&#39;" -> "'"
                | numeric when numeric.StartsWith("&#x", StringComparison.Ordinal) ->
                    Char.ConvertFromUtf32(Convert.ToInt32(numeric[3 .. numeric.Length - 2], 16))
                | numeric ->
                    Char.ConvertFromUtf32(Int32.Parse(numeric[2 .. numeric.Length - 2], CultureInfo.InvariantCulture)))
        )

    let private normalizeLabelSegment (value: string) =
        value
        |> decodeHtmlEntities
        |> fun text -> markupPattern.Replace(text, "")
        |> fun text -> text.Replace("**", "").Replace("__", "")
        |> fun text -> whitespacePattern.Replace(text, " ")
        |> _.Trim([| ' '; '\t'; '\r'; '\n'; '"'; '\''; '`' |])

    let private legibilityIssue (block: MermaidBlock) line role actual limit message =
        MermaidLegibilityViolation
            { Path = block.Path
              Line = line
              LabelRole = role
              ActualLength = actual
              Limit = limit
              Message = message }

    let private validateLabel (block: MermaidBlock) line role limit rawLabel =
        [ for segment in labelBreakPattern.Split rawLabel do
              let normalized = normalizeLabelSegment segment

              if not (String.IsNullOrWhiteSpace normalized) then
                  let actual = graphemeLength normalized

                  if actual > limit then
                      yield
                          legibilityIssue
                              block
                              line
                              role
                              actual
                              limit
                              $"Mermaid {role} label segment has {actual} graphemes; maximum is {limit}" ]

    let private ignoredLegibilityLine (line: string) =
        let trimmed = line.TrimStart()

        String.IsNullOrWhiteSpace trimmed
        || trimmed.StartsWith("%%", StringComparison.Ordinal)
        || trimmed.StartsWith("---", StringComparison.Ordinal)
        || trimmed.StartsWith("classDef ", StringComparison.OrdinalIgnoreCase)
        || trimmed.StartsWith("style ", StringComparison.OrdinalIgnoreCase)
        || trimmed.StartsWith("linkStyle ", StringComparison.OrdinalIgnoreCase)
        || trimmed.StartsWith("direction ", StringComparison.OrdinalIgnoreCase)
        || trimmed.StartsWith("columns ", StringComparison.OrdinalIgnoreCase)
        || trimmed.StartsWith("+", StringComparison.Ordinal)
        || trimmed.StartsWith("-", StringComparison.Ordinal)
        || trimmed.StartsWith("#", StringComparison.Ordinal)
        || Regex.IsMatch(trimmed, @"^(id|text|risk|verifymethod|type|docref):", RegexOptions.IgnoreCase)
        || Regex.IsMatch(trimmed, @"^[A-Za-z_][\w-]*\s+[A-Za-z_][\w-]*\s*$")

    let private validateMermaidLegibility (block: MermaidBlock) =
        let header = diagramHeader block |> Option.defaultValue ""

        [ for lineNumber, line in block.Lines do
              if not (ignoredLegibilityLine line) then
                  for matched in nodeLabelPattern.Matches(line) |> Seq.cast<Match> do
                      yield! validateLabel block lineNumber "node" NodeLabelLimit matched.Groups["label"].Value

                  let stateNode = stateNodePattern.Match line

                  if stateNode.Success then
                      yield! validateLabel block lineNumber "state" NodeLabelLimit stateNode.Groups["label"].Value

                  if header = "erDiagram" || header = "requirementDiagram" then
                      let namedBlock = namedBlockPattern.Match line

                      if namedBlock.Success then
                          yield! validateLabel block lineNumber "node" NodeLabelLimit namedBlock.Groups["label"].Value

                  for matched in pipeEdgeLabelPattern.Matches(line) |> Seq.cast<Match> do
                      yield! validateLabel block lineNumber "edge" EdgeLabelLimit matched.Groups["label"].Value

                  let textEdge = textEdgeLabelPattern.Match line

                  if textEdge.Success then
                      yield! validateLabel block lineNumber "edge" EdgeLabelLimit textEdge.Groups["label"].Value

                  let supportsColonEdges =
                      header.StartsWith("stateDiagram", StringComparison.Ordinal)
                      || header = "classDiagram"
                      || header = "erDiagram"

                  let colonEdge = colonEdgeLabelPattern.Match line

                  if supportsColonEdges && colonEdge.Success then
                      let label = colonEdge.Groups["label"].Value

                      if
                          header.StartsWith("stateDiagram", StringComparison.Ordinal)
                          && label.Contains(';')
                      then
                          yield
                              legibilityIssue
                                  block
                                  lineNumber
                                  "transition"
                                  (normalizeLabelSegment label |> graphemeLength)
                                  EdgeLabelLimit
                                  "Mermaid state transition labels must not contain semicolons"
                      else
                          yield! validateLabel block lineNumber "edge" EdgeLabelLimit label ]

    let private validateClassDef (block: MermaidBlock) (lineNumber: int) (properties: string) =
        let properties = parseStyleProperties properties
        let fill = Map.tryFind "fill" properties
        let stroke = Map.tryFind "stroke" properties
        let text = Map.tryFind "color" properties

        let normalizedFill = fill |> Option.bind normalizeHexColor
        let normalizedStroke = stroke |> Option.bind normalizeHexColor
        let normalizedText = text |> Option.bind normalizeHexColor

        let violations =
            [ match fill with
              | Some value when not (normalizedFill |> Option.exists fillColors.Contains) ->
                  yield issue block lineNumber $"Mermaid node fill {value} must use a six-digit accessible fill color"
              | Some _ ->
                  match stroke with
                  | Some value when normalizedStroke = Some "#000000" -> ()
                  | Some value ->
                      yield issue block lineNumber $"Mermaid colored nodes require stroke:#000000, found {value}"
                  | None -> yield issue block lineNumber "Mermaid colored nodes require stroke:#000000"

                  match text with
                  | Some value when normalizedText |> Option.exists textColors.Contains -> ()
                  | Some value ->
                      yield issue block lineNumber $"Mermaid colored nodes require black or white text, found {value}"
                  | None ->
                      yield issue block lineNumber "Mermaid colored nodes require an explicit black or white text color"

                  match normalizedFill, normalizedText with
                  | Some fillColor, Some textColor when
                      Set.contains textColor textColors && contrastRatio fillColor textColor < 4.5
                      ->
                      yield
                          issue
                              block
                              lineNumber
                              $"Mermaid text contrast is {contrastRatio fillColor textColor:F2}:1; expected at least 4.5:1"
                  | _ -> ()
              | None ->
                  match text with
                  | Some value ->
                      yield issue block lineNumber $"Mermaid text color {value} requires an explicit accessible fill"
                  | None -> ()

                  match stroke with
                  | Some value when not (normalizedStroke |> Option.exists edgeColors.Contains) ->
                      yield
                          issue
                              block
                              lineNumber
                              $"Mermaid edge stroke {value} must use a six-digit accessible palette color"
                  | _ -> () ]

        violations

    let private containsColorOutsideClassDef (line: string) =
        hexColorPattern.IsMatch(line)
        || colorFunctionPattern.IsMatch(line)
        || ((line.TrimStart().StartsWith("style ", StringComparison.OrdinalIgnoreCase)
             || line.TrimStart().StartsWith("linkStyle ", StringComparison.OrdinalIgnoreCase))
            && stylePropertyPattern.IsMatch(line))

    let private isLineComment (line: string) =
        let trimmed = line.TrimStart()

        trimmed.StartsWith("%%", StringComparison.Ordinal)
        && not (trimmed.StartsWith("%%{", StringComparison.Ordinal))

    let private validateMermaidBlock (block: MermaidBlock) =
        let classDefViolations =
            [ for lineNumber, line in block.Lines do
                  let classDefinition = classDefPattern.Match line

                  if classDefinition.Success then
                      yield! validateClassDef block lineNumber classDefinition.Groups["properties"].Value
                  elif not (isLineComment line) && containsColorOutsideClassDef line then
                      yield issue block lineNumber "Mermaid custom colors must be declared with classDef" ]

        classDefViolations @ validateMermaidLegibility block

    let private inspectMermaidAccessibilityCore fileSystem fullRoot markdownFiles =
        let blocks =
            markdownFiles
            |> Seq.sort
            |> Seq.collect (fun path ->
                fileSystem.ReadAllText path
                |> extractMermaidBlocks (normalizeRelativePath fullRoot path))
            |> Seq.filter isCompatibleMermaidBlock
            |> Seq.toList

        let violations =
            [ for block in blocks do
                  yield! validateMermaidBlock block ]

        blocks.Length, violations

    let inspectMermaidAccessibilityWith fileSystem root =
        let fullRoot = Path.GetFullPath root

        let diagramCount, violations =
            enumerateOwnedMarkdown fileSystem fullRoot
            |> inspectMermaidAccessibilityCore fileSystem fullRoot

        { DiagramCount = diagramCount
          Violations = violations }

    let inspectMermaidAccessibilityAtWith fileSystem root relativeFiles =
        let fullRoot = Path.GetFullPath root

        let selectedFiles =
            relativeFiles
            |> Seq.map (fun relativePath ->
                if String.IsNullOrWhiteSpace relativePath || Path.IsPathRooted relativePath then
                    invalidArg "file" "Mermaid files must be non-empty repository-relative Markdown paths."

                let absolutePath =
                    relativePath.Replace('/', Path.DirectorySeparatorChar)
                    |> fun path -> Path.GetFullPath(Path.Combine(fullRoot, path))

                if
                    not (isWithinRoot fullRoot absolutePath)
                    || not (isMarkdown absolutePath)
                    || not (fileSystem.FileExists absolutePath)
                    || isReparsePoint fileSystem absolutePath
                then
                    invalidArg
                        "file"
                        $"Mermaid file '{relativePath}' must be an existing repository-owned Markdown file."

                absolutePath)
            |> Seq.distinct
            |> Seq.toList

        let files =
            if List.isEmpty selectedFiles then
                enumerateOwnedMarkdown fileSystem fullRoot |> Seq.toList
            else
                selectedFiles

        let diagramCount, violations =
            inspectMermaidAccessibilityCore fileSystem fullRoot files

        { DiagramCount = diagramCount
          Violations = violations }

    let scanRepositoryWith fileSystem root =
        let fullRoot = Path.GetFullPath root
        let agentsPath = Path.Combine(fullRoot, "AGENTS.md")
        let governancePath = Path.Combine(fullRoot, "repo-governance")

        seq {
            if fileSystem.FileExists agentsPath then
                yield agentsPath

            if fileSystem.DirectoryExists governancePath then
                yield! enumerateFilesRecursively fileSystem governancePath |> Seq.filter isMarkdown
        }
        |> Seq.map (fun path ->
            { Path = normalizeRelativePath fullRoot path
              WordCount = fileSystem.ReadAllText path |> countWords })
        |> Seq.sortBy _.Path
        |> Seq.toList

    let findViolations files =
        files |> List.filter (fun file -> file.WordCount > WordLimit)

    let inspectWordBudgetWith fileSystem root =
        let markdownFiles = scanRepositoryWith fileSystem root

        { MarkdownFiles = markdownFiles
          Violations = markdownFiles |> findViolations |> List.map WordLimitExceeded }

    let inspectFileWordCountWith fileSystem root relativePath =
        if String.IsNullOrWhiteSpace relativePath then
            invalidArg (nameof relativePath) "File must be relative to the repository root."

        if Path.IsPathRooted relativePath then
            invalidArg (nameof relativePath) "File must be relative to the repository root."

        let fullRoot = Path.GetFullPath root
        let filePath = Path.GetFullPath(Path.Combine(fullRoot, relativePath))
        let normalizedRelativePath = Path.GetRelativePath(fullRoot, filePath)

        if
            normalizedRelativePath = ".."
            || normalizedRelativePath.StartsWith($"..{Path.DirectorySeparatorChar}", StringComparison.Ordinal)
        then
            invalidArg (nameof relativePath) "File must be within the repository root."

        if not (fileSystem.FileExists filePath) then
            invalidArg (nameof relativePath) $"File does not exist: {relativePath}"

        { Path = normalizeRelativePath fullRoot filePath
          WordCount = fileSystem.ReadAllText filePath |> countWords }

    let private mappedDirectories fileSystem fullRoot relativeDirectory =
        if String.IsNullOrWhiteSpace relativeDirectory then
            invalidArg (nameof relativeDirectory) "Directory must be relative to the repository root."

        if Path.IsPathRooted relativeDirectory then
            invalidArg (nameof relativeDirectory) "Directory must be relative to the repository root."

        let directoryPath = Path.GetFullPath(Path.Combine(fullRoot, relativeDirectory))
        let normalizedRelativePath = Path.GetRelativePath(fullRoot, directoryPath)

        if
            normalizedRelativePath = ".."
            || normalizedRelativePath.StartsWith($"..{Path.DirectorySeparatorChar}", StringComparison.Ordinal)
        then
            invalidArg (nameof relativeDirectory) "Directory must be within the repository root."

        if not (fileSystem.DirectoryExists directoryPath) then
            []
        else
            directoryPath
            :: (enumerateDirectoriesRecursively fileSystem directoryPath |> Seq.toList)
            |> List.sort

    let private extractDirectoryMapTargets content =
        let lines = Regex.Split(content, "\r?\n")

        match lines |> Array.tryFindIndex (fun line -> line.Trim() = DirectoryMapHeading) with
        | None -> None
        | Some headingIndex ->
            lines
            |> Seq.skip (headingIndex + 1)
            |> Seq.takeWhile (sectionHeadingPattern.IsMatch >> not)
            |> String.concat "\n"
            |> markdownLinkPattern.Matches
            |> Seq.cast<Match>
            |> Seq.map (fun link -> link.Groups["target"].Value)
            |> Seq.toList
            |> Some

    let private cleanLinkTarget (target: string) =
        let target = target.Trim().Trim([| '<'; '>' |])
        let suffixIndex = target.IndexOfAny([| '#'; '?' |])

        if suffixIndex >= 0 then
            target.Substring(0, suffixIndex)
        else
            target

    let private extractMarkdownLinkTargets content =
        let lines = Regex.Split(content, "\r?\n")
        let targets = ResizeArray<string>()
        let mutable openingFence = ""

        for line in lines do
            let fence = markdownFencePattern.Match line

            if String.IsNullOrEmpty openingFence then
                if fence.Success then
                    openingFence <- fence.Groups["fence"].Value
                else
                    markdownLinkPattern.Matches(line)
                    |> Seq.cast<Match>
                    |> Seq.iter (fun link -> targets.Add(link.Groups["target"].Value))

                    markdownReferenceLinkPattern.Matches(line)
                    |> Seq.cast<Match>
                    |> Seq.iter (fun link -> targets.Add(link.Groups["target"].Value))
            elif
                fence.Success
                && fence.Groups["fence"].Value[0] = openingFence[0]
                && fence.Groups["fence"].Value.Length >= openingFence.Length
            then
                openingFence <- ""

        targets |> Seq.toList

    let private isArchivedPlanMarkdown fullRoot path =
        let relativePath = normalizeRelativePath fullRoot path

        relativePath.StartsWith("plans/done/", StringComparison.OrdinalIgnoreCase)

    let private hasExistingMarkdownTarget fileSystem fullRoot (sourcePath: string) (target: string) =
        try
            let cleanTarget = cleanLinkTarget target

            if String.IsNullOrWhiteSpace cleanTarget then
                true
            else
                let decodedTarget = Uri.UnescapeDataString cleanTarget

                if Path.IsPathRooted decodedTarget then
                    false
                else
                    let mutable absoluteUri = Unchecked.defaultof<Uri>

                    if Uri.TryCreate(cleanTarget, UriKind.Absolute, &absoluteUri) then
                        true
                    else
                        let sourceDirectory = Path.GetDirectoryName sourcePath

                        let targetPath =
                            decodedTarget.Replace('/', Path.DirectorySeparatorChar)
                            |> fun path -> Path.GetFullPath(Path.Combine(sourceDirectory, path))

                        isWithinRoot fullRoot targetPath
                        && (fileSystem.FileExists targetPath || fileSystem.DirectoryExists targetPath)
        with
        | :? ArgumentException
        | :? NotSupportedException -> false

    let inspectMarkdownLinksWith fileSystem root =
        let fullRoot = Path.GetFullPath root

        let markdownFiles =
            enumerateOwnedMarkdown fileSystem fullRoot
            |> Seq.filter (isArchivedPlanMarkdown fullRoot >> not)
            |> Seq.sort
            |> Seq.toList

        let violations =
            [ for path in markdownFiles do
                  let relativePath = normalizeRelativePath fullRoot path

                  for target in fileSystem.ReadAllText path |> extractMarkdownLinkTargets do
                      if not (hasExistingMarkdownTarget fileSystem fullRoot path target) then
                          yield InvalidMarkdownLink { Path = relativePath; Target = target } ]

        { MarkdownFileCount = markdownFiles.Length
          Violations = violations }

    let private pathsEqual left right =
        String.Equals(Path.GetFullPath left, Path.GetFullPath right, StringComparison.Ordinal)

    let private resolveMappedSibling fileSystem directory siblings target =
        try
            let cleanTarget = cleanLinkTarget target
            let mutable absoluteUri = Unchecked.defaultof<Uri>

            if
                String.IsNullOrWhiteSpace cleanTarget
                || Path.IsPathRooted cleanTarget
                || Uri.TryCreate(cleanTarget, UriKind.Absolute, &absoluteUri)
            then
                None
            else
                let targetPath =
                    cleanTarget
                    |> Uri.UnescapeDataString
                    |> fun path -> path.Replace('/', Path.DirectorySeparatorChar)
                    |> fun path -> Path.GetFullPath(Path.Combine(directory, path))

                siblings
                |> List.tryFind (fun sibling ->
                    pathsEqual sibling targetPath
                    || (fileSystem.DirectoryExists sibling
                        && fileSystem.FileExists targetPath
                        && pathsEqual (Path.Combine(sibling, "README.md")) targetPath))
        with
        | :? ArgumentException
        | :? NotSupportedException -> None

    let private validateDirectoryMap fileSystem fullRoot directory =
        let readmePath = Path.Combine(directory, "README.md")
        let relativeDirectory = normalizeRelativePath fullRoot directory

        if not (fileSystem.FileExists readmePath) then
            [ MissingReadme relativeDirectory ]
        else
            let relativeReadme = normalizeRelativePath fullRoot readmePath

            match fileSystem.ReadAllText readmePath |> extractDirectoryMapTargets with
            | None -> [ MissingDirectoryMap relativeReadme ]
            | Some targets ->
                let siblings =
                    fileSystem.EnumerateFileSystemEntries directory
                    |> Seq.filter (pathsEqual readmePath >> not)
                    |> Seq.sort
                    |> Seq.toList

                let mappedSiblings, invalidTargets =
                    targets
                    |> List.fold
                        (fun (mapped, invalid) target ->
                            match resolveMappedSibling fileSystem directory siblings target with
                            | Some sibling -> Set.add sibling mapped, invalid
                            | None -> mapped, target :: invalid)
                        (Set.empty, [])

                [ for sibling in siblings do
                      if not (Set.contains sibling mappedSiblings) then
                          yield MissingMapEntry(relativeReadme, normalizeRelativePath fullRoot sibling)

                  for target in List.rev invalidTargets do
                      yield InvalidMapEntry(relativeReadme, target) ]

    let inspectDirectoryMapsAtWith fileSystem root relativeDirectory =
        let fullRoot = Path.GetFullPath root
        let directories = mappedDirectories fileSystem fullRoot relativeDirectory

        { DirectoryCount = directories.Length
          Violations =
            [ for directory in directories do
                  yield! validateDirectoryMap fileSystem fullRoot directory ] }

    let inspectDirectoryMapsWith fileSystem root =
        inspectDirectoryMapsAtWith fileSystem root "repo-governance"

    let formatViolation violation =
        match violation with
        | WordLimitExceeded file -> $"{file.Path}: {file.WordCount} words (maximum {WordLimit})"
        | MissingReadme directoryPath -> $"{directoryPath}: missing README.md"
        | MissingDirectoryMap readmePath -> $"{readmePath}: missing \"{DirectoryMapHeading}\" section"
        | MissingMapEntry(readmePath, siblingPath) ->
            $"{readmePath}: directory map does not include sibling: {siblingPath}"
        | InvalidMapEntry(readmePath, target) ->
            $"{readmePath}: directory map links a nonexistent or non-sibling entry: {target}"
        | InvalidMarkdownLink issue -> $"{issue.Path}: Markdown link target does not exist: {issue.Target}"
        | MermaidAccessibilityViolation issue -> $"{issue.Path}:{issue.Line}: {issue.Message}"
        | MermaidLegibilityViolation issue -> $"{issue.Path}:{issue.Line}: {issue.Message}"

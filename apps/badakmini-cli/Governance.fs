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

type GovernanceViolation =
    | WordLimitExceeded of MarkdownFile
    | MissingReadme of directoryPath: string
    | MissingDirectoryMap of readmePath: string
    | MissingMapEntry of readmePath: string * siblingPath: string
    | InvalidMapEntry of readmePath: string * target: string
    | MermaidAccessibilityViolation of MermaidAccessibilityIssue

type WordBudgetInspection =
    { MarkdownFiles: MarkdownFile list
      Violations: GovernanceViolation list }

type DirectoryMapInspection =
    { DirectoryCount: int
      Violations: GovernanceViolation list }

type MermaidInspection =
    { DiagramCount: int
      Violations: GovernanceViolation list }

module Governance =
    [<Literal>]
    let WordLimit = 500

    [<Literal>]
    let DirectoryMapHeading = "## Directory Map"

    let private wordPattern =
        Regex(@"[\p{L}\p{M}\p{N}]+(?:['’_-][\p{L}\p{M}\p{N}]+)*", RegexOptions.Compiled)

    let private markdownLinkPattern =
        Regex(@"(?<!!)\[[^\]]+\]\(\s*(?<target><[^>]+>|[^)\s]+)", RegexOptions.Compiled)

    let private sectionHeadingPattern = Regex(@"^\s*#{1,2}\s+", RegexOptions.Compiled)

    let private mermaidFencePattern =
        Regex(@"^\s*(?<fence>`{3,}|~{3,})mermaid\s*$", RegexOptions.Compiled ||| RegexOptions.IgnoreCase)

    let private hexColorPattern = Regex(@"#[0-9a-fA-F]{3,8}\b", RegexOptions.Compiled)

    let private colorFunctionPattern =
        Regex(@"\b(?:rgb|rgba|hsl|hsla)\s*\(", RegexOptions.Compiled ||| RegexOptions.IgnoreCase)

    let private classDefPattern =
        Regex(@"^\s*classDef\s+\S+\s+(?<properties>.+?)\s*;?\s*$", RegexOptions.Compiled ||| RegexOptions.IgnoreCase)

    let private stylePropertyPattern =
        Regex(@"(?<name>[a-zA-Z-]+)\s*:\s*(?<value>[^,\s;]+)", RegexOptions.Compiled)

    [<Literal>]
    let private PaletteCommentPrefix = "%% Accessible palette:"

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
              "test-results" ],
            StringComparer.OrdinalIgnoreCase
        )

    let countWords content = wordPattern.Matches(content).Count

    let private isMarkdown (path: string) =
        String.Equals(Path.GetExtension path, ".md", StringComparison.OrdinalIgnoreCase)

    let private normalizeRelativePath root path =
        Path.GetRelativePath(root, path).Replace(Path.DirectorySeparatorChar, '/')

    let private isReparsePoint (path: string) =
        File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint)

    let private enumerateOwnedMarkdown directory =
        seq {
            let directories = Stack<string>()
            directories.Push(directory)

            while directories.Count > 0 do
                let currentDirectory = directories.Pop()

                yield! Directory.EnumerateFiles(currentDirectory) |> Seq.filter isMarkdown

                for child in Directory.EnumerateDirectories(currentDirectory) do
                    if
                        not (excludedMarkdownDirectories.Contains(Path.GetFileName child))
                        && not (isReparsePoint child)
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

        let semanticColors =
            seq {
                match normalizedFill with
                | Some color when Set.contains color fillColors -> yield color
                | _ -> ()

                match normalizedFill, normalizedStroke with
                | None, Some color when Set.contains color fillColors -> yield color
                | _ -> ()
            }
            |> Set.ofSeq

        violations, semanticColors

    let private containsColorOutsideClassDef (line: string) =
        hexColorPattern.IsMatch(line)
        || colorFunctionPattern.IsMatch(line)
        || ((line.TrimStart().StartsWith("style ", StringComparison.OrdinalIgnoreCase)
             || line.TrimStart().StartsWith("linkStyle ", StringComparison.OrdinalIgnoreCase))
            && stylePropertyPattern.IsMatch(line))

    let private validateMermaidBlock (block: MermaidBlock) =
        let paletteComments =
            block.Lines
            |> List.filter (fun (_, line) ->
                line.TrimStart().StartsWith(PaletteCommentPrefix, StringComparison.OrdinalIgnoreCase))

        let mutable semanticColors = Set.empty

        let classDefViolations =
            [ for lineNumber, line in block.Lines do
                  let classDefinition = classDefPattern.Match line

                  if classDefinition.Success then
                      let violations, colors =
                          validateClassDef block lineNumber classDefinition.Groups["properties"].Value

                      semanticColors <- Set.union semanticColors colors
                      yield! violations
                  elif
                      not (line.TrimStart().StartsWith(PaletteCommentPrefix, StringComparison.OrdinalIgnoreCase))
                      && containsColorOutsideClassDef line
                  then
                      yield issue block lineNumber "Mermaid custom colors must be declared with classDef" ]

        let paletteViolations =
            if Set.isEmpty semanticColors then
                match paletteComments with
                | [] -> []
                | (lineNumber, _) :: _ ->
                    [ issue block lineNumber "Mermaid palette comment does not correspond to accessible classDef colors" ]
            elif paletteComments.Length <> 1 then
                [ issue
                      block
                      block.StartLine
                      "Colored Mermaid diagrams require exactly one '%% Accessible palette:' comment" ]
            else
                let lineNumber, comment = paletteComments.Head

                let documentedColors =
                    hexColorPattern.Matches(comment)
                    |> Seq.cast<Match>
                    |> Seq.choose (fun color -> normalizeHexColor color.Value)
                    |> Seq.filter fillColors.Contains
                    |> Set.ofSeq

                if documentedColors = semanticColors then
                    []
                else
                    [ issue
                          block
                          lineNumber
                          "Mermaid palette comment must list exactly the accessible colors used by classDef" ]

        classDefViolations @ paletteViolations

    let private inspectMermaidAccessibilityCore fullRoot =
        let blocks =
            enumerateOwnedMarkdown fullRoot
            |> Seq.sort
            |> Seq.collect (fun path ->
                File.ReadAllText(path)
                |> extractMermaidBlocks (normalizeRelativePath fullRoot path))
            |> Seq.filter isCompatibleMermaidBlock
            |> Seq.toList

        let violations =
            [ for block in blocks do
                  yield! validateMermaidBlock block ]

        blocks.Length, violations

    let inspectMermaidAccessibility root =
        let diagramCount, violations =
            root |> Path.GetFullPath |> inspectMermaidAccessibilityCore

        { DiagramCount = diagramCount
          Violations = violations }

    let scanRepository root =
        let fullRoot = Path.GetFullPath root
        let agentsPath = Path.Combine(fullRoot, "AGENTS.md")
        let governancePath = Path.Combine(fullRoot, "repo-governance")

        seq {
            if File.Exists agentsPath then
                yield agentsPath

            if Directory.Exists governancePath then
                yield!
                    Directory.EnumerateFiles(governancePath, "*", SearchOption.AllDirectories)
                    |> Seq.filter isMarkdown
        }
        |> Seq.map (fun path ->
            { Path = normalizeRelativePath fullRoot path
              WordCount = File.ReadAllText(path) |> countWords })
        |> Seq.sortBy _.Path
        |> Seq.toList

    let findViolations files =
        files |> List.filter (fun file -> file.WordCount > WordLimit)

    let inspectWordBudget root =
        let markdownFiles = scanRepository root

        { MarkdownFiles = markdownFiles
          Violations = markdownFiles |> findViolations |> List.map WordLimitExceeded }

    let private mappedDirectories fullRoot relativeDirectory =
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

        if not (Directory.Exists directoryPath) then
            []
        else
            directoryPath
            :: (Directory.EnumerateDirectories(directoryPath, "*", SearchOption.AllDirectories)
                |> Seq.toList)
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

    let private pathsEqual left right =
        String.Equals(Path.GetFullPath left, Path.GetFullPath right, StringComparison.Ordinal)

    let private resolveMappedSibling directory siblings target =
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
                    || (Directory.Exists sibling
                        && File.Exists targetPath
                        && pathsEqual (Path.Combine(sibling, "README.md")) targetPath))
        with
        | :? ArgumentException
        | :? NotSupportedException -> None

    let private validateDirectoryMap fullRoot directory =
        let readmePath = Path.Combine(directory, "README.md")
        let relativeDirectory = normalizeRelativePath fullRoot directory

        if not (File.Exists readmePath) then
            [ MissingReadme relativeDirectory ]
        else
            let relativeReadme = normalizeRelativePath fullRoot readmePath

            match File.ReadAllText(readmePath) |> extractDirectoryMapTargets with
            | None -> [ MissingDirectoryMap relativeReadme ]
            | Some targets ->
                let siblings =
                    Directory.EnumerateFileSystemEntries(directory)
                    |> Seq.filter (pathsEqual readmePath >> not)
                    |> Seq.sort
                    |> Seq.toList

                let mappedSiblings, invalidTargets =
                    targets
                    |> List.fold
                        (fun (mapped, invalid) target ->
                            match resolveMappedSibling directory siblings target with
                            | Some sibling -> Set.add sibling mapped, invalid
                            | None -> mapped, target :: invalid)
                        (Set.empty, [])

                [ for sibling in siblings do
                      if not (Set.contains sibling mappedSiblings) then
                          yield MissingMapEntry(relativeReadme, normalizeRelativePath fullRoot sibling)

                  for target in List.rev invalidTargets do
                      yield InvalidMapEntry(relativeReadme, target) ]

    let inspectDirectoryMapsAt root relativeDirectory =
        let fullRoot = Path.GetFullPath root
        let directories = mappedDirectories fullRoot relativeDirectory

        { DirectoryCount = directories.Length
          Violations =
            [ for directory in directories do
                  yield! validateDirectoryMap fullRoot directory ] }

    let inspectDirectoryMaps root =
        inspectDirectoryMapsAt root "repo-governance"

    let formatViolation violation =
        match violation with
        | WordLimitExceeded file -> $"{file.Path}: {file.WordCount} words (maximum {WordLimit})"
        | MissingReadme directoryPath -> $"{directoryPath}: missing README.md"
        | MissingDirectoryMap readmePath -> $"{readmePath}: missing \"{DirectoryMapHeading}\" section"
        | MissingMapEntry(readmePath, siblingPath) ->
            $"{readmePath}: directory map does not include sibling: {siblingPath}"
        | InvalidMapEntry(readmePath, target) ->
            $"{readmePath}: directory map links a nonexistent or non-sibling entry: {target}"
        | MermaidAccessibilityViolation issue -> $"{issue.Path}:{issue.Line}: {issue.Message}"

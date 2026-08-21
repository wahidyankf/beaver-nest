namespace Badakmini.Cli

open System
open System.IO
open System.Text.RegularExpressions

type MarkdownFile =
    { Path: string
      WordCount: int }

type GovernanceViolation =
    | WordLimitExceeded of MarkdownFile
    | MissingReadme of directoryPath: string
    | MissingDirectoryMap of readmePath: string
    | MissingMapEntry of readmePath: string * siblingPath: string
    | InvalidMapEntry of readmePath: string * target: string

type RepositoryInspection =
    { MarkdownFiles: MarkdownFile list
      GovernanceDirectoryCount: int
      Violations: GovernanceViolation list }

module Governance =
    [<Literal>]
    let wordLimit = 500

    [<Literal>]
    let directoryMapHeading = "## Directory Map"

    let private wordPattern =
        Regex(
            @"[\p{L}\p{M}\p{N}]+(?:['’_-][\p{L}\p{M}\p{N}]+)*",
            RegexOptions.Compiled
        )

    let private markdownLinkPattern =
        Regex(
            @"(?<!!)\[[^\]]+\]\(\s*(?<target><[^>]+>|[^)\s]+)",
            RegexOptions.Compiled
        )

    let private sectionHeadingPattern =
        Regex(@"^\s*#{1,2}\s+", RegexOptions.Compiled)

    let countWords content = wordPattern.Matches(content).Count

    let private isMarkdown (path: string) =
        String.Equals(Path.GetExtension path, ".md", StringComparison.OrdinalIgnoreCase)

    let private normalizeRelativePath root path =
        Path.GetRelativePath(root, path).Replace(Path.DirectorySeparatorChar, '/')

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
        files |> List.filter (fun file -> file.WordCount > wordLimit)

    let private governanceDirectories fullRoot =
        let governancePath = Path.Combine(fullRoot, "repo-governance")

        if not (Directory.Exists governancePath) then
            []
        else
            governancePath
            :: (Directory.EnumerateDirectories(
                    governancePath,
                    "*",
                    SearchOption.AllDirectories
                )
                |> Seq.toList)
            |> List.sort

    let private extractDirectoryMapTargets content =
        let lines = Regex.Split(content, "\r?\n")

        match
            lines
            |> Array.tryFindIndex (fun line -> line.Trim() = directoryMapHeading)
        with
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
        String.Equals(
            Path.GetFullPath left,
            Path.GetFullPath right,
            StringComparison.Ordinal
        )

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
                          yield
                              MissingMapEntry(
                                  relativeReadme,
                                  normalizeRelativePath fullRoot sibling
                              )

                  for target in List.rev invalidTargets do
                      yield InvalidMapEntry(relativeReadme, target) ]

    let inspectRepository root =
        let fullRoot = Path.GetFullPath root
        let markdownFiles = scanRepository fullRoot
        let directories = governanceDirectories fullRoot

        let violations =
            [ yield!
                  markdownFiles
                  |> findViolations
                  |> List.map WordLimitExceeded

              for directory in directories do
                  yield! validateDirectoryMap fullRoot directory ]

        { MarkdownFiles = markdownFiles
          GovernanceDirectoryCount = directories.Length
          Violations = violations }

    let formatViolation violation =
        match violation with
        | WordLimitExceeded file ->
            $"{file.Path}: {file.WordCount} words (maximum {wordLimit})"
        | MissingReadme directoryPath ->
            $"{directoryPath}: missing README.md"
        | MissingDirectoryMap readmePath ->
            $"{readmePath}: missing \"{directoryMapHeading}\" section"
        | MissingMapEntry(readmePath, siblingPath) ->
            $"{readmePath}: directory map does not include sibling: {siblingPath}"
        | InvalidMapEntry(readmePath, target) ->
            $"{readmePath}: directory map links a nonexistent or non-sibling entry: {target}"

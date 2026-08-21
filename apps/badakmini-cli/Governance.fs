namespace Badakmini.Cli

open System
open System.IO
open System.Text.RegularExpressions

type MarkdownFile =
    { Path: string
      WordCount: int }

module Governance =
    [<Literal>]
    let wordLimit = 500

    let private wordPattern =
        Regex(
            @"[\p{L}\p{M}\p{N}]+(?:['’_-][\p{L}\p{M}\p{N}]+)*",
            RegexOptions.Compiled
        )

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

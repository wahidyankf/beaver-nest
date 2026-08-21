module Badakmini.Cli.Tests

open System
open System.IO
open Xunit
open Badakmini.Cli

type private TemporaryRepository() =
    let root =
        Path.Combine(Path.GetTempPath(), $"badakmini-cli-{Guid.NewGuid():N}")

    do Directory.CreateDirectory(root) |> ignore

    member _.Root = root

    member _.Write(relativePath: string, content: string) =
        let path = Path.Combine(root, relativePath)
        Directory.CreateDirectory(Path.GetDirectoryName path) |> ignore
        File.WriteAllText(path, content)

    interface IDisposable with
        member _.Dispose() = Directory.Delete(root, true)

let private words count = Seq.replicate count "word" |> String.concat " "

[<Fact>]
let ``countWords counts text rather than Markdown punctuation`` () =
    let content = "# Hello, can't-stop! naïve 42"

    Assert.Equal(4, Governance.countWords content)

[<Fact>]
let ``scanRepository includes AGENTS and nested governance Markdown only`` () =
    use repository = new TemporaryRepository()
    repository.Write("AGENTS.md", "agents rules")
    repository.Write("repo-governance/nested/RULES.MD", "nested rules")
    repository.Write("repo-governance/notes.txt", "not Markdown")
    repository.Write("README.md", "outside governance")

    let files = Governance.scanRepository repository.Root

    Assert.Equal<string list>(
        [ "AGENTS.md"; "repo-governance/nested/RULES.MD" ],
        files |> List.map _.Path
    )

[<Fact>]
let ``findViolations allows 500 words and rejects 501`` () =
    use repository = new TemporaryRepository()
    repository.Write("AGENTS.md", words Governance.wordLimit)
    repository.Write("repo-governance/too-long.md", words (Governance.wordLimit + 1))

    let violations =
        Governance.scanRepository repository.Root |> Governance.findViolations

    let violation = Assert.Single violations
    Assert.Equal("repo-governance/too-long.md", violation.Path)
    Assert.Equal(501, violation.WordCount)

[<Fact>]
let ``scanRepository handles missing optional paths`` () =
    use repository = new TemporaryRepository()

    Assert.Empty(Governance.scanRepository repository.Root)

[<Fact>]
let ``CLI returns failure when a governed file exceeds the limit`` () =
    use repository = new TemporaryRepository()
    repository.Write("AGENTS.md", words (Governance.wordLimit + 1))

    Assert.Equal(1, Program.main [| repository.Root |])

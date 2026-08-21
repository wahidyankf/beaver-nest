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

let private emptyDirectoryMap title =
    $"# {title}\n\n## Directory Map\n\nThis directory currently has no entries other than this README."

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
let ``inspectRepository accepts complete direct-sibling maps`` () =
    use repository = new TemporaryRepository()

    repository.Write(
        "repo-governance/README.md",
        "# Governance\n\n## Directory Map\n\n- [Nested](nested/README.md)\n- [Rules](rules.md)"
    )

    repository.Write(
        "repo-governance/nested/README.md",
        emptyDirectoryMap "Nested"
    )

    repository.Write("repo-governance/rules.md", "# Rules")

    let inspection = Governance.inspectRepository repository.Root

    Assert.Equal(2, inspection.GovernanceDirectoryCount)
    Assert.Empty(inspection.Violations)

[<Fact>]
let ``inspectRepository requires README in every governance directory`` () =
    use repository = new TemporaryRepository()

    repository.Write(
        "repo-governance/README.md",
        "# Governance\n\n## Directory Map\n\n- [Nested](nested)"
    )

    repository.Write("repo-governance/nested/rules.md", "# Rules")

    let violation =
        Governance.inspectRepository repository.Root
        |> fun inspection -> Assert.Single inspection.Violations

    match violation with
    | MissingReadme path -> Assert.Equal("repo-governance/nested", path)
    | _ -> failwithf "Expected MissingReadme, got %A" violation

[<Fact>]
let ``inspectRepository requires a Directory Map section`` () =
    use repository = new TemporaryRepository()
    repository.Write("repo-governance/README.md", "# Governance")

    let violation =
        Governance.inspectRepository repository.Root
        |> fun inspection -> Assert.Single inspection.Violations

    match violation with
    | MissingDirectoryMap path ->
        Assert.Equal("repo-governance/README.md", path)
    | _ -> failwithf "Expected MissingDirectoryMap, got %A" violation

[<Fact>]
let ``inspectRepository rejects an omitted sibling`` () =
    use repository = new TemporaryRepository()
    repository.Write("repo-governance/README.md", emptyDirectoryMap "Governance")
    repository.Write("repo-governance/rules.md", "# Rules")

    let violation =
        Governance.inspectRepository repository.Root
        |> fun inspection -> Assert.Single inspection.Violations

    match violation with
    | MissingMapEntry(readmePath, siblingPath) ->
        Assert.Equal("repo-governance/README.md", readmePath)
        Assert.Equal("repo-governance/rules.md", siblingPath)
    | _ -> failwithf "Expected MissingMapEntry, got %A" violation

[<Fact>]
let ``inspectRepository reports an overlong README and its omitted sibling`` () =
    use repository = new TemporaryRepository()
    let readme =
        emptyDirectoryMap "Governance"
        + "\n\n"
        + words (Governance.wordLimit + 1)

    repository.Write("repo-governance/README.md", readme)

    repository.Write("repo-governance/rules.md", "# Rules")

    match Governance.inspectRepository(repository.Root).Violations with
    | [ WordLimitExceeded file;
        MissingMapEntry(readmePath, siblingPath) ] ->
        Assert.Equal("repo-governance/README.md", file.Path)
        Assert.True(file.WordCount > Governance.wordLimit)
        Assert.Equal("repo-governance/README.md", readmePath)
        Assert.Equal("repo-governance/rules.md", siblingPath)
    | violations -> failwithf "Expected both violations, got %A" violations

[<Fact>]
let ``inspectRepository rejects a nonexistent map entry`` () =
    use repository = new TemporaryRepository()

    repository.Write(
        "repo-governance/README.md",
        "# Governance\n\n## Directory Map\n\n- [Old rules](old-rules.md)"
    )

    let violation =
        Governance.inspectRepository repository.Root
        |> fun inspection -> Assert.Single inspection.Violations

    match violation with
    | InvalidMapEntry(readmePath, target) ->
        Assert.Equal("repo-governance/README.md", readmePath)
        Assert.Equal("old-rules.md", target)
    | _ -> failwithf "Expected InvalidMapEntry, got %A" violation

[<Fact>]
let ``inspectRepository rejects an existing non-sibling map entry`` () =
    use repository = new TemporaryRepository()

    repository.Write(
        "repo-governance/README.md",
        "# Governance\n\n## Directory Map\n\n- [Nested](nested/README.md)"
    )

    repository.Write(
        "repo-governance/nested/README.md",
        "# Nested\n\n## Directory Map\n\n- [Parent](../README.md)"
    )

    let violation =
        Governance.inspectRepository repository.Root
        |> fun inspection -> Assert.Single inspection.Violations

    match violation with
    | InvalidMapEntry(readmePath, target) ->
        Assert.Equal("repo-governance/nested/README.md", readmePath)
        Assert.Equal("../README.md", target)
    | _ -> failwithf "Expected InvalidMapEntry, got %A" violation

[<Fact>]
let ``CLI returns failure when a governed file exceeds the limit`` () =
    use repository = new TemporaryRepository()
    repository.Write("AGENTS.md", words (Governance.wordLimit + 1))

    Assert.Equal(1, Program.main [| repository.Root |])

[<Fact>]
let ``CLI returns failure when governance navigation is invalid`` () =
    use repository = new TemporaryRepository()
    repository.Write("repo-governance/README.md", "# Governance")

    Assert.Equal(1, Program.main [| repository.Root |])

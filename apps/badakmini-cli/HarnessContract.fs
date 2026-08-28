namespace Badakmini.Cli

open System
open System.Collections.Generic
open System.IO
open System.Security.Cryptography
open System.Text
open System.Text.Json
open System.Text.RegularExpressions

type HarnessContractFinding =
    { Kind: string
      Path: string
      RelatedPath: string option
      Harness: string option
      Name: string option
      Field: string option
      ExpectedDigest: string option
      ActualDigest: string option
      Message: string }

type HarnessContractInspection =
    { ContractDigest: string
      HarnessCount: int
      SkillCount: int
      AgentCount: int
      CapabilityCount: int
      Violations: HarnessContractFinding list }

type private FrontMatter =
    { Scalars: Map<string, string>
      Lists: Map<string, string list>
      Nested: Map<string, Map<string, string>>
      Body: string }

type private CanonicalSkill =
    { Name: string
      Description: string
      Digest: string }

type private CanonicalAgent =
    { Name: string
      Description: string
      Requires: Set<string>
      Denies: Set<string>
      Constraints: Set<string>
      Digest: string }

module HarnessContract =
    let private excludedDirectories =
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

    let private kebabCase = Regex("^[a-z0-9]+(?:-[a-z0-9]+)*$", RegexOptions.Compiled)

    let private knownAgentKeys =
        set [ "name"; "description"; "mode"; "requires"; "denies"; "constraints" ]

    let private knownCapabilities =
        set
            [ "repository-read"
              "repository-write"
              "web-search"
              "web-fetch"
              "shell"
              "nested-agent"
              "nx-mcp" ]

    let private knownConstraints = set [ "inline-result-only"; "single-mcp-operation" ]

    let private normalizeText (value: string) =
        let value =
            if value.Length > 0 && value[0] = '\uFEFF' then
                value.Substring 1
            else
                value

        value.Replace("\r\n", "\n").Replace('\r', '\n')

    let private normalizeAdapter value = normalizeText value |> _.Trim()

    let private sha256 (value: string) =
        value
        |> Encoding.UTF8.GetBytes
        |> SHA256.HashData
        |> Convert.ToHexString
        |> _.ToLowerInvariant()

    let private relativePath (root: string) (path: string) =
        Path.GetRelativePath(root, path).Replace(Path.DirectorySeparatorChar, '/')

    let private isReparsePoint (fileSystem: RepositoryFileSystem) (path: string) =
        fileSystem.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint)

    let private enumerateFiles (fileSystem: RepositoryFileSystem) (root: string) =
        seq {
            let pending = Stack<string>()
            pending.Push root

            while pending.Count > 0 do
                let directory = pending.Pop()

                for file in fileSystem.EnumerateFiles directory |> Seq.sort do
                    if not (isReparsePoint fileSystem file) then
                        yield file

                for child in fileSystem.EnumerateDirectories directory |> Seq.sortDescending do
                    if
                        not (excludedDirectories.Contains(Path.GetFileName child))
                        && not (isReparsePoint fileSystem child)
                    then
                        pending.Push child
        }

    let private enumerateDirectFiles (fileSystem: RepositoryFileSystem) (directory: string) (extension: string) =
        if
            fileSystem.DirectoryExists directory
            && not (isReparsePoint fileSystem directory)
        then
            fileSystem.EnumerateFiles directory
            |> Seq.filter (fun path ->
                not (isReparsePoint fileSystem path)
                && String.Equals(Path.GetExtension path, extension, StringComparison.OrdinalIgnoreCase))
            |> Seq.sort
            |> Seq.toList
        else
            []

    let private enumerateDirectDirectories (fileSystem: RepositoryFileSystem) (directory: string) =
        if
            fileSystem.DirectoryExists directory
            && not (isReparsePoint fileSystem directory)
        then
            fileSystem.EnumerateDirectories directory
            |> Seq.filter (isReparsePoint fileSystem >> not)
            |> Seq.sort
            |> Seq.toList
        else
            []

    let private unquote (value: string) =
        let value = value.Trim()

        if value.Length >= 2 && value[0] = '"' && value[value.Length - 1] = '"' then
            JsonSerializer.Deserialize<string>(value)
        elif value.Length >= 2 && value[0] = '\'' && value[value.Length - 1] = '\'' then
            value.Substring(1, value.Length - 2).Replace("''", "'")
        else
            value

    let private parseFrontMatter path content =
        let normalized = normalizeText content
        let lines = normalized.Split '\n'

        if lines.Length < 3 || lines[0].Trim() <> "---" then
            invalidOp $"{path}: missing front matter"

        let closing =
            lines
            |> Array.indexed
            |> Array.tryFind (fun (index, line) -> index > 0 && line.Trim() = "---")
            |> Option.map fst
            |> Option.defaultWith (fun () -> invalidOp $"{path}: unterminated front matter")

        let scalars = Dictionary<string, string>(StringComparer.Ordinal)
        let lists = Dictionary<string, ResizeArray<string>>(StringComparer.Ordinal)
        let nested = Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal)
        let mutable currentList: string option = None
        let mutable currentNested: string option = None

        for line in lines[1 .. closing - 1] do
            if String.IsNullOrWhiteSpace line then
                ()
            elif line.StartsWith("  - ", StringComparison.Ordinal) then
                match currentList with
                | Some key -> lists[key].Add(unquote (line.Substring 4))
                | None -> invalidOp $"{path}: list item has no parent"
            elif line.StartsWith("  ", StringComparison.Ordinal) then
                match currentNested with
                | Some key ->
                    let nestedLine = line.Trim()
                    let separator = nestedLine.IndexOf ':'

                    if separator <= 0 then
                        invalidOp $"{path}: malformed nested field"

                    let nestedKey = nestedLine.Substring(0, separator).Trim()

                    if nested[key].ContainsKey nestedKey then
                        invalidOp $"{path}: duplicate nested field '{nestedKey}'"

                    nested[key][nestedKey] <- unquote (nestedLine.Substring(separator + 1))
                | None -> invalidOp $"{path}: unexpected indentation"
            else
                let separator = line.IndexOf ':'

                if separator <= 0 then
                    invalidOp $"{path}: malformed front-matter field"

                let key = line.Substring(0, separator).Trim()
                let value = line.Substring(separator + 1).Trim()

                if scalars.ContainsKey key || lists.ContainsKey key || nested.ContainsKey key then
                    invalidOp $"{path}: duplicate front-matter field '{key}'"

                currentList <- None
                currentNested <- None

                if String.IsNullOrEmpty value then
                    if key = "requires" || key = "denies" || key = "constraints" then
                        lists[key] <- ResizeArray<string>()
                        currentList <- Some key
                    else
                        nested[key] <- Dictionary<string, string>(StringComparer.Ordinal)
                        currentNested <- Some key
                else
                    scalars[key] <- unquote value

        { Scalars = scalars |> Seq.map (fun pair -> pair.Key, pair.Value) |> Map.ofSeq
          Lists = lists |> Seq.map (fun pair -> pair.Key, pair.Value |> Seq.toList) |> Map.ofSeq
          Nested =
            nested
            |> Seq.map (fun pair ->
                pair.Key,
                (pair.Value
                 |> Seq.map (fun nestedPair -> nestedPair.Key, nestedPair.Value)
                 |> Map.ofSeq))
            |> Map.ofSeq
          Body = lines[closing + 1 ..] |> String.concat "\n" |> _.Trim() }

    let private finding (kind: string) (path: string) (message: string) : HarnessContractFinding =
        { Kind = kind
          Path = path
          RelatedPath = None
          Harness = None
          Name = None
          Field = None
          ExpectedDigest = None
          ActualDigest = None
          Message = message }

    let private withHarness
        (harness: string)
        (name: string option)
        (field: string option)
        (finding: HarnessContractFinding)
        =
        { finding with
            Harness = Some harness
            Name = name
            Field = field }

    let private withDigests (expected: string) (actual: string) (finding: HarnessContractFinding) =
        { finding with
            ExpectedDigest = Some expected
            ActualDigest = Some actual }

    let private readRequired
        (fileSystem: RepositoryFileSystem)
        (root: string)
        (relative: string)
        (kind: string)
        (findings: ResizeArray<HarnessContractFinding>)
        =
        let path = Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar))

        if not (fileSystem.FileExists path) || isReparsePoint fileSystem path then
            findings.Add(finding kind relative $"Required regular file is missing: {relative}")
            None
        else
            Some(fileSystem.ReadAllText path)

    let private validateInstructions
        (fileSystem: RepositoryFileSystem)
        (root: string)
        (findings: ResizeArray<HarnessContractFinding>)
        (records: ResizeArray<string>)
        =
        match readRequired fileSystem root "AGENTS.md" "missing-canonical-source" findings with
        | Some content -> records.Add("rules\000" + normalizeText content)
        | None -> ()

        match readRequired fileSystem root "CLAUDE.md" "invalid-instruction-adapter" findings with
        | Some content when normalizeAdapter content = "@AGENTS.md" -> ()
        | Some _ ->
            finding "invalid-instruction-adapter" "CLAUDE.md" "Claude instructions must import only @AGENTS.md."
            |> withHarness "claude" None (Some "content")
            |> findings.Add
        | None -> ()

        for path in enumerateFiles fileSystem root do
            let relative = relativePath root path
            let fileName = Path.GetFileName path

            let unexpected =
                (fileName = "AGENTS.md" && relative <> "AGENTS.md")
                || fileName = "AGENTS.override.md"
                || (fileName = "CLAUDE.md" && relative <> "CLAUDE.md")
                || (relative.StartsWith(".claude/rules/", StringComparison.Ordinal)
                    && String.Equals(Path.GetExtension path, ".md", StringComparison.OrdinalIgnoreCase))

            if unexpected then
                findings.Add(
                    finding
                        "unexpected-instruction-source"
                        relative
                        "Additional repository instruction sources are outside the parity contract."
                )

    let private skillRecord
        (fileSystem: RepositoryFileSystem)
        (_root: string)
        (directory: string)
        (name: string)
        (description: string)
        =
        let entries =
            enumerateFiles fileSystem directory
            |> Seq.map (fun path -> relativePath directory path, normalizeText (fileSystem.ReadAllText path))
            |> Seq.sortBy fst
            |> Seq.map (fun (path, content) -> $"{path.Length}:{path}{content.Length}:{content}")
            |> String.concat "\n"

        $"skill\n{name}\n{description}\n{entries}" |> sha256

    let private validateSkills
        (fileSystem: RepositoryFileSystem)
        (root: string)
        (findings: ResizeArray<HarnessContractFinding>)
        (records: ResizeArray<string>)
        =
        let canonicalRoot = Path.Combine(root, ".agents", "skills")
        let skills = ResizeArray<CanonicalSkill>()

        for directory in enumerateDirectDirectories fileSystem canonicalRoot do
            let directoryName = Path.GetFileName directory
            let skillPath = Path.Combine(directory, "SKILL.md")
            let relative = relativePath root skillPath

            try
                if not (fileSystem.FileExists skillPath) || isReparsePoint fileSystem skillPath then
                    invalidOp "missing regular SKILL.md"

                let parsed = parseFrontMatter relative (fileSystem.ReadAllText skillPath)
                let name = Map.tryFind "name" parsed.Scalars |> Option.defaultValue ""
                let description = Map.tryFind "description" parsed.Scalars |> Option.defaultValue ""

                if
                    not (kebabCase.IsMatch name)
                    || name <> directoryName
                    || String.IsNullOrWhiteSpace description
                    || String.IsNullOrWhiteSpace parsed.Body
                then
                    invalidOp "name, description, body, directory, or uniqueness is invalid"

                let digest = skillRecord fileSystem root directory name description

                skills.Add(
                    { Name = name
                      Description = description
                      Digest = digest }
                )

                records.Add($"skill/{name}\000{digest}")
            with ex ->
                findings.Add(finding "invalid-skill" relative $"Canonical skill is invalid: {ex.Message}")

        let wrappersRoot = Path.Combine(root, ".claude", "commands")
        let wrappers = enumerateDirectFiles fileSystem wrappersRoot ".md"
        let expectedNames = skills |> Seq.map _.Name |> Set.ofSeq

        for skill in skills do
            let relative = $".claude/commands/{skill.Name}.md"
            let path = Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar))

            if not (fileSystem.FileExists path) || isReparsePoint fileSystem path then
                finding "missing-skill-adapter" relative "Canonical skill has no regular Claude adapter."
                |> withHarness "claude" (Some skill.Name) None
                |> findings.Add
            else
                try
                    let parsed = parseFrontMatter relative (fileSystem.ReadAllText path)

                    let expectedBody =
                        $"Read .agents/skills/{skill.Name}/SKILL.md completely, resolve every relative resource from that skill directory, and follow it as authoritative before acting."

                    let actualDescription =
                        Map.tryFind "description" parsed.Scalars |> Option.defaultValue ""

                    if
                        parsed.Scalars.Count <> 1
                        || not parsed.Lists.IsEmpty
                        || not parsed.Nested.IsEmpty
                        || actualDescription <> skill.Description
                        || normalizeAdapter parsed.Body <> expectedBody
                    then
                        let expected = sha256 (skill.Description + "\n" + expectedBody)
                        let actual = sha256 (actualDescription + "\n" + normalizeAdapter parsed.Body)

                        finding "skill-content-divergence" relative "Claude skill adapter content diverges."
                        |> withHarness "claude" (Some skill.Name) (Some "content")
                        |> withDigests expected actual
                        |> findings.Add
                with ex ->
                    findings.Add(
                        finding "skill-content-divergence" relative $"Claude skill adapter is invalid: {ex.Message}"
                    )

        for wrapper in wrappers do
            let name = Path.GetFileNameWithoutExtension wrapper

            if not (Set.contains name expectedNames) then
                finding "unexpected-skill-adapter" (relativePath root wrapper) "Claude adapter has no canonical skill."
                |> withHarness "claude" (Some name) None
                |> findings.Add

        skills |> Seq.toList

    let private listSet (key: string) (parsed: FrontMatter) =
        let values = Map.tryFind key parsed.Lists |> Option.defaultValue []

        if values.Length <> (values |> Set.ofList |> Set.count) then
            invalidOp $"duplicate {key} values"

        values |> Set.ofList

    let private validateCanonicalAgent (path: string) (stem: string) (parsed: FrontMatter) =
        let allKeys =
            Set.union (parsed.Scalars |> Map.keys |> Set.ofSeq) (parsed.Lists |> Map.keys |> Set.ofSeq)

        if not parsed.Nested.IsEmpty || not (Set.isSubset allKeys knownAgentKeys) then
            invalidOp "unknown agent front-matter fields"

        let name = Map.tryFind "name" parsed.Scalars |> Option.defaultValue ""
        let description = Map.tryFind "description" parsed.Scalars |> Option.defaultValue ""
        let mode = Map.tryFind "mode" parsed.Scalars |> Option.defaultValue ""
        let requires = listSet "requires" parsed
        let denies = listSet "denies" parsed
        let constraints = listSet "constraints" parsed

        if
            not (kebabCase.IsMatch name)
            || name <> stem
            || String.IsNullOrWhiteSpace description
            || mode <> "subagent"
            || String.IsNullOrWhiteSpace parsed.Body
            || not (Set.isSubset requires knownCapabilities)
            || not (Set.isSubset denies knownCapabilities)
            || not (Set.isSubset constraints knownConstraints)
            || not (Set.intersect requires denies |> Set.isEmpty)
        then
            invalidOp $"{path}: invalid agent identity, mode, capabilities, constraints, or body"

        let ordered values =
            values |> Set.toList |> List.sort |> String.concat ","

        let digest =
            $"agent\n{name}\n{description}\n{mode}\n{ordered requires}\n{ordered denies}\n{ordered constraints}\n{normalizeText parsed.Body}"
            |> sha256

        { Name = name
          Description = description
          Requires = requires
          Denies = denies
          Constraints = constraints
          Digest = digest }

    let private tomlScalar (key: string) (content: string) =
        let matched =
            Regex.Match(
                content,
                $"(?m)^\\s*{Regex.Escape key}\\s*=\\s*(?<value>\"(?:\\\\.|[^\"])*\")\\s*$",
                RegexOptions.CultureInvariant
            )

        if matched.Success then
            Some(JsonSerializer.Deserialize<string>(matched.Groups["value"].Value))
        else
            None

    let private tomlMultiline (key: string) (content: string) =
        let matched =
            Regex.Match(
                normalizeText content,
                $"(?s)(?:^|\\n)\\s*{Regex.Escape key}\\s*=\\s*\"\"\"(?<value>.*?)\"\"\"",
                RegexOptions.CultureInvariant
            )

        if matched.Success then
            Some matched.Groups["value"].Value
        else
            None

    let private validateCodexAdapter
        (fileSystem: RepositoryFileSystem)
        (root: string)
        (agent: CanonicalAgent)
        (findings: ResizeArray<HarnessContractFinding>)
        =
        let relative = $".codex/agents/{agent.Name}.toml"
        let path = Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar))

        if not (fileSystem.FileExists path) || isReparsePoint fileSystem path then
            finding "missing-agent-adapter" relative "Canonical agent has no regular Codex adapter."
            |> withHarness "codex" (Some agent.Name) None
            |> findings.Add
        else
            let content = fileSystem.ReadAllText path

            let expectedRoute =
                $"Before acting, read the complete canonical agent definition at the repository-root path .agents/agents/{agent.Name}.md and follow it as authoritative. If it cannot be read, stop and report the missing path."

            let name = tomlScalar "name" content |> Option.defaultValue ""
            let description = tomlScalar "description" content |> Option.defaultValue ""
            let sandbox = tomlScalar "sandbox_mode" content |> Option.defaultValue ""

            let route =
                tomlMultiline "developer_instructions" content
                |> Option.defaultValue ""
                |> normalizeAdapter

            if
                name <> agent.Name
                || description <> agent.Description
                || Regex.IsMatch(content, "(?m)^\\s*model\\s*=")
            then
                finding "agent-semantic-divergence" relative "Codex agent identity or portable model semantics diverge."
                |> withHarness "codex" (Some agent.Name) (Some "identity")
                |> findings.Add

            if sandbox <> "read-only" then
                finding "agent-semantic-divergence" relative "Codex agent must use the read-only sandbox."
                |> withHarness "codex" (Some agent.Name) (Some "sandbox_mode")
                |> findings.Add

            if route <> expectedRoute then
                finding "agent-prompt-divergence" relative "Codex agent prompt must be the exact canonical route."
                |> withHarness "codex" (Some agent.Name) (Some "developer_instructions")
                |> withDigests (sha256 expectedRoute) (sha256 route)
                |> findings.Add

    let private containsTool (tool: string) (tools: Set<string>) = Set.contains tool tools

    let private validateClaudeAdapter
        (fileSystem: RepositoryFileSystem)
        (root: string)
        (agent: CanonicalAgent)
        (findings: ResizeArray<HarnessContractFinding>)
        =
        let relative = $".claude/agents/{agent.Name}.md"
        let path = Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar))

        if not (fileSystem.FileExists path) || isReparsePoint fileSystem path then
            finding "missing-agent-adapter" relative "Canonical agent has no regular Claude adapter."
            |> withHarness "claude" (Some agent.Name) None
            |> findings.Add
        else
            try
                let parsed = parseFrontMatter relative (fileSystem.ReadAllText path)
                let name = Map.tryFind "name" parsed.Scalars |> Option.defaultValue ""
                let description = Map.tryFind "description" parsed.Scalars |> Option.defaultValue ""

                let tools =
                    Map.tryFind "tools" parsed.Scalars
                    |> Option.defaultValue ""
                    |> _.Split(',', StringSplitOptions.RemoveEmptyEntries ||| StringSplitOptions.TrimEntries)
                    |> Set.ofArray

                let expectedRoute =
                    $"Before acting, read the complete canonical agent definition at the repository-root path .agents/agents/{agent.Name}.md and follow it as authoritative. If it cannot be read, stop and report the missing path."

                if name <> agent.Name || description <> agent.Description then
                    finding "agent-semantic-divergence" relative "Claude agent identity or description diverges."
                    |> withHarness "claude" (Some agent.Name) (Some "identity")
                    |> findings.Add

                let requiredTools =
                    seq {
                        yield "Read"

                        if agent.Requires.Contains "repository-read" then
                            yield! [ "Glob"; "Grep" ]

                        if agent.Requires.Contains "web-search" then
                            yield "WebSearch"

                        if agent.Requires.Contains "web-fetch" then
                            yield "WebFetch"
                    }
                    |> Set.ofSeq

                let weakRequired = not (Set.isSubset requiredTools tools)

                let weakNx =
                    agent.Requires.Contains "nx-mcp"
                    && not (tools |> Seq.exists (_.StartsWith("mcp__nx-mcp__")))

                let weakWrite =
                    agent.Denies.Contains "repository-write"
                    && (containsTool "Write" tools || containsTool "Edit" tools)

                let weakShell =
                    agent.Denies.Contains "shell"
                    && (containsTool "Bash" tools || containsTool "PowerShell" tools)

                let weakNested =
                    agent.Denies.Contains "nested-agent"
                    && (containsTool "Agent" tools || containsTool "Task" tools)

                if weakRequired || weakNx || weakWrite || weakShell || weakNested then
                    finding "agent-semantic-divergence" relative "Claude tool allowlist weakens canonical capabilities."
                    |> withHarness "claude" (Some agent.Name) (Some "tools")
                    |> findings.Add

                if normalizeAdapter parsed.Body <> expectedRoute then
                    finding "agent-prompt-divergence" relative "Claude agent prompt must be the exact canonical route."
                    |> withHarness "claude" (Some agent.Name) (Some "content")
                    |> findings.Add
            with ex ->
                findings.Add(
                    finding "agent-semantic-divergence" relative $"Claude agent adapter is invalid: {ex.Message}"
                )

    let private validateOpenCodeAdapter
        (fileSystem: RepositoryFileSystem)
        (root: string)
        (agent: CanonicalAgent)
        (findings: ResizeArray<HarnessContractFinding>)
        =
        let relative = $".opencode/agents/{agent.Name}.md"
        let path = Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar))

        if not (fileSystem.FileExists path) || isReparsePoint fileSystem path then
            finding "missing-agent-adapter" relative "Canonical agent has no regular OpenCode adapter."
            |> withHarness "opencode" (Some agent.Name) None
            |> findings.Add
        else
            try
                let parsed = parseFrontMatter relative (fileSystem.ReadAllText path)
                let description = Map.tryFind "description" parsed.Scalars |> Option.defaultValue ""
                let mode = Map.tryFind "mode" parsed.Scalars |> Option.defaultValue ""

                let permissions =
                    Map.tryFind "permission" parsed.Nested |> Option.defaultValue Map.empty

                let permission key =
                    Map.tryFind key permissions |> Option.defaultValue ""

                let expectedRoute =
                    $"Before acting, read the complete canonical agent definition at the repository-root path .agents/agents/{agent.Name}.md and follow it as authoritative. If it cannot be read, stop and report the missing path."

                let weakRead =
                    permission "read" <> "allow"
                    || (agent.Requires.Contains "repository-read"
                        && [ "glob"; "grep" ] |> List.exists (fun key -> permission key <> "allow"))

                let weakWeb =
                    (agent.Requires.Contains "web-search" && permission "websearch" <> "allow")
                    || (agent.Requires.Contains "web-fetch" && permission "webfetch" <> "allow")

                let weakNx =
                    agent.Requires.Contains "nx-mcp"
                    && not (
                        permissions
                        |> Map.exists (fun key value ->
                            key.StartsWith("nx-mcp_", StringComparison.Ordinal) && value = "allow")
                    )

                let weakDenied =
                    (agent.Denies.Contains "repository-write" && permission "edit" <> "deny")
                    || (agent.Denies.Contains "shell" && permission "bash" <> "deny")
                    || (agent.Denies.Contains "nested-agent" && permission "task" <> "deny")

                if
                    description <> agent.Description
                    || mode <> "subagent"
                    || weakRead
                    || weakWeb
                    || weakNx
                    || weakDenied
                then
                    finding "agent-semantic-divergence" relative "OpenCode agent metadata or permissions diverge."
                    |> withHarness "opencode" (Some agent.Name) (Some "permission")
                    |> findings.Add

                if normalizeAdapter parsed.Body <> expectedRoute then
                    finding
                        "agent-prompt-divergence"
                        relative
                        "OpenCode agent prompt must be the exact canonical route."
                    |> withHarness "opencode" (Some agent.Name) (Some "content")
                    |> findings.Add
            with ex ->
                findings.Add(
                    finding "agent-semantic-divergence" relative $"OpenCode agent adapter is invalid: {ex.Message}"
                )

    let private validateAgents
        (fileSystem: RepositoryFileSystem)
        (root: string)
        (findings: ResizeArray<HarnessContractFinding>)
        (records: ResizeArray<string>)
        =
        let canonicalRoot = Path.Combine(root, ".agents", "agents")
        let agents = ResizeArray<CanonicalAgent>()

        for path in enumerateDirectFiles fileSystem canonicalRoot ".md" do
            let relative = relativePath root path
            let stem = Path.GetFileNameWithoutExtension path

            try
                let agent =
                    parseFrontMatter relative (fileSystem.ReadAllText path)
                    |> validateCanonicalAgent relative stem

                agents.Add agent
                records.Add($"agent/{agent.Name}\000{agent.Digest}")
            with ex ->
                findings.Add(finding "invalid-agent" relative $"Canonical agent is invalid: {ex.Message}")

        let expected = agents |> Seq.map _.Name |> Set.ofSeq

        for agent in agents do
            validateCodexAdapter fileSystem root agent findings
            validateClaudeAdapter fileSystem root agent findings
            validateOpenCodeAdapter fileSystem root agent findings

        for harness, directory, extension in
            [ "codex", ".codex/agents", ".toml"
              "claude", ".claude/agents", ".md"
              "opencode", ".opencode/agents", ".md" ] do
            let fullDirectory =
                Path.Combine(root, directory.Replace('/', Path.DirectorySeparatorChar))

            for adapter in enumerateDirectFiles fileSystem fullDirectory extension do
                let name = Path.GetFileNameWithoutExtension adapter

                if not (Set.contains name expected) then
                    finding
                        "unexpected-agent-adapter"
                        (relativePath root adapter)
                        "Harness adapter has no canonical custom agent."
                    |> withHarness harness (Some name) None
                    |> findings.Add

        agents |> Seq.toList

    let private stripJsonComments (content: string) =
        let source = normalizeText content
        let result = StringBuilder(source.Length)
        let mutable index = 0
        let mutable inString = false
        let mutable escaped = false

        while index < source.Length do
            let current = source[index]

            if inString then
                result.Append current |> ignore

                if escaped then
                    escaped <- false
                elif current = '\\' then
                    escaped <- true
                elif current = '"' then
                    inString <- false

                index <- index + 1
            elif current = '"' then
                inString <- true
                result.Append current |> ignore
                index <- index + 1
            elif current = '/' && index + 1 < source.Length && source[index + 1] = '/' then
                index <- index + 2

                while index < source.Length && source[index] <> '\n' do
                    index <- index + 1
            elif current = '/' && index + 1 < source.Length && source[index + 1] = '*' then
                index <- index + 2

                while index + 1 < source.Length
                      && not (source[index] = '*' && source[index + 1] = '/') do
                    index <- index + 1

                if index + 1 >= source.Length then
                    invalidOp "unterminated JSON block comment"

                index <- index + 2
            else
                result.Append current |> ignore
                index <- index + 1

        result.ToString()

    let private jsonDocument path content =
        try
            JsonDocument.Parse(stripJsonComments content, JsonDocumentOptions(AllowTrailingCommas = true))
        with ex ->
            raise (InvalidDataException($"{path}: unreadable harness config", ex))

    let private stringArray (element: JsonElement) : string list =
        if element.ValueKind <> JsonValueKind.Array then
            []
        else
            element.EnumerateArray() |> Seq.map _.GetString() |> Seq.toList

    let private validateCapabilities
        (fileSystem: RepositoryFileSystem)
        (root: string)
        (findings: ResizeArray<HarnessContractFinding>)
        (records: ResizeArray<string>)
        =
        let expected = [ "npx"; "nx"; "mcp" ]

        let codex =
            readRequired fileSystem root ".codex/config.toml" "missing-capability" findings
            |> Option.map (fun content ->
                let section =
                    Regex.Match(
                        normalizeText content,
                        "(?ms)^\\s*\\[mcp_servers\\.nx-mcp\\]\\s*(?<body>.*?)(?=^\\s*\\[|\\z)"
                    )

                if not section.Success then
                    []
                else
                    let body = section.Groups["body"].Value
                    let command = tomlScalar "command" body |> Option.toList

                    let arguments =
                        let matched = Regex.Match(body, "(?m)^\\s*args\\s*=\\s*\\[(?<value>[^]]*)\\]")

                        if not matched.Success then
                            []
                        else
                            Regex.Matches(matched.Groups["value"].Value, "\"(?<value>(?:\\\\.|[^\"])*)\"")
                            |> Seq.cast<Match>
                            |> Seq.map (fun item ->
                                JsonSerializer.Deserialize<string>("\"" + item.Groups["value"].Value + "\""))
                            |> Seq.toList

                    command @ arguments)
            |> Option.defaultValue []

        let claude =
            readRequired fileSystem root ".mcp.json" "missing-capability" findings
            |> Option.map (fun content ->
                use document = jsonDocument ".mcp.json" content
                let mutable servers = Unchecked.defaultof<JsonElement>
                let mutable server = Unchecked.defaultof<JsonElement>
                let mutable command = Unchecked.defaultof<JsonElement>
                let mutable arguments = Unchecked.defaultof<JsonElement>

                if
                    document.RootElement.TryGetProperty("mcpServers", &servers)
                    && servers.TryGetProperty("nx-mcp", &server)
                    && server.TryGetProperty("command", &command)
                    && server.TryGetProperty("args", &arguments)
                then
                    command.GetString() :: stringArray arguments
                else
                    [])
            |> Option.defaultValue []

        let opencode =
            readRequired fileSystem root "opencode.json" "missing-capability" findings
            |> Option.map (fun content ->
                use document = jsonDocument "opencode.json" content
                let mutable instructions = Unchecked.defaultof<JsonElement>

                if
                    document.RootElement.TryGetProperty("instructions", &instructions)
                    && instructions.ValueKind = JsonValueKind.Array
                    && instructions.GetArrayLength() > 0
                then
                    findings.Add(
                        finding
                            "unexpected-instruction-source"
                            "opencode.json"
                            "OpenCode instructions must be absent or empty."
                    )

                let mutable servers = Unchecked.defaultof<JsonElement>
                let mutable server = Unchecked.defaultof<JsonElement>
                let mutable kind = Unchecked.defaultof<JsonElement>
                let mutable command = Unchecked.defaultof<JsonElement>

                if
                    document.RootElement.TryGetProperty("mcp", &servers)
                    && servers.TryGetProperty("nx-mcp", &server)
                    && server.TryGetProperty("type", &kind)
                    && kind.GetString() = "local"
                    && server.TryGetProperty("command", &command)
                then
                    stringArray command
                else
                    [])
            |> Option.defaultValue []

        for harness, path, actual in
            [ "codex", ".codex/config.toml", codex
              "claude", ".mcp.json", claude
              "opencode", "opencode.json", opencode ] do
            if actual <> expected then
                finding "divergent-capability" path "Nx MCP executable vector must be npx nx mcp."
                |> withHarness harness None (Some "nx-mcp")
                |> withDigests (sha256 (String.concat "\000" expected)) (sha256 (String.concat "\000" actual))
                |> findings.Add

        records.Add("capability/nx-mcp\000" + sha256 (String.concat "\000" expected))

    let inspectWith (fileSystem: RepositoryFileSystem) (root: string) =
        let fullRoot = Path.GetFullPath root

        if not (fileSystem.DirectoryExists fullRoot) then
            invalidArg (nameof root) $"Directory does not exist: {root}"

        let findings = ResizeArray<HarnessContractFinding>()
        let records = ResizeArray<string>()
        validateInstructions fileSystem fullRoot findings records
        let skills = validateSkills fileSystem fullRoot findings records
        let agents = validateAgents fileSystem fullRoot findings records
        validateCapabilities fileSystem fullRoot findings records

        let sortedFindings =
            findings
            |> Seq.sortBy (fun item ->
                item.Path,
                item.Kind,
                Option.defaultValue "" item.Harness,
                Option.defaultValue "" item.Name,
                Option.defaultValue "" item.Field)
            |> Seq.toList

        { ContractDigest = records |> Seq.sort |> String.concat "\n" |> sha256
          HarnessCount = 3
          SkillCount = skills.Length
          AgentCount = agents.Length
          CapabilityCount = 1
          Violations = sortedFindings }

    let formatFinding finding = $"{finding.Path}: {finding.Message}"

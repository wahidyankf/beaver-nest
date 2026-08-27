module Badakmini.Cli.BehaviourSteps

open TickSpec
open Badakmini.Cli.BehaviourSupport
open Badakmini.Cli.BehaviourTests

[<BeforeScenario>]
let createScenarioContext () =
    BehaviourSupport.createScenarioContext ()

[<Given>]
let ``an empty repository`` (context: ScenarioContext) =
    BehaviourSupport.``an empty repository`` context

[<Given>]
let ``the repository contains:`` (table: Table) (context: ScenarioContext) =
    BehaviourSupport.``the repository contains:`` table context

[<Given>]
let ``file "(.*)" contains (\d+) words`` (path: string) (count: int) (context: ScenarioContext) =
    BehaviourSupport.``file "(.*)" contains (\d+) words`` path count context

[<Given>]
let ``file "(.*)" contains this Markdown:`` (path: string) (content: string) (context: ScenarioContext) =
    BehaviourSupport.``file "(.*)" contains this Markdown:`` path content context

[<Given>]
let ``file "(.*)" has title "(.*)" and an empty directory map``
    (path: string)
    (title: string)
    (context: ScenarioContext)
    =
    BehaviourSupport.``file "(.*)" has title "(.*)" and an empty directory map`` path title context

[<Given>]
let ``file "(.*)" has an empty "(.*)" directory map followed by (\d+) words``
    (path: string)
    (title: string)
    (count: int)
    (context: ScenarioContext)
    =
    BehaviourSupport.``file "(.*)" has an empty "(.*)" directory map followed by (\d+) words`` path title count context

[<Given>]
let ``an unsafe "(.*)" Mermaid diagram exists at "(.*)" using (.*) fences``
    (header: string)
    (path: string)
    (fenceName: string)
    (context: ScenarioContext)
    =
    BehaviourSupport.``an unsafe "(.*)" Mermaid diagram exists at "(.*)" using (.*) fences``
        header
        path
        fenceName
        context

[<Given>]
let ``the repository contains Mermaid sample "(.*)" at "(.*)"``
    (sample: string)
    (path: string)
    (context: ScenarioContext)
    =
    BehaviourSupport.``the repository contains Mermaid sample "(.*)" at "(.*)"`` sample path context

[<Given>]
let ``each excluded directory contains an unsafe Mermaid diagram:``
    (directories: string array)
    (context: ScenarioContext)
    =
    BehaviourSupport.``each excluded directory contains an unsafe Mermaid diagram:`` directories context

[<Given>]
let ``the governed files are exclusively locked`` (context: ScenarioContext) =
    BehaviourSupport.``the governed files are exclusively locked`` context

[<Given>]
let ``Markdown text containing a heading marker, Hello, can't-stop, naïve, and 42`` (context: ScenarioContext) =
    BehaviourSupport.``Markdown text containing a heading marker, Hello, can't-stop, naïve, and 42`` context

[<When>]
let ``I count the words in "(.*)"`` (path: string) (context: ScenarioContext) =
    BehaviourSupport.``I count the words in "(.*)"`` path context

[<When>]
let ``I scan governed Markdown`` (context: ScenarioContext) =
    BehaviourSupport.``I scan governed Markdown`` context

[<When>]
let ``I find word-limit violations`` (context: ScenarioContext) =
    BehaviourSupport.``I find word-limit violations`` context

[<When>]
let ``I inspect the word budget`` (context: ScenarioContext) =
    BehaviourSupport.``I inspect the word budget`` context

[<When>]
let ``I inspect directory maps`` (context: ScenarioContext) =
    BehaviourSupport.``I inspect directory maps`` context

[<When>]
let ``I inspect directory maps under the invalid "(.*)" location`` (location: string) (context: ScenarioContext) =
    BehaviourSupport.``I inspect directory maps under the invalid "(.*)" location`` location context

[<When>]
let ``I inspect Mermaid accessibility`` (context: ScenarioContext) =
    BehaviourSupport.``I inspect Mermaid accessibility`` context

[<When>]
let ``I run the "(.*)" validator`` (validator: string) (context: ScenarioContext) =
    BehaviourSupport.``I run the "(.*)" validator`` validator context

[<When>]
let ``I run the directory-map validator for "(.*)"`` (directory: string) (context: ScenarioContext) =
    BehaviourSupport.``I run the directory-map validator for "(.*)"`` directory context

[<When>]
let ``I invoke the CLI with "(.*)"`` (argumentText: string) (context: ScenarioContext) =
    BehaviourSupport.``I invoke the CLI with "(.*)"`` argumentText context

[<When>]
let ``I invoke the CLI from the repository directory with "(.*)"`` (argumentText: string) (context: ScenarioContext) =
    BehaviourSupport.``I invoke the CLI from the repository directory with "(.*)"`` argumentText context

[<Then>]
let ``the word count is (\d+)`` (expected: int) (context: ScenarioContext) =
    BehaviourSupport.``the word count is (\d+)`` expected context

[<Then>]
let ``the scanned Markdown paths are:`` (expectedPaths: string array) (context: ScenarioContext) =
    BehaviourSupport.``the scanned Markdown paths are:`` expectedPaths context

[<Then>]
let ``no Markdown files are scanned`` (context: ScenarioContext) =
    BehaviourSupport.``no Markdown files are scanned`` context

[<Then>]
let ``there are no violations`` (context: ScenarioContext) =
    BehaviourSupport.``there are no violations`` context

[<Then>]
let ``there are (\d+) violations`` (expected: int) (context: ScenarioContext) =
    BehaviourSupport.``there are (\d+) violations`` expected context

[<Then>]
let ``all violations are "(.*)"`` (expectedKind: string) (context: ScenarioContext) =
    BehaviourSupport.``all violations are "(.*)"`` expectedKind context

[<Then>]
let ``the only violation is a (\d+)-word limit for "(.*)"``
    (expectedCount: int)
    (expectedPath: string)
    (context: ScenarioContext)
    =
    BehaviourSupport.``the only violation is a (\d+)-word limit for "(.*)"`` expectedCount expectedPath context

[<Then>]
let ``the only violation is a missing directory map at "(.*)"`` (expectedPath: string) (context: ScenarioContext) =
    BehaviourSupport.``the only violation is a missing directory map at "(.*)"`` expectedPath context

[<Then>]
let ``the only violation is a missing README at "(.*)"`` (expectedPath: string) (context: ScenarioContext) =
    BehaviourSupport.``the only violation is a missing README at "(.*)"`` expectedPath context

[<Then>]
let ``the only violation is a missing map entry from "(.*)" to "(.*)"``
    (expectedReadme: string)
    (expectedSibling: string)
    (context: ScenarioContext)
    =
    BehaviourSupport.``the only violation is a missing map entry from "(.*)" to "(.*)"``
        expectedReadme
        expectedSibling
        context

[<Then>]
let ``the only violation is an invalid map entry from "(.*)" to "(.*)"``
    (expectedReadme: string)
    (expectedTarget: string)
    (context: ScenarioContext)
    =
    BehaviourSupport.``the only violation is an invalid map entry from "(.*)" to "(.*)"``
        expectedReadme
        expectedTarget
        context

[<Then>]
let ``the violations include an overlong "(.*)" and its missing map entry for "(.*)"``
    (expectedReadme: string)
    (expectedSibling: string)
    (context: ScenarioContext)
    =
    BehaviourSupport.``the violations include an overlong "(.*)" and its missing map entry for "(.*)"``
        expectedReadme
        expectedSibling
        context

[<Then>]
let ``the only violation is a Mermaid accessibility issue at "(.*)"``
    (expectedPath: string)
    (context: ScenarioContext)
    =
    BehaviourSupport.``the only violation is a Mermaid accessibility issue at "(.*)"`` expectedPath context

[<Then>]
let ``the formatted violation starts with "(.*)"`` (expectedPrefix: string) (context: ScenarioContext) =
    BehaviourSupport.``the formatted violation starts with "(.*)"`` expectedPrefix context

[<Then>]
let ``(\d+) directories were inspected`` (expected: int) (context: ScenarioContext) =
    BehaviourSupport.``(\d+) directories were inspected`` expected context

[<Then>]
let ``(\d+) Mermaid diagrams were inspected`` (expected: int) (context: ScenarioContext) =
    BehaviourSupport.``(\d+) Mermaid diagrams were inspected`` expected context

[<Then>]
let ``an argument error is raised`` (context: ScenarioContext) =
    BehaviourSupport.``an argument error is raised`` context

[<Then>]
let ``the exit code is (\d+)`` (expected: int) (context: ScenarioContext) =
    BehaviourSupport.``the exit code is (\d+)`` expected context

[<Then>]
let ``stdout lines start with "(.*)"`` (prefix: string) (context: ScenarioContext) =
    BehaviourSupport.``stdout lines start with "(.*)"`` prefix context

[<Then>]
let ``stderr lines start with "(.*)"`` (prefix: string) (context: ScenarioContext) =
    BehaviourSupport.``stderr lines start with "(.*)"`` prefix context

[<Then>]
let ``stdout is empty`` (context: ScenarioContext) =
    BehaviourSupport.``stdout is empty`` context

[<Then>]
let ``stdout JSON property "(.*)" is (\d+)`` (property: string) (expected: int) (context: ScenarioContext) =
    BehaviourSupport.``stdout JSON property "(.*)" is (\d+)`` property expected context

[<Then>]
let ``the first stdout JSON violation kind is "(.*)"`` (expected: string) (context: ScenarioContext) =
    BehaviourSupport.``the first stdout JSON violation kind is "(.*)"`` expected context

[<Then>]
let ``the first stdout JSON legibility fields are "(.*)", (\d+), and (\d+)``
    (expectedRole: string)
    (expectedLength: int)
    (expectedLimit: int)
    (context: ScenarioContext)
    =
    BehaviourSupport.``the first stdout JSON legibility fields are "(.*)", (\d+), and (\d+)``
        expectedRole
        expectedLength
        expectedLimit
        context

namespace Badakmini.Cli.BehaviourTests

open System
open System.IO
open global.Xunit

type UnitPolicyTests() =
    [<Fact>]
    member _.``unit runtime uses test doubles instead of system resources``() =
        let forbidden =
            [ "RepositoryFileSystem.system"
              "CliRuntime.system"
              "File."
              "Directory."
              "Process"
              "System.Net"
              "HttpClient"
              "WebRequest"
              "TcpClient"
              "UdpClient"
              "Socket("
              "localhost"
              "127.0.0.1"
              "http://"
              "https://"
              "curl "
              "wget " ]

        let sourcePaths =
            [ "UnitDriver.fs"
              "../contract/CliContractTests.fs"
              "../contract/BehaviourTests.fs" ]
            |> List.map (fun path -> Path.GetFullPath(Path.Combine(__SOURCE_DIRECTORY__, path)))

        Assert.All(
            sourcePaths,
            fun sourcePath ->
                let source = File.ReadAllText sourcePath

                Assert.All(forbidden, fun token -> Assert.DoesNotContain(token, source))
        )

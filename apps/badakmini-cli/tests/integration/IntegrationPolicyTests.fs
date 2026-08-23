namespace Badakmini.Cli.BehaviourTests

open System
open System.IO
open global.Xunit

type IntegrationPolicyTests() =
    [<Fact>]
    member _.``integration runtime has no network dependency``() =
        let forbidden =
            [ "System.Net"
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
            [ "IntegrationDriver.fs"
              "IntegrationApplicationTests.fs"
              "../contract/CliContractTests.fs"
              "../../Runtime.fs"
              "../../Governance.fs"
              "../../Cli.fs"
              "../../Program.fs" ]
            |> List.map (fun path -> Path.GetFullPath(Path.Combine(__SOURCE_DIRECTORY__, path)))

        Assert.All(
            sourcePaths,
            fun sourcePath ->
                let source = File.ReadAllText sourcePath

                Assert.All(
                    forbidden,
                    fun token -> Assert.DoesNotContain(token, source, StringComparison.OrdinalIgnoreCase)
                )
        )

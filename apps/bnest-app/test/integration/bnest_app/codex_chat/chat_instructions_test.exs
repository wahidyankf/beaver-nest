defmodule BnestApp.CodexChat.ChatInstructionsTest do
  @moduledoc """
  Contract test for the Codex developer instruction in `priv/codex/chat_instructions.mjs`.

  It starts the CLI that `@openai/codex-sdk` runs, with `developer_instructions` set the way the SDK sets it, and
  reads the prompt that the CLI would send to the model. It makes no model call and writes only to a temporary
  `CODEX_HOME`, so the real `~/.codex` is never read or changed. It fails when an SDK or CLI upgrade stops
  delivering the instruction verbatim.
  """
  use ExUnit.Case, async: false

  alias BnestApp.CodexChat.Adapters.CodexPortSession

  @workspace Path.expand("../../../../../..", __DIR__)
  @instructions_module Path.join(@workspace, "apps/bnest-app/priv/codex/chat_instructions.mjs")
  # The npm entry point of the pinned `@openai/codex` package. It starts the native binary the SDK runs.
  @codex_entry Path.join(@workspace, "node_modules/@openai/codex/bin/codex.js")
  @logo "apps/bnest-app/priv/static/images/beaver-nest-logo.png"

  test "the developer instruction reaches the model as a verbatim developer message" do
    # A checkout without `npm ci` fails here, loudly, rather than skipping the contract.
    assert File.exists?(@codex_entry),
           "the pinned Codex CLI is not installed at #{@codex_entry}; run npm ci first"

    {instructions, override} = load_instruction()
    codex_home = temporary_codex_home()

    {output, status} =
      System.cmd(
        node!(),
        [@codex_entry, "debug", "prompt-input", "-c", override, "Contract probe"],
        env: [{"CODEX_HOME", codex_home}, {"HOME", codex_home}],
        stderr_to_stdout: false
      )

    assert status == 0, "codex debug prompt-input failed: #{output}"

    developer_texts =
      output
      |> Jason.decode!()
      |> Enum.filter(&match?(%{"role" => "developer"}, &1))
      |> Enum.flat_map(&Map.get(&1, "content", []))
      |> Enum.filter(&match?(%{"type" => "input_text"}, &1))
      |> Enum.map(& &1["text"])

    assert instructions in developer_texts
  end

  # The runner must pass the instruction to the SDK constructor as `config`, the way the SDK sends
  # it to the CLI. A stub SDK in a temporary directory records the constructor options, so the test
  # proves the wiring without a model call and without the real CLI.
  test "the runner passes the developer instruction to the Codex constructor as config" do
    {instructions, _override} = load_instruction()
    workspace = temporary_directory("bnest-codex-runner-stub")
    record = Path.join(workspace, "constructor.json")
    sdk_directory = Path.join(workspace, "node_modules/@openai/codex-sdk")

    File.mkdir_p!(Path.join(sdk_directory, "dist"))
    File.write!(Path.join(sdk_directory, "package.json"), ~s({"type": "module"}))
    File.write!(Path.join(sdk_directory, "dist/index.js"), stub_sdk())

    probe = """
    process.stdin.push(null);
    process.argv.splice(2, 0, #{inspect(workspace)}, "gpt-5.6-terra", "medium", "", "read-only");
    await import(process.argv[1]);
    """

    {output, status} =
      System.cmd(
        node!(),
        ["--input-type=module", "--eval", probe, CodexPortSession.bundled_runner()],
        env: [{"BNEST_STUB_RECORD", record}],
        stderr_to_stdout: true
      )

    assert status == 0, "the runner failed against the stub SDK: #{output}"

    assert %{"config" => %{"developer_instructions" => ^instructions}} =
             record |> File.read!() |> Jason.decode!()
  end

  test "the instruction asks for Markdown and repository images only, and names the example file" do
    {text, _override} = load_instruction()

    assert text =~ "Markdown"
    assert text =~ "Never write raw HTML"
    assert text =~ "png, jpg, jpeg, gif and webp"
    assert text =~ "SVG"
    assert text =~ "data: URIs"
    assert text =~ "absolute paths"
    assert text =~ "external image URLs"
    assert text =~ @logo
    assert File.regular?(Path.join(@workspace, @logo))
  end

  # Loads the module with the same Node the chat runner uses. The `--config` value is built the way the SDK builds
  # it for `config: { developer_instructions: text }`: `key=` followed by the JSON string of the text.
  defp load_instruction do
    script = """
    import { pathToFileURL } from "node:url";
    const { developerInstructions } = await import(pathToFileURL(process.argv[1]).href);
    process.stdout.write(JSON.stringify({
      text: developerInstructions,
      override: `developer_instructions=${JSON.stringify(developerInstructions)}`,
    }));
    """

    {output, status} =
      System.cmd(node!(), ["--input-type=module", "-e", script, @instructions_module],
        stderr_to_stdout: true
      )

    assert status == 0, "could not load the developer instruction: #{output}"

    # Node may print warnings before the JSON line, so only the last line is the payload.
    %{"text" => text, "override" => override} =
      output |> String.split("\n", trim: true) |> List.last() |> Jason.decode!()

    {text, override}
  end

  defp temporary_codex_home, do: temporary_directory("bnest-codex-contract")

  defp temporary_directory(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  # Records the options the runner gives the constructor, then ends the turn stream at once.
  defp stub_sdk do
    """
    import { writeFileSync } from "node:fs";

    export class Codex {
      constructor(options) {
        writeFileSync(process.env.BNEST_STUB_RECORD, JSON.stringify(options ?? {}));
      }

      startThread() {
        return { runStreamed: async () => ({ events: (async function* () {})() }) };
      }

      resumeThread() {
        return this.startThread();
      }
    }
    """
  end

  defp node! do
    System.find_executable("node") || raise "node is required to run the Codex contract test"
  end
end

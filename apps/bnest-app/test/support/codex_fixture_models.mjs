// The local Codex model list (`codex app-server model/list`) as read on the development machine, so
// the picker's filtering runs on the real ids, display names and efforts. Mirrors
// `BnestApp.Test.CodexFixtureModels`.
const models = [
  [
    "gpt-6.1-sol",
    "GPT-6.1-Sol",
    "low",
    ["low", "medium", "high", "xhigh", "max", "ultra"],
    true,
  ],
  [
    "gpt-6-astra",
    "GPT-6-Astra",
    "low",
    ["low", "medium", "high", "xhigh", "max", "ultra"],
    false,
  ],
  [
    "gpt-6.1-terra",
    "GPT-6.1 Terra",
    "low",
    ["low", "medium", "high", "xhigh", "max", "ultra"],
    false,
  ],
  [
    "gpt-6-sol",
    "GPT-6-Sol",
    "medium",
    ["low", "medium", "high", "xhigh", "max", "ultra"],
    false,
  ],
  [
    "gpt-6-luna",
    "GPT-6-Luna",
    "medium",
    ["low", "medium", "high", "xhigh", "max"],
    false,
  ],
  [
    "gpt-5.6-sol",
    "GPT-5.6-Sol",
    "low",
    ["low", "medium", "high", "xhigh", "max", "ultra"],
    false,
  ],
  [
    "gpt-5.6-terra",
    "GPT-5.6-Terra",
    "medium",
    ["low", "medium", "high", "xhigh", "max", "ultra"],
    false,
  ],
  [
    "gpt-5.6-luna",
    "GPT-5.6-Luna",
    "medium",
    ["low", "medium", "high", "xhigh", "max"],
    false,
  ],
].map(
  ([
    id,
    display_name,
    default_reasoning_effort,
    supported_reasoning_efforts,
    is_default,
  ]) => ({
    id,
    display_name,
    default_reasoning_effort,
    supported_reasoning_efforts,
    is_default,
  }),
);

process.stdout.write(`${JSON.stringify(models)}\n`);

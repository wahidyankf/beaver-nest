const models = [
  [
    "gpt-5.6-sol",
    "GPT-5.6-Sol",
    "low",
    ["low", "medium", "high", "xhigh", "max", "ultra"],
    true,
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
  ["gpt-5.5", "GPT-5.5", "medium", ["low", "medium", "high", "xhigh"], false],
  ["gpt-5.4", "GPT-5.4", "medium", ["low", "medium", "high", "xhigh"], false],
  [
    "gpt-5.4-mini",
    "GPT-5.4-Mini",
    "medium",
    ["low", "medium", "high", "xhigh"],
    false,
  ],
  [
    "gpt-5.3-codex-spark",
    "GPT-5.3-Codex-Spark",
    "high",
    ["low", "medium", "high", "xhigh"],
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

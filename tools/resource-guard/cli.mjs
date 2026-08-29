#!/usr/bin/env node

import { runCli } from "./cli-application.mjs";

runCli()
  .then((exitCode) => {
    process.exitCode = exitCode;
  })
  .catch((error) => {
    process.stderr.write(`Resource guard failed: ${error.message}\n`);
    process.exitCode = 1;
  });

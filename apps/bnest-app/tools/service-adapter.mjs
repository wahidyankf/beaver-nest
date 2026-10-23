// Picks the service-manager adapter for the platform the release tool runs on
// (D-11). Any platform other than darwin or linux fails closed with a named
// error (L-05); it writes nothing, because the caller stops before any work.

import * as launchd from "./launchd.mjs";
import * as systemd from "./systemd.mjs";

export function serviceAdapter(platform) {
  if (platform === "darwin") return launchd;
  if (platform === "linux") return systemd;
  throw new Error(
    `unsupported platform "${platform}": the release tool supports darwin (launchd) and linux (systemd) only.`,
  );
}

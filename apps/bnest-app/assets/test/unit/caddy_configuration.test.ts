// Plain Vitest unit coverage for the reverse-proxy configuration the deployment tool writes
// (`tools/caddy-config.mjs`). The generator is side-effect free, so each scenario reads the
// real configuration it produces; no Caddy binary runs and no service is touched.

import { describe, expect, it } from "vitest";
import { caddyfile, slots, type Slot } from "../../../tools/caddy-config.mjs";

const slotNames = Object.keys(slots) as Slot[];

describe("generated reverse-proxy configuration", () => {
  // @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: The generated Caddy configuration rejects a nonzero stream-close delay
  it("omits every stream-close directive and keeps the global five-minute grace period", () => {
    for (const slot of slotNames) {
      for (const healthChecked of [true, false]) {
        const config = caddyfile(slot, healthChecked);

        expect(config).not.toMatch(/stream[_-]?close/iu);
        expect(config).toMatch(/^\tgrace_period 5m$/mu);
      }
    }
  });

  // @scenario specs/apps/bnest/app-be/behaviours/family_chat_operations.feature: A replacement handshake routes only to the promoted slot while the prior slot stays warm
  it("routes a replacement handshake only to the promoted slot, and keeps the prior slot warm", () => {
    for (const promoted of slotNames) {
      const prior = slotNames.find((slot) => slot !== promoted);
      if (prior === undefined)
        throw new Error("the configuration names no prior slot");

      const upstreams = [
        ...caddyfile(promoted, true).matchAll(/reverse_proxy\s+(\S+)/gu),
      ].map((match) => match[1]);

      expect(upstreams).toEqual([`127.0.0.1:${slots[promoted]}`]);
      expect(upstreams).not.toContain(`127.0.0.1:${slots[prior]}`);
      // The prior slot stays warm: its own configuration still names its port.
      expect(caddyfile(prior, true)).toContain(`127.0.0.1:${slots[prior]}`);
    }
  });
});

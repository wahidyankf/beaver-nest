export type Slot = "blue" | "green";

export const slots: Record<Slot, number>;

export function caddyfile(slot: Slot, healthChecked: boolean): string;

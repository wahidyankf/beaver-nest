export type PortLease = { owner: string; path: string; port: number };

export function acquirePortLease(
  port: number,
  owner: string,
  minimum: number,
  maximum: number,
): PortLease;

export function releasePortLease(lease: PortLease): void;

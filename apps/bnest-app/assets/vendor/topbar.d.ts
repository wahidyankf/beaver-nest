interface TopbarOptions {
  autoRun?: boolean;
  barColors?: Record<string, string>;
  barThickness?: number;
  className?: string | null;
  shadowBlur?: number;
  shadowColor?: string;
}

interface Topbar {
  config(options: TopbarOptions): void;
  hide(): void;
  progress(to?: number | string): number;
  show(delay?: number): void;
}

declare const topbar: Topbar;

export default topbar;

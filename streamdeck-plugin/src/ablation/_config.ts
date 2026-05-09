/**
 * Ablation axis selector. Switching this single line is the entire ablation
 * activation surface. "off" means the adapter loads but installs no patch;
 * runtime behavior must be byte-for-byte identical to baseline.
 */
export type AxisName = "off" | "1a" | "2" | "3" | "4" | "5" | "6" | "7";

export const CURRENT_AXIS: AxisName = "off";

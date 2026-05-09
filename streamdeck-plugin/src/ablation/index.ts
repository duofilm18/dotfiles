/**
 * Ablation entry point. Imported once from plugin.ts. Side-effect modules
 * below decide internally whether to install themselves based on CURRENT_AXIS.
 *
 * When CURRENT_AXIS === "off", every imported module no-ops at module load
 * and runtime behavior is identical to baseline.
 */
import "./ws-send-patch";

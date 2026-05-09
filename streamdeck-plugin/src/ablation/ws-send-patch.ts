/**
 * Outgoing WebSocket send-path adapter. Installs a single monkey-patch on
 * `ws.WebSocket.prototype.send` so we can mutate or drop SDK commands before
 * they reach Stream Deck host. Used by axes 1a, 3, 5.
 *
 * Design constraints:
 *   - Module-level ENABLED gate. When CURRENT_AXIS === "off" the patch is
 *     never installed, so T0 baseline is byte-identical to upstream.
 *   - Fail-open. Any throw inside the patch falls through to the original
 *     send. Worst case is "ablation didn't apply", never "plugin broken".
 *   - Touches only WebSocket.prototype. No SDK files, no action files,
 *     no mqtt-handler.
 */
import WebSocket from "ws";
import { CURRENT_AXIS } from "./_config";

const ENABLED =
  CURRENT_AXIS === "1a" ||
  CURRENT_AXIS === "3" ||
  CURRENT_AXIS === "5";

if (ENABLED) {
  const origSend = WebSocket.prototype.send as (...args: unknown[]) => void;

  WebSocket.prototype.send = function patchedSend(
    this: WebSocket,
    ...args: unknown[]
  ): void {
    try {
      const data = args[0];
      if (typeof data !== "string") {
        return origSend.apply(this, args);
      }

      const command = JSON.parse(data) as { event?: string; payload?: unknown };
      const event = command?.event;

      if (event === "setImage" || event === "setTitle") {
        if (CURRENT_AXIS === "1a") {
          const payload = (command.payload ?? {}) as Record<string, unknown>;
          command.payload = { ...payload, target: 1 };
          return origSend.apply(this, [JSON.stringify(command), ...args.slice(1)]);
        }
        if (CURRENT_AXIS === "3") {
          return;
        }
        // CURRENT_AXIS === "5": instrumentation hook (not yet implemented)
      }
    } catch (err) {
      console.error(`[ablation ws-send-patch] fail-open: ${String(err)}`);
      return origSend.apply(this, args);
    }
    return origSend.apply(this, args);
  } as typeof WebSocket.prototype.send;

  console.error(`[ablation ws-send-patch] installed (axis=${CURRENT_AXIS})`);
}

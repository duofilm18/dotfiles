/**
 * MQTT boundary adapter for ablation axes that must alter subscription
 * behavior. The default "off" path returns baseline behavior.
 */
import { CURRENT_AXIS } from "./_config";

export function shouldSubscribeToMqtt(): boolean {
  return CURRENT_AXIS !== "2";
}

import "./ablation";
import streamDeck from "@elgato/streamdeck";
import { shouldConnectToMqtt } from "./ablation/mqtt-adapter";
import { ClaudeStatusAction } from "./actions/claude-status";
import { ClaudeDateAction } from "./actions/claude-date";
import { SystemStatsAction } from "./actions/system-stats";
import { WinStatsAction } from "./actions/win-stats";
import { MqttHandler } from "./mqtt-handler";
import { StateReader } from "./state-reader";
import { DEFAULT_SETTINGS, type GlobalSettings } from "./types";

// Data source for project / sys / win state.
//
//   "file"  — read snapshots from %LOCALAPPDATA%\claude-monitor\state.json,
//             written by the out-of-process sidecar (sidecar/sidecar.mjs).
//             This avoids the SD plugin sandbox CPU regression triggered by
//             any outgoing TCP socket from the plugin Node process. See
//             tests/cpu-ablation-log.md (T0..T8) and sidecar/README.md.
//
//   "mqtt"  — legacy in-process MqttHandler. Reproduces the regression
//             (~20% Plugin Node + ~66% StreamDeck.exe). Kept for fallback
//             and ablation, not for normal operation.
const DATA_SOURCE: "file" | "mqtt" = "file";

// --- Action instances ---
const statusAction = new ClaudeStatusAction();
const dateAction = new ClaudeDateAction();
const sysStatsAction = new SystemStatsAction();
const winStatsAction = new WinStatsAction();

// --- Register actions ---
streamDeck.actions.registerAction(statusAction);
streamDeck.actions.registerAction(dateAction);
streamDeck.actions.registerAction(sysStatsAction);
streamDeck.actions.registerAction(winStatsAction);

// --- Start SDK connection ---
streamDeck.connect();

if (DATA_SOURCE === "file") {
  streamDeck.logger.info("[plugin] data source = file (sidecar)");
  const reader = new StateReader(statusAction, sysStatsAction, winStatsAction, 1000);
  setTimeout(() => reader.start(), 500);
} else {
  streamDeck.logger.info("[plugin] data source = mqtt (legacy in-process)");

  const mqttHandler = new MqttHandler(
    (project, state) => {
      if (state === null) {
        statusAction.removeProject(project);
      } else {
        statusAction.assignProject(project, state);
      }
    },
    (cache) => {
      statusAction.rebuild(cache);
    },
    (temp, ram) => {
      sysStatsAction.updateStats(temp, ram);
    },
    (temp, freq, ram) => {
      winStatsAction.updateStats(temp, freq, ram);
    },
  );

  /** 從 globalSettings 讀取 MQTT broker 設定並連線 */
  async function connectMqtt(): Promise<void> {
    if (!shouldConnectToMqtt()) {
      streamDeck.logger.info("MQTT ablation axis 6: connect skipped");
      return;
    }
    const settings =
      await streamDeck.settings.getGlobalSettings<GlobalSettings>();
    const broker = settings.mqttBroker || DEFAULT_SETTINGS.mqttBroker;
    const port = settings.mqttPort || DEFAULT_SETTINGS.mqttPort;
    mqttHandler.connect(broker, port);
  }

  streamDeck.settings.onDidReceiveGlobalSettings<GlobalSettings>(() => {
    connectMqtt();
  });

  // SDK ready 後連線 MQTT（短延遲確保 WebSocket 已建立）
  setTimeout(connectMqtt, 500);
}

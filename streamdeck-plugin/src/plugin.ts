import streamDeck from "@elgato/streamdeck";
import { ClaudeStatusAction } from "./actions/claude-status";
import { ClaudeDateAction } from "./actions/claude-date";
import { MqttHandler } from "./mqtt-handler";
import { DEFAULT_SETTINGS, type GlobalSettings } from "./types";

// --- Action instances ---
const statusAction = new ClaudeStatusAction();
const dateAction = new ClaudeDateAction();

// --- MQTT ---
const mqttHandler = new MqttHandler(
  // onStateChange
  (project, state) => {
    if (state === null) {
      statusAction.removeProject(project);
    } else {
      statusAction.assignProject(project, state);
    }
  },
  // onRebuild
  (cache) => {
    statusAction.rebuild(cache);
  },
);

/** 從 globalSettings 讀取 MQTT broker 設定並連線 */
async function connectMqtt(): Promise<void> {
  const settings =
    await streamDeck.settings.getGlobalSettings<GlobalSettings>();
  const broker = settings.mqttBroker || DEFAULT_SETTINGS.mqttBroker;
  const port = settings.mqttPort || DEFAULT_SETTINGS.mqttPort;
  mqttHandler.connect(broker, port);
}

// --- 註冊 actions ---
streamDeck.actions.registerAction(statusAction);
streamDeck.actions.registerAction(dateAction);

// --- Settings 變更時重連 MQTT ---
streamDeck.settings.onDidReceiveGlobalSettings<GlobalSettings>(() => {
  connectMqtt();
});

// --- 啟動 ---
streamDeck.connect();

// SDK ready 後連線 MQTT（短延遲確保 WebSocket 已建立）
setTimeout(connectMqtt, 500);

import {
  action,
  SingletonAction,
  type KeyDownEvent,
  type WillAppearEvent,
} from "@elgato/streamdeck";
import streamDeck from "@elgato/streamdeck";
import { execFile } from "node:child_process";

const ICON_PATH = "imgs/stats-bg";

function todayStr(): string {
  const now = new Date();
  return (
    now.getFullYear().toString() +
    (now.getMonth() + 1).toString().padStart(2, "0") +
    now.getDate().toString().padStart(2, "0")
  );
}

function todayTitle(): string {
  const now = new Date();
  const yyyy = now.getFullYear().toString();
  const mmdd =
    (now.getMonth() + 1).toString().padStart(2, "0") +
    now.getDate().toString().padStart(2, "0");
  return `${yyyy}\n${mmdd}`;
}

/**
 * 顯示今日日期，按下貼上 YYYYMMDD。
 * 靜態背景 + setTitle 顯示日期。每 60 秒檢查跨日。
 */
@action({ UUID: "com.duofilm.claude-monitor.claude-date" })
export class ClaudeDateAction extends SingletonAction {
  private lastTitle = "";

  constructor() {
    super();
    setInterval(() => this.checkDateChange(), 60_000);
  }

  override async onWillAppear(ev: WillAppearEvent): Promise<void> {
    await ev.action.setImage(ICON_PATH);
    this.lastTitle = todayTitle();
    await ev.action.setTitle(this.lastTitle);
  }

  override async onKeyDown(ev: KeyDownEvent): Promise<void> {
    const today = todayStr();
    const psCmd =
      `Set-Clipboard -Value '${today}'; ` +
      "Add-Type -AssemblyName System.Windows.Forms; " +
      "[System.Windows.Forms.SendKeys]::SendWait('^v')";

    execFile(
      "powershell.exe",
      ["-WindowStyle", "Hidden", "-Command", psCmd],
      (err) => {
        if (err) streamDeck.logger.error(`Date paste failed: ${err.message}`);
      },
    );
    streamDeck.logger.info(`Date typed: ${today}`);
  }

  private checkDateChange(): void {
    const title = todayTitle();
    if (title === this.lastTitle) return;
    this.lastTitle = title;
    for (const a of this.actions) {
      a.setTitle(title);
    }
  }
}

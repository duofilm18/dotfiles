import {
  action,
  SingletonAction,
  type KeyDownEvent,
  type WillAppearEvent,
} from "@elgato/streamdeck";
import streamDeck from "@elgato/streamdeck";
import { execFile } from "node:child_process";
import { renderDateSvg, svgToDataUri } from "../renderer";

/** 取得今天的 YYYYMMDD 字串 */
function todayStr(): string {
  const now = new Date();
  const yyyy = now.getFullYear().toString();
  const mm = (now.getMonth() + 1).toString().padStart(2, "0");
  const dd = now.getDate().toString().padStart(2, "0");
  return `${yyyy}${mm}${dd}`;
}

/**
 * Claude Date action：顯示日期 + 按下貼上
 *
 * YYYY 上半、MMDD 下半。每 60 秒檢查日期變化。
 * 按下 → PowerShell 複製到剪貼簿 + SendKeys Ctrl+V
 */
@action({ UUID: "com.duofilm.claude-monitor.claude-date" })
export class ClaudeDateAction extends SingletonAction {
  private lastDate = "";

  constructor() {
    super();
    // 每 60 秒檢查日期變化
    setInterval(() => this.checkDateChange(), 60_000);
  }

  override async onWillAppear(ev: WillAppearEvent): Promise<void> {
    this.lastDate = todayStr();
    await ev.action.setImage(svgToDataUri(renderDateSvg()));
  }

  override async onKeyDown(ev: KeyDownEvent): Promise<void> {
    const today = todayStr();

    // 複製到剪貼簿 + 模擬 Ctrl+V 貼上
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

  /** 跨日時更新所有 date action 實例的顯示 */
  private checkDateChange(): void {
    const today = todayStr();
    if (today === this.lastDate) return;

    this.lastDate = today;
    const uri = svgToDataUri(renderDateSvg());
    for (const a of this.actions) {
      a.setImage(uri);
    }
  }
}

import {
  action,
  SingletonAction,
  type WillAppearEvent,
} from "@elgato/streamdeck";
import { renderWinStatsSvg, svgToDataUri } from "../renderer";

@action({ UUID: "com.duofilm.claude-monitor.win-stats" })
export class WinStatsAction extends SingletonAction {
  private lastTemp = 0;
  private lastFreq = 0;
  private lastRam = 0;

  override async onWillAppear(ev: WillAppearEvent): Promise<void> {
    await ev.action.setImage(svgToDataUri(renderWinStatsSvg(this.lastTemp, this.lastFreq, this.lastRam)));
  }

  /** 由 plugin.ts 的 MQTT callback 呼叫 */
  updateStats(temp: number, freq: number, ram: number): void {
    this.lastTemp = temp;
    this.lastFreq = freq;
    this.lastRam = ram;
    const uri = svgToDataUri(renderWinStatsSvg(temp, freq, ram));
    for (const a of this.actions) {
      a.setImage(uri);
    }
  }
}

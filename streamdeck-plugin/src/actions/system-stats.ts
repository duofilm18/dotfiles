import {
  action,
  SingletonAction,
  type WillAppearEvent,
} from "@elgato/streamdeck";
import { renderSysStatsSvg, svgToDataUri } from "../renderer";

@action({ UUID: "com.duofilm.claude-monitor.system-stats" })
export class SystemStatsAction extends SingletonAction {
  private lastTemp = 0;
  private lastRam = 0;

  override async onWillAppear(ev: WillAppearEvent): Promise<void> {
    await ev.action.setImage(svgToDataUri(renderSysStatsSvg(this.lastTemp, this.lastRam)));
  }

  /** 由 plugin.ts 的 MQTT callback 呼叫 */
  updateStats(temp: number, ram: number): void {
    this.lastTemp = temp;
    this.lastRam = ram;
    const uri = svgToDataUri(renderSysStatsSvg(temp, ram));
    for (const a of this.actions) {
      a.setImage(uri);
    }
  }
}

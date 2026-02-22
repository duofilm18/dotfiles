#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ── 設定 ──
OFFSET_X := 15           ; 游標右方偏移
OFFSET_Y := 20           ; 游標下方偏移
FONT_SIZE := 14          ; 文字大小
LABEL_ZH := "中"
LABEL_EN := "EN"
COLOR_ZH := "FF6600"     ; 中文 = 橘色
COLOR_EN := "00AA00"     ; 英文 = 綠色

; ── 狀態（注音 IME 預設開啟為中文）──
isChinese := 1

; ── 建立指示器視窗（文字跟隨游標）──
indicator := Gui("+AlwaysOnTop -Caption +ToolWindow")
indicator.BackColor := "1a1a1a"
indicator.SetFont("s" FONT_SIZE " bold c" COLOR_ZH, "Microsoft JhengHei UI")
label := indicator.Add("Text", "vLabel Center w30", LABEL_ZH)
indicator.Show("AutoSize NoActivate")
WinSetExStyle("+0x20", indicator)
WinSetTransparent(220, indicator)

; ── 偵測「單獨按 Shift」切換中英 ──
~LShift Up:: {
    global isChinese
    if (A_PriorKey = "LShift") {
        isChinese := !isChinese
        UpdateLabel()
    }
}
~RShift Up:: {
    global isChinese
    if (A_PriorKey = "RShift") {
        isChinese := !isChinese
        UpdateLabel()
    }
}

UpdateLabel() {
    global isChinese, label, indicator
    if (isChinese) {
        label.SetFont("c" COLOR_ZH)
        label.Value := LABEL_ZH
    } else {
        label.SetFont("c" COLOR_EN)
        label.Value := LABEL_EN
    }
}

; ── 跟隨游標位置 ──
SetTimer(FollowCursor, 100)

lastX := 0
lastY := 0

FollowCursor() {
    global lastX, lastY
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mx, &my)
    if (mx != lastX || my != lastY) {
        lastX := mx
        lastY := my
        indicator.Show("x" (mx + OFFSET_X) " y" (my + OFFSET_Y) " NoActivate")
    }
}

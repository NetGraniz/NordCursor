#Requires AutoHotkey v2.0
#SingleInstance Force

; NordCursor — GDI+ interface adapted from NordEye.
; Every button and dropdown row is painted, not a native rectangular control.
InstallKeybdHook true, true
InstallMouseHook true, true
CoordMode "Mouse", "Screen"

global idleDelay := 30000
global idleValues := [15000, 30000, 60000, 300000]
global idleLabels := ["15 sec", "30 sec", "1 min", "5 min"]
global idleIndex := 2
global radius := 5
global radiusValues := [1, 5, 20]
global radiusLabels := ["1 px", "5 px", "20 px"]
global radiusIndex := 2
global speedIndex := 1
global speedLabels := ["Smooth", "Normal", "Fast"]
global speedSteps := [0.09, 0.15, 0.24]
global angle := 0.0
global centerX := 0
global centerY := 0
global lastAutoX := 0
global lastAutoY := 0
global enabledAt := A_TickCount
global lastPhysicalInput := A_TickCount
global isEnabled := true
global isMoving := false

global gdipToken := 0
global fontFamily := 0
global dropdownGui := 0
global dropdownPanel := 0
global openKind := ""
global statusTitle := "Waiting for inactivity"
global statusHint := "Movement will start automatically"
global statusColor := 0xFF60D6A4

; -DPIScale keeps painted hit regions aligned with cursor coordinates.
global app := Gui("-Caption -Resize -DPIScale", "NordCursor")
app.BackColor := "121B29"
app.MarginX := 0
app.MarginY := 0
global panel := app.AddPicture("x0 y0 w432 h332 +0x100")
panel.OnEvent("Click", HandlePanelClick)
app.OnEvent("Close", CloseApp)
app.OnEvent("Escape", CloseDropdown)
app.OnEvent("Size", HandleSize)
OnMessage(0x0201, HandleMouseDown)
OnMessage(0x0006, HandleActivate)
OnExit CleanUp

A_IconTip := "NordCursor"
A_TrayMenu.Delete()
A_TrayMenu.Add("Open NordCursor", ShowApp)
A_TrayMenu.Add("Pause / Resume", Toggle)
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", ExitApplication)
A_TrayMenu.Default := "Open NordCursor"
A_TrayMenu.ClickCount := 1

StartGraphics()
app.Show("w432 h332")
RoundWindow(app.Hwnd, 16, 432, 332)
SetDarkWindow(app.Hwnd)
DrawPanel()
SetExecutionState(true)
SetTimer CheckIdle, 40

; ---------- Graphics (same GDI+ approach as NordEye) ----------

StartGraphics() {
    global gdipToken, fontFamily
    startup := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut "UInt", 1, startup, 0
    DllCall("gdiplus\GdiplusStartup", "Ptr*", &gdipToken, "Ptr", startup, "Ptr", 0)
    DllCall("gdiplus\GdipCreateFontFamilyFromName", "WStr", "Segoe UI", "Ptr", 0, "Ptr*", &fontFamily)
}

DrawPanel() {
    global panel, idleIndex, radiusIndex, speedIndex
    global idleLabels, radiusLabels, speedLabels, statusTitle, statusHint, statusColor
    global isEnabled, isMoving
    g := BeginPaint(432, 332, 0xFF121B29, &bitmap)

    ; NordEye-style cyan frame: several subtle outlines, not a sharp neon stroke.
    GlowFrame(g, 0, 0, 432, 332, 16, 0xFF314258)
    Rounded(g, 20, 20, 40, 40, 11, 0xFF1E3149, 0xFF335477, 1)
    Outline(g, 22, 22, 36, 36, 10, 0x3436B5F4, 1)
    TextAt(g, "◎", 20, 20, 40, 40, 21, 0xFF18C3F7, true, 1)
    TextAt(g, "NordCursor", 72, 20, 235, 38, 18, 0xFFE9F4FF, true)
    TextAt(g, isEnabled ? "АКТИВНО" : "ПАУЗА", 72, 48, 145, 16, 9
        , isEnabled ? 0xFF59DFAE : 0xFF7F94AD)
    Line(g, 365, 39, 375, 39, 0xFF8498B1, 1.7)
    Line(g, 398, 35, 406, 43, 0xFF8498B1, 1.7)
    Line(g, 406, 35, 398, 43, 0xFF8498B1, 1.7)

    ; Each selector gets its own cyan border and a soft external halo.
    TextAt(g, "Start after inactivity", 20, 89, 275, 35, 13, 0xFFE6F2FF, true)
    TextAt(g, "Movement radius", 20, 134, 275, 35, 13, 0xFFE6F2FF, true)
    TextAt(g, "Speed", 20, 179, 275, 35, 13, 0xFFE6F2FF, true)
    DrawSelect(g, 302, 90, idleLabels[idleIndex])
    DrawSelect(g, 302, 135, radiusLabels[radiusIndex])
    DrawSelect(g, 302, 180, speedLabels[speedIndex])

    ; Status card has the same rounded illuminated surface as NordEye buttons.
    Rounded(g, 20, 230, 392, 82, 13, 0xFF172438, 0xFF2D4763, 1.1)
    Outline(g, 22, 232, 388, 78, 12, 0x273BB9F0, 1)
    Outline(g, 24, 234, 384, 74, 11, 0x1242AFFF, 1)
    Rounded(g, 34, 245, 28, 28, 11, 0xFF1E3149, 0xFF335477, 1)
    TextAt(g, isMoving ? "↗" : isEnabled ? "✓" : "Ⅱ", 35, 247, 26, 24, 13, statusColor, true, 1)
    TextAt(g, statusTitle, 72, 239, 219, 32, 13, 0xFFE9F4FF, true)
    TextAt(g, statusHint, 35, 276, 251, 26, 11, 0xFF94A9C4)
    ; Uses the existing Toggle() action, now available from the panel too.
    if isEnabled {
        Rounded(g, 300, 252, 101, 44, 11, 0xFF213149, 0xFF344C68, 1.1)
        Outline(g, 302, 254, 97, 40, 10, 0x302FAEF0, 1)
        TextAt(g, "Ⅱ Pause", 302, 254, 97, 40, 12, 0xFFD8E6F8, true, 1)
    } else {
        Outline(g, 298, 250, 105, 48, 12, 0x1A32CFFF, 1)
        Rounded(g, 300, 252, 101, 44, 11, 0xFF0EADE8, 0xFF32D9FF, 1.3)
        Outline(g, 302, 254, 97, 40, 10, 0x652AF0FF, 1)
        TextAt(g, "▶ Resume", 302, 254, 97, 40, 12, 0xFFFFFFFF, true, 1)
    }
    EndPaint(panel, g, bitmap)
}

DrawSelect(g, x, y, label) {
    ; Three soft outer rings give the same focused glow as NordEye controls.
    Outline(g, x - 3, y - 3, 116, 39, 12, 0x0E3CCAFF, 1)
    Outline(g, x - 2, y - 2, 114, 37, 11, 0x2053C8FF, 1)
    Rounded(g, x, y, 110, 33, 10, 0xFF1D2B40, 0xFF37618B, 1.2)
    Outline(g, x + 1.5, y + 1.5, 107, 30, 9, 0x3635C8F9, 1)
    TextAt(g, label, x + 6, y + 1, 79, 31, 12, 0xFFE9F4FF, true, 1)
    Line(g, x + 91, y + 14, x + 95, y + 18, 0xFF9CB6D3, 1.8)
    Line(g, x + 95, y + 18, x + 99, y + 14, 0xFF9CB6D3, 1.8)
}

GlowFrame(g, x, y, w, h, radius, border) {
    for idx, color in [0x0C77CFFF, 0x1668BDFF, 0x295D99D2] {
        offset := 5 - idx
        Outline(g, x + offset, y + offset, w - 2*offset, h - 2*offset, radius, color, 1.2)
    }
    Outline(g, x + 1, y + 1, w - 2, h - 2, radius, border, 1.1)
    Outline(g, x + 2.5, y + 2.5, w - 5, h - 5, radius, 0x432787C3, 1)
}

BeginPaint(w, h, background, &bitmap) {
    bitmap := 0
    g := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", w, "Int", h, "Int", 0
        , "Int", 0x26200A, "Ptr", 0, "Ptr*", &bitmap)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", bitmap, "Ptr*", &g)
    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", g, "Int", 4)
    DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", g, "Int", 4)
    DllCall("gdiplus\GdipGraphicsClear", "Ptr", g, "UInt", background)
    return g
}

EndPaint(picture, g, bitmap) {
    bitmapHandle := 0
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", bitmap, "Ptr*", &bitmapHandle, "UInt", 0xFF121B29)
    picture.Value := "HBITMAP:*" bitmapHandle
    DllCall("gdi32\DeleteObject", "Ptr", bitmapHandle)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", g)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", bitmap)
}

Rounded(g, x, y, w, h, r, fill, border := 0, thickness := 1) {
    path := MakeRoundPath(x, y, w, h, r)
    brush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", fill, "Ptr*", &brush)
    DllCall("gdiplus\GdipFillPath", "Ptr", g, "Ptr", brush, "Ptr", path)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
    if border
        StrokePath(g, path, border, thickness)
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

Outline(g, x, y, w, h, r, color, thickness := 1) {
    path := MakeRoundPath(x, y, w, h, r)
    StrokePath(g, path, color, thickness)
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

MakeRoundPath(x, y, w, h, r) {
    path := 0
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path)
    d := r * 2
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x + w - d, "Float", y, "Float", d, "Float", d, "Float", 270, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x + w - d, "Float", y + h - d, "Float", d, "Float", d, "Float", 0, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x, "Float", y + h - d, "Float", d, "Float", d, "Float", 90, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x, "Float", y, "Float", d, "Float", d, "Float", 180, "Float", 90)
    DllCall("gdiplus\GdipClosePathFigure", "Ptr", path)
    return path
}

StrokePath(g, path, color, width) {
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "UInt", color, "Float", width, "Int", 2, "Ptr*", &pen)
    DllCall("gdiplus\GdipDrawPath", "Ptr", g, "Ptr", pen, "Ptr", path)
    DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
}

Line(g, x1, y1, x2, y2, color, width := 1) {
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "UInt", color, "Float", width, "Int", 2, "Ptr*", &pen)
    DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pen, "Float", x1, "Float", y1, "Float", x2, "Float", y2)
    DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
}

TextAt(g, str, x, y, w, h, size, color, bold := false, center := 0) {
    global fontFamily
    font := 0, brush := 0, fmt := 0
    DllCall("gdiplus\GdipCreateFont", "Ptr", fontFamily, "Float", size, "Int", bold ? 1 : 0, "Int", 2, "Ptr*", &font)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", color, "Ptr*", &brush)
    DllCall("gdiplus\GdipCreateStringFormat", "Int", 0x1000, "UShort", 0, "Ptr*", &fmt)
    DllCall("gdiplus\GdipSetStringFormatAlign", "Ptr", fmt, "Int", center)
    DllCall("gdiplus\GdipSetStringFormatLineAlign", "Ptr", fmt, "Int", 1)
    rect := Buffer(16, 0)
    NumPut "Float", x, rect, 0
    NumPut "Float", y, rect, 4
    NumPut "Float", w, rect, 8
    NumPut "Float", h, rect, 12
    DllCall("gdiplus\GdipDrawString", "Ptr", g, "WStr", str, "Int", -1, "Ptr", font
        , "Ptr", rect, "Ptr", fmt, "Ptr", brush)
    DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", fmt)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
    DllCall("gdiplus\GdipDeleteFont", "Ptr", font)
}

RoundWindow(hwnd, radius, width, height) {
    region := DllCall("gdi32\CreateRoundRectRgn", "Int", 0, "Int", 0
        , "Int", width + 1, "Int", height + 1, "Int", radius * 2, "Int", radius * 2, "Ptr")
    if region && !DllCall("user32\SetWindowRgn", "Ptr", hwnd, "Ptr", region, "Int", 1)
        DllCall("gdi32\DeleteObject", "Ptr", region)
}

SetDarkWindow(hwnd) {
    dark := 1
    DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 20, "Int*", dark, "UInt", 4)
}

; ---------- Mouse interaction / real rounded popup ----------

MouseInClient(hwnd, &x, &y) {
    point := Buffer(8, 0)
    DllCall("user32\GetCursorPos", "Ptr", point)
    DllCall("user32\ScreenToClient", "Ptr", hwnd, "Ptr", point)
    x := NumGet(point, 0, "Int")
    y := NumGet(point, 4, "Int")
}

HandleMouseDown(wParam, lParam, msg, hwnd) {
    global app
    if DllCall("user32\GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != app.Hwnd
        return
    MouseInClient(app.Hwnd, &x, &y)
    if y < 70 && x < 338 {
        CloseDropdown()
        DllCall("user32\ReleaseCapture")
        PostMessage 0xA1, 2,,, "ahk_id " app.Hwnd
    }
}

HandlePanelClick(*) {
    global app
    MouseInClient(app.Hwnd, &x, &y)
    if y >= 20 && y <= 60 && x >= 383 && x < 420 {
        CloseApp()
        return
    }
    if y >= 20 && y <= 60 && x >= 338 && x < 383 {
        MinimizeApp()
        return
    }
    if x >= 300 && x <= 401 && y >= 252 && y <= 296 {
        Toggle()
    } else if x >= 302 && x <= 412 && y >= 90 && y <= 123 {
        ShowDropdown("idle")
    } else if x >= 302 && x <= 412 && y >= 135 && y <= 168 {
        ShowDropdown("radius")
    } else if x >= 302 && x <= 412 && y >= 180 && y <= 213 {
        ShowDropdown("speed")
    } else {
        CloseDropdown()
    }
}

ShowDropdown(kind) {
    global app, dropdownGui, dropdownPanel, openKind
    global idleLabels, idleIndex, radiusLabels, radiusIndex, speedLabels, speedIndex
    if IsObject(dropdownGui) && kind = openKind {
        CloseDropdown()
        return
    }
    CloseDropdown()
    switch kind {
        case "idle":
            labels := idleLabels, selected := idleIndex, anchorY := 90
        case "radius":
            labels := radiusLabels, selected := radiusIndex, anchorY := 135
        case "speed":
            labels := speedLabels, selected := speedIndex, anchorY := 180
    }
    openKind := kind
    w := 152, rowH := 34, h := 12 + rowH * labels.Length
    dropdownGui := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale +E0x08000000 +Owner" app.Hwnd, "")
    dropdownGui.BackColor := "172638"
    dropdownGui.MarginX := 0
    dropdownGui.MarginY := 0
    dropdownPanel := dropdownGui.AddPicture("x0 y0 w" w " h" h " +0x100")
    dropdownPanel.OnEvent("Click", HandleDropdownClick)
    dropdownGui.OnEvent("Escape", CloseDropdown)
    DrawDropdown(labels, selected, w, h)
    point := Buffer(8, 0)
    NumPut "Int", 412 - w, point, 0
    NumPut "Int", anchorY + 37, point, 4
    DllCall("user32\ClientToScreen", "Ptr", app.Hwnd, "Ptr", point)
    x := NumGet(point, 0, "Int"), y := NumGet(point, 4, "Int")
    dropdownGui.Show("Hide x" x " y" y " w" w " h" h)
    RoundWindow(dropdownGui.Hwnd, 12, w, h)
    SetDarkWindow(dropdownGui.Hwnd)
    dropdownGui.Show("NA")
}

DrawDropdown(labels, selected, w, h) {
    global dropdownPanel
    g := BeginPaint(w, h, 0xFF172638, &bitmap)
    Outline(g, 0.7, 0.7, w - 1.4, h - 1.4, 11, 0xFF395776, 1.3)
    Outline(g, 2, 2, w - 4, h - 4, 10, 0x3656BFF9, 1)
    Outline(g, 3.5, 3.5, w - 7, h - 7, 9, 0x1949BAF0, 1)
    for i, label in labels {
        rowY := 6 + (i - 1) * 34
        if i = selected {
            Rounded(g, 6, rowY, w - 12, 31, 8, 0xFF24445D, 0xFF3679A2, 1)
            Outline(g, 7.5, rowY + 1.5, w - 15, 28, 7, 0x3535C8F9, 1)
        } else
            Rounded(g, 6, rowY, w - 12, 31, 8, 0xFF1D2B40)
        TextAt(g, label, 16, rowY + 1, w - 55, 29, 12
            , i = selected ? 0xFF6DDEFF : 0xFFD4E4F6, i = selected)
        if i = selected
            TextAt(g, "✓", w - 31, rowY + 1, 20, 29, 12, 0xFF6DDEFF, true, 1)
    }
    EndPaint(dropdownPanel, g, bitmap)
}

HandleDropdownClick(*) {
    global dropdownGui, openKind
    if !IsObject(dropdownGui)
        return
    MouseInClient(dropdownGui.Hwnd, &x, &y)
    if x < 6 || x > 146 || y < 6
        return
    idx := Floor((y - 6) / 34) + 1
    kind := openKind
    switch kind {
        case "idle":
            if idx < 1 || idx > 4
                return
        case "radius", "speed":
            if idx < 1 || idx > 3
                return
        default:
            return
    }
    SelectDropdown(kind, idx)
}

SelectDropdown(kind, idx) {
    global idleIndex, idleValues, idleDelay, radiusIndex, radiusValues, radius
    global speedIndex, enabledAt, lastPhysicalInput
    switch kind {
        case "idle":
            idleIndex := idx
            idleDelay := idleValues[idx]
            enabledAt := A_TickCount
            lastPhysicalInput := A_TickCount
            StopMoving()
        case "radius":
            radiusIndex := idx
            radius := radiusValues[idx]
            lastPhysicalInput := A_TickCount
            StopMoving()
        case "speed":
            speedIndex := idx
    }
    CloseDropdown()
    DrawPanel()
}

CloseDropdown(*) {
    global dropdownGui, dropdownPanel, openKind
    if IsObject(dropdownGui) {
        dropdownGui.Destroy()
        dropdownGui := 0
        dropdownPanel := 0
    }
    openKind := ""
}

HandleActivate(wParam, lParam, msg, hwnd) {
    global app, dropdownGui
    if hwnd != app.Hwnd || !IsObject(dropdownGui)
        return
    ; Closing a menu should not be triggered when focus goes to its owned popup.
    if (wParam & 0xFFFF) = 0 {
        next := lParam
        if next != dropdownGui.Hwnd
            CloseDropdown()
    }
}

HandleSize(guiObj, minMax, width, height) {
    global app
    if minMax = 0 && guiObj.Hwnd = app.Hwnd {
        RoundWindow(app.Hwnd, 16, 432, 332)
        DrawPanel()
    }
}

MinimizeApp(*) {
    global app
    CloseDropdown()
    app.Minimize()
}

CloseApp(*) {
    global app
    CloseDropdown()
    app.Hide()
}

ShowApp(*) {
    global app
    CloseDropdown()
    app.Show("Restore")
    RoundWindow(app.Hwnd, 16, 432, 332)
    DrawPanel()
    WinActivate "ahk_id " app.Hwnd
}

ExitApplication(*) {
    ExitApp()
}

; ---------- Original cursor movement and power handling ----------

Toggle(*) {
    global isEnabled, enabledAt
    CloseDropdown()
    isEnabled := !isEnabled
    StopMoving()
    if isEnabled {
        enabledAt := A_TickCount
        SetExecutionState(true)
        SetStatus("Waiting for inactivity", "Movement will start automatically", 0xFF60D6A4)
    } else {
        SetExecutionState(false)
        SetStatus("Paused", "Use the tray menu to resume", 0xFFD1A9B6)
    }
}

CheckIdle() {
    global idleDelay, angle, centerX, centerY, lastAutoX, lastAutoY
    global enabledAt, lastPhysicalInput, isEnabled, isMoving
    if !isEnabled
        return
    physicalIdle := Min(A_TimeIdlePhysical, A_TickCount - lastPhysicalInput)
    if physicalIdle < idleDelay {
        StopMoving()
        return
    }
    if A_TickCount - enabledAt < idleDelay
        return
    if !isMoving {
        MouseGetPos &centerX, &centerY
        lastAutoX := centerX
        lastAutoY := centerY
        angle := 0.0
        isMoving := true
        SetStatus("Moving cursor", "Activity keeps the computer awake", 0xFF59BBFF)
        SetTimer MoveCursor, 40
    }
}

MoveCursor() {
    global idleDelay, radius, angle, centerX, centerY, lastAutoX, lastAutoY
    global lastPhysicalInput, isEnabled, isMoving, speedIndex, speedSteps
    if !isEnabled || !isMoving || A_TickCount - lastPhysicalInput < idleDelay
        return
    MouseGetPos &currentX, &currentY
    if currentX != lastAutoX || currentY != lastAutoY {
        lastPhysicalInput := A_TickCount
        StopMoving()
        return
    }
    angle += speedSteps[speedIndex]
    lastAutoX := Round(centerX + radius * Cos(angle))
    lastAutoY := Round(centerY + radius * Sin(angle))
    MouseMove lastAutoX, lastAutoY, 0
}

StopMoving() {
    global isMoving, isEnabled
    SetTimer MoveCursor, 0
    if isMoving {
        isMoving := false
        if isEnabled
            SetStatus("Waiting for inactivity", "Movement will start automatically", 0xFF60D6A4)
    }
}

SetStatus(title, hint, color) {
    global statusTitle, statusHint, statusColor
    statusTitle := title
    statusHint := hint
    statusColor := color
    DrawPanel()
}

SetExecutionState(enable) {
    flags := enable ? 0x80000003 : 0x80000000
    DllCall("Kernel32\SetThreadExecutionState", "UInt", flags, "UInt")
}

CleanUp(*) {
    global gdipToken, fontFamily
    CloseDropdown()
    SetTimer CheckIdle, 0
    SetTimer MoveCursor, 0
    SetExecutionState(false)
    if fontFamily
        DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", fontFamily)
    if gdipToken
        DllCall("gdiplus\GdiplusShutdown", "Ptr", gdipToken)
}

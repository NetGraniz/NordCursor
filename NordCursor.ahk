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
global hoverPart := ""

global gdipToken := 0
global fontFamily := 0
global dropdownGui := 0
global dropdownPanel := 0
global openKind := ""
global statusTitle := "Waiting for inactivity"
global statusHint := "Movement will start automatically"
global statusColor := 0xFF1DCBFB

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
OnMessage(0x0200, HandlePointerMove)
OnMessage(0x02A3, HandlePointerLeave)
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
app.Show("Hide w432 h332")
RoundWindow(app.Hwnd, 18, 432, 332)
SetDarkWindow(app.Hwnd)
DrawPanel()
app.Show()
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
    global panel, idleIndex, radiusIndex, speedIndex, hoverPart
    global idleLabels, radiusLabels, speedLabels, statusTitle, statusHint, statusColor
    global isEnabled, isMoving
    g := BeginPaint(432, 332, 0xFF101C2D, &bitmap)
    DrawWindowShell(g)
    CursorIcon(g, 27, 26, 0xFF20CEFA)
    TextAt(g, "NordCursor", 75, 19, 235, 42, 19.5, 0xFFE9F3FF, true)
    Line(g, 364, 37, 374, 37, 0xFFA1B3CB, 1.6)
    Line(g, 395, 32, 406, 43, 0xFFA1B3CB, 1.6)
    Line(g, 406, 32, 395, 43, 0xFFA1B3CB, 1.6)

    DrawIconTile(g, 25, 88, 43, 43)
    ClockIcon(g, 46.5, 109.5, 0xFFC4D7F1)
    TextAt(g, "Start after inactivity", 82, 89, 180, 40, 12.9, 0xFFE5F1FF)
    DrawControl(g, 254, 90, 153, 39, idleLabels[idleIndex], hoverPart = "idle")

    DrawIconTile(g, 25, 141, 43, 43)
    TargetIcon(g, 46.5, 162.5, 0xFFC4D7F1)
    TextAt(g, "Movement radius", 82, 142, 173, 40, 12.9, 0xFFE5F1FF)
    DrawControl(g, 254, 143, 153, 39, radiusLabels[radiusIndex], hoverPart = "radius")

    DrawIconTile(g, 25, 194, 43, 43)
    GaugeIcon(g, 46.5, 215.5, 0xFFC4D7F1)
    TextAt(g, "Speed", 82, 195, 173, 40, 12.9, 0xFFE5F1FF)
    DrawControl(g, 254, 196, 153, 39, speedLabels[speedIndex], hoverPart = "speed")

    Line(g, 25, 249, 407, 249, 0xFF2B405B, 0.9)
    GradientRounded(g, 23, 260, 386, 59, 11, 0xFF1D3049, 0xFF16263B, 0xFF304763, 0.9)
    Outline(g, 24.7, 261.7, 382.6, 55.6, 10, 0x1C43B9EF, 0.9)
    Rounded(g, 35, 276, 28, 28, 14, 0x242EB7F3)
    Rounded(g, 42, 283, 14, 14, 7, statusColor)
    TextAt(g, statusTitle, 75, 262, 228, 28, 12.7, 0xFFE8F2FF)
    TextAt(g, statusHint, 75, 289, 231, 22, 10.5, 0xFF92AACC)
    ; Functional Pause / Resume action integrated as a small glass button.
    if isEnabled
        DrawCompactAction(g, 311, 272, 87, 35, "Pause", false, hoverPart = "toggle")
    else
        DrawCompactAction(g, 311, 272, 87, 35, "Resume", true, hoverPart = "toggle")
    EndPaint(panel, g, bitmap)
}

CursorIcon(g, x, y, color) {
    ; Crisp mouse-pointer outline similar to the product icon.
    path := 0, pen := 0, brush := 0
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path)
    pts := [[x, y], [x+5, y+32], [x+12, y+24], [x+19, y+36]
        , [x+25, y+33], [x+17, y+20], [x+29, y+18]]
    Loop pts.Length {
        j := A_Index = pts.Length ? 1 : A_Index+1
        DllCall("gdiplus\GdipAddPathLine", "Ptr", path
            , "Float", pts[A_Index][1], "Float", pts[A_Index][2]
            , "Float", pts[j][1], "Float", pts[j][2])
    }
    DllCall("gdiplus\GdipClosePathFigure", "Ptr", path)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", color, "Ptr*", &brush)
    DllCall("gdiplus\GdipFillPath", "Ptr", g, "Ptr", brush, "Ptr", path)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
    DllCall("gdiplus\GdipCreatePen1", "UInt", 0xFF55DFFF, "Float", 1, "Int", 2, "Ptr*", &pen)
    DllCall("gdiplus\GdipDrawPath", "Ptr", g, "Ptr", pen, "Ptr", path)
    DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

ClockIcon(g, x, y, color) {
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "UInt", color, "Float", 1.8, "Int", 2, "Ptr*", &pen)
    DllCall("gdiplus\GdipDrawEllipse", "Ptr", g, "Ptr", pen, "Float", x-12, "Float", y-12, "Float", 24, "Float", 24)
    DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pen, "Float", x, "Float", y-8, "Float", x, "Float", y)
    DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pen, "Float", x, "Float", y, "Float", x+6, "Float", y+4)
    DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
}

TargetIcon(g, x, y, color) {
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "UInt", color, "Float", 1.7, "Int", 2, "Ptr*", &pen)
    DllCall("gdiplus\GdipDrawEllipse", "Ptr", g, "Ptr", pen, "Float", x-12, "Float", y-12, "Float", 24, "Float", 24)
    DllCall("gdiplus\GdipDrawEllipse", "Ptr", g, "Ptr", pen, "Float", x-6, "Float", y-6, "Float", 12, "Float", 12)
    DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
    Rounded(g, x-2, y-2, 4, 4, 2, color)
}

GaugeIcon(g, x, y, color) {
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "UInt", color, "Float", 1.8, "Int", 2, "Ptr*", &pen)
    DllCall("gdiplus\GdipDrawArc", "Ptr", g, "Ptr", pen, "Float", x-13, "Float", y-10, "Float", 26, "Float", 26, "Float", 190, "Float", 160)
    DllCall("gdiplus\GdipDrawLine", "Ptr", g, "Ptr", pen, "Float", x, "Float", y+4, "Float", x+7, "Float", y-5)
    DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
}

DrawCompactAction(g, x, y, w, h, title, primary, hot := false) {
    if hot
        Outline(g, x-2, y-2, w+4, h+4, 10, 0x4636D5FF, 1.4)
    GradientRounded(g, x, y, w, h, 9
        , primary ? 0xFF20C9FD : (hot ? 0xFF2A405B : 0xFF253A54)
        , primary ? 0xFF078FE1 : (hot ? 0xFF1C304A : 0xFF1B2941)
        , primary ? 0xFF46E2FF : 0xFF385879, 1)
    TextAt(g, primary ? "▶" : "Ⅱ", x+6, y, 21, h, 12, 0xFFEAF7FF, true, 1)
    TextAt(g, title, x+26, y, w-30, h, 11.3, 0xFFEAF7FF, false, 1)
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

; -------- Reference-matched GDI+ surfaces / controls --------

GradientRounded(g, x, y, w, h, r, topColor, bottomColor, border := 0, thickness := 1) {
    path := MakeRoundPath(x, y, w, h, r)
    rect := Buffer(16, 0)
    NumPut "Float", x, rect, 0
    NumPut "Float", y, rect, 4
    NumPut "Float", w, rect, 8
    NumPut "Float", h, rect, 12
    brush := 0
    result := DllCall("gdiplus\GdipCreateLineBrushFromRect", "Ptr", rect
        , "UInt", topColor, "UInt", bottomColor, "Int", 1, "Int", 0, "Ptr*", &brush)
    if result || !brush
        DllCall("gdiplus\GdipCreateSolidFill", "UInt", topColor, "Ptr*", &brush)
    DllCall("gdiplus\GdipFillPath", "Ptr", g, "Ptr", brush, "Ptr", path)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", brush)
    if border
        StrokePath(g, path, border, thickness)
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

DrawWindowShell(g) {
    ; An inset shadow + cold, thin rim (rather than a flat outline).
    GradientRounded(g, 0, 0, 432, 332, 18, 0xFF17283E, 0xFF0D1727)
    Outline(g, 0.8, 0.8, 430.4, 330.4, 18, 0x4D39BFFF, 2.4)
    Outline(g, 1.5, 1.5, 429, 329, 18, 0xB13FA9ED, 1.05)
    Outline(g, 3.8, 3.8, 424.4, 324.4, 16, 0x2149B7FF, 2)
    Line(g, 23, 5, 408, 5, 0x193AB9F9, 1)
}

DrawIconTile(g, x, y, w := 43, h := 43) {
    GradientRounded(g, x, y, w, h, 11, 0xFF233650, 0xFF18273D, 0xFF2C405C, 0.9)
    Outline(g, x+1.4, y+1.4, w-2.8, h-2.8, 10, 0x1935B9F4, 1)
}

DrawControl(g, x, y, w, h, label, hot := false) {
    if hot {
        Outline(g, x-3, y-3, w+6, h+6, 13, 0x1F45CFFF, 2)
        Outline(g, x-1.5, y-1.5, w+3, h+3, 12, 0x3C35CCFF, 1.5)
    }
    GradientRounded(g, x, y, w, h, 10, hot ? 0xFF263C57 : 0xFF213249
        , hot ? 0xFF1B2E47 : 0xFF18283F, hot ? 0xFF4AABEF : 0xFF395A7F, 1.2)
    Outline(g, x+1.8, y+1.8, w-3.6, h-3.6, 9, 0x2C2AAAF5, 0.85)
    TextAt(g, label, x+15, y+1, w-52, h-2, 13.6, 0xFFE7F3FF)
    ax := x + w - 25, ay := y + h/2
    Line(g, ax-6, ay-3, ax, ay+3, 0xFFB3CBE6, 1.8)
    Line(g, ax, ay+3, ax+6, ay-3, 0xFFB3CBE6, 1.8)
}

DrawAction(g, x, y, w, h, title, kind, hot := false) {
    if kind = "primary" {
        if hot {
            Outline(g, x-3, y-3, w+6, h+6, 13, 0x3435DEFF, 2.5)
            Outline(g, x-1.5, y-1.5, w+3, h+3, 12, 0x6341D8FF, 1.5)
        }
        GradientRounded(g, x, y, w, h, 11
            , hot ? 0xFF4BE3FF : 0xFF21C5FA, hot ? 0xFF06A6F4 : 0xFF079CE7, 0xFF3DE7FF, 1.25)
        Outline(g, x+1.7, y+1.7, w-3.4, h-3.4, 10, 0x7F97F4FF, 1)
        color := 0xFFFFFFFF
    } else {
        if hot
            Outline(g, x-2, y-2, w+4, h+4, 12, 0x3140C7FA, 1.8)
        GradientRounded(g, x, y, w, h, 11
            , hot ? 0xFF2A4261 : 0xFF26364F, hot ? 0xFF1C304A : 0xFF1C2B42
            , hot ? 0xFF5087BB : 0xFF344E70, 1.1)
        Outline(g, x+1.5, y+1.5, w-3, h-3, 10, 0x2535A8F4, 1)
        color := 0xFFDAE7FA
    }
    if title = "Start" || title = "Running" || title = "Resume" {
        ; Triangle / checkmark, separately drawn to avoid emoji font fallback.
        if title = "Running"
            TextAt(g, "✓", x+10, y+1, 26, h-2, 16, color, true, 1)
        else
            TextAt(g, "▶", x+11, y+1, 24, h-2, 17, color, true, 1)
    } else if title = "Preview" {
        SmallEyeIcon(g, x+17, y+h/2, color)
    } else {
        Rounded(g, x+16, y+h/2-9, 4, 18, 2, color)
        Rounded(g, x+25, y+h/2-9, 4, 18, 2, color)
    }
    TextAt(g, title, x+40, y+1, w-45, h-2, 13.4, color, false, 1)
}

SmallEyeIcon(g, x, y, color) {
    pen := 0
    DllCall("gdiplus\GdipCreatePen1", "UInt", color, "Float", 2.2, "Int", 2, "Ptr*", &pen)
    DllCall("gdiplus\GdipDrawBezier", "Ptr", g, "Ptr", pen
        , "Float", x-12, "Float", y, "Float", x-6, "Float", y-9
        , "Float", x+6, "Float", y-9, "Float", x+12, "Float", y)
    DllCall("gdiplus\GdipDrawBezier", "Ptr", g, "Ptr", pen
        , "Float", x-12, "Float", y, "Float", x-6, "Float", y+9
        , "Float", x+6, "Float", y+9, "Float", x+12, "Float", y)
    DllCall("gdiplus\GdipDrawEllipse", "Ptr", g, "Ptr", pen
        , "Float", x-3.5, "Float", y-3.5, "Float", 7, "Float", 7)
    DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
}

TrackPointerLeave(hwnd) {
    event := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut "UInt", event.Size, event, 0
    NumPut "UInt", 2, event, 4 ; TME_LEAVE
    NumPut "Ptr", hwnd, event, 8
    DllCall("user32\TrackMouseEvent", "Ptr", event)
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

HoverAt(x, y) {
    if x >= 254 && x <= 407 {
        if y >= 90 && y <= 129
            return "idle"
        if y >= 143 && y <= 182
            return "radius"
        if y >= 196 && y <= 235
            return "speed"
    }
    if x >= 311 && x <= 398 && y >= 272 && y <= 307
        return "toggle"
    return ""
}

HandlePointerMove(wParam, lParam, msg, hwnd) {
    global app, hoverPart
    if DllCall("user32\GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != app.Hwnd
        return
    TrackPointerLeave(hwnd)
    MouseInClient(app.Hwnd, &x, &y)
    hovered := HoverAt(x, y)
    if hovered != hoverPart {
        hoverPart := hovered
        DrawPanel()
    }
}

HandlePointerLeave(wParam, lParam, msg, hwnd) {
    global app, hoverPart
    if DllCall("user32\GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") = app.Hwnd && hoverPart != "" {
        hoverPart := ""
        DrawPanel()
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
    if x >= 311 && x <= 398 && y >= 272 && y <= 307 {
        Toggle()
    } else if x >= 254 && x <= 407 && y >= 90 && y <= 129 {
        ShowDropdown("idle")
    } else if x >= 254 && x <= 407 && y >= 143 && y <= 182 {
        ShowDropdown("radius")
    } else if x >= 254 && x <= 407 && y >= 196 && y <= 235 {
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
            labels := radiusLabels, selected := radiusIndex, anchorY := 143
        case "speed":
            labels := speedLabels, selected := speedIndex, anchorY := 196
    }
    openKind := kind
    w := 164, rowH := 34, h := 12 + rowH * labels.Length
    dropdownGui := Gui("-Caption +ToolWindow -DPIScale +E0x08000000 +Owner" app.Hwnd, "")
    dropdownGui.BackColor := "172638"
    dropdownGui.MarginX := 0
    dropdownGui.MarginY := 0
    dropdownPanel := dropdownGui.AddPicture("x0 y0 w" w " h" h " +0x100")
    dropdownPanel.OnEvent("Click", HandleDropdownClick)
    dropdownGui.OnEvent("Escape", CloseDropdown)
    DrawDropdown(labels, selected, w, h)
    point := Buffer(8, 0)
    NumPut "Int", 407 - w, point, 0
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
    GradientRounded(g, 0.5, 0.5, w-1, h-1, 11, 0xFF223750, 0xFF142238, 0xFF395776, 1.3)
    Outline(g, 2, 2, w - 4, h - 4, 10, 0x3656BFF9, 1)
    Outline(g, 3.5, 3.5, w - 7, h - 7, 9, 0x1949BAF0, 1)
    for i, label in labels {
        rowY := 6 + (i - 1) * 34
        if i = selected {
            GradientRounded(g, 6, rowY, w - 12, 31, 8, 0xFF2D516F, 0xFF213C59, 0xFF3679A2, 1)
            Outline(g, 7.5, rowY + 1.5, w - 15, 28, 7, 0x3535C8F9, 1)
        } else
            Rounded(g, 6, rowY, w - 12, 31, 8, 0x111D2B40)
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
    if x < 6 || x > 158 || y < 6
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
        RoundWindow(app.Hwnd, 18, 432, 332)
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
    RoundWindow(app.Hwnd, 18, 432, 332)
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

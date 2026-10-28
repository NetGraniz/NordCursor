#Requires AutoHotkey v2.0
#SingleInstance Force

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
global dropdownGui := 0

global app := Gui("-Caption -Resize", "NordCursor")
app.BackColor := "17191E"
app.MarginX := 0
app.MarginY := 0

A_IconTip := "NordCursor"
A_TrayMenu.Delete()
A_TrayMenu.Add("Open NordCursor", ShowApp)
A_TrayMenu.Add("Pause / Resume", Toggle)
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", ExitApplication)
A_TrayMenu.Default := "Open NordCursor"
A_TrayMenu.ClickCount := 1

global logoTile := AddLabel(app, "x20 y20 w40 h40 Center Background252A33", "◎", "s16 c7DA2F8 w600")
AddLabel(app, "x72 y21 w170 h32", "NordCursor", "s13 cF2F4F7 w600")
global minimizeButton := AddLabel(app, "x342 y20 w32 h30 Center", "–", "s12 c8B93A1")
global closeButton := AddLabel(app, "x382 y20 w30 h30 Center", "×", "s12 c8B93A1")
minimizeButton.OnEvent("Click", MinimizeApp)
closeButton.OnEvent("Click", CloseApp)

AddLabel(app, "x20 y91 w270 h32", "Start after inactivity", "s10 cD7DCE5 w600")
global idleValue := app.AddText("x302 y90 w110 h32 Background262B33")
global idleText := AddLabel(app, "x310 y90 w94 h32 Center BackgroundTrans", "30 sec  ▾", "s9 cF2F4F7")
idleValue.OnEvent("Click", ShowIdleMenu)
idleText.OnEvent("Click", ShowIdleMenu)

AddLabel(app, "x20 y136 w270 h32", "Movement radius", "s10 cD7DCE5 w600")
global radiusValue := app.AddText("x302 y135 w110 h32 Background262B33")
global radiusText := AddLabel(app, "x310 y135 w94 h32 Center BackgroundTrans", "5 px  ▾", "s9 cF2F4F7")
radiusValue.OnEvent("Click", ShowRadiusMenu)
radiusText.OnEvent("Click", ShowRadiusMenu)

AddLabel(app, "x20 y181 w270 h32", "Speed", "s10 cD7DCE5 w600")
global speedValue := app.AddText("x302 y180 w110 h32 Background262B33")
global speedText := AddLabel(app, "x310 y180 w94 h32 Center BackgroundTrans", "Smooth  ▾", "s9 cF2F4F7")
speedValue.OnEvent("Click", ShowSpeedMenu)
speedText.OnEvent("Click", ShowSpeedMenu)

global statusCard := app.AddText("x20 y230 w392 h82 Background20242B")
global statusIcon := AddLabel(app, "x35 y247 w24 h24 Center Background20242B", "✓", "s10 c62C98D w600")
global statusTitle := AddLabel(app, "x67 y244 w320 h28 Background20242B", "Waiting for inactivity", "s10 cE5E9F0 w600")
global statusHint := AddLabel(app, "x35 y279 w340 h22 Background20242B", "Movement will start automatically", "s8 c8B93A1")

app.OnEvent("Close", CloseApp)
app.OnEvent("Size", HandleSize)
OnMessage(0x0201, BeginDrag)
OnMessage(0x0006, HandleActivate)
OnExit CleanUp

SetExecutionState(true)
SetTimer CheckIdle, 40
app.Show("w432 h332")
ApplyWindowVisuals()

AddLabel(gui, options, text, fontOptions) {
    gui.SetFont(fontOptions, "Segoe UI")
    return gui.AddText(options " +0x200", text)
}

ApplyRounding() {
    global logoTile, idleValue, radiusValue, speedValue, statusCard
    RoundControl(logoTile, 10)
    RoundControl(idleValue, 10)
    RoundControl(radiusValue, 10)
    RoundControl(speedValue, 10)
    RoundControl(statusCard, 10)
}

RoundControl(control, radius) {
    control.GetPos(, , &width, &height)
    WinSetRegion("0-0 W" width " H" height " R" (radius * 2) "-" (radius * 2), "ahk_id " control.Hwnd)
}

RoundWindow(hwnd, radius) {
    rect := Buffer(16, 0)
    if !DllCall("User32\GetWindowRect", "Ptr", hwnd, "Ptr", rect)
        return
    width := NumGet(rect, 8, "Int") - NumGet(rect, 0, "Int")
    height := NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int")
    dpi := DllCall("User32\GetDpiForWindow", "Ptr", hwnd, "UInt")
    radius := Round(radius * (dpi ? dpi : 96) / 96)
    region := DllCall("CreateRoundRectRgn", "Int", 0, "Int", 0, "Int", width + 1, "Int", height + 1, "Int", radius * 2, "Int", radius * 2, "Ptr")
    DllCall("SetWindowRgn", "Ptr", hwnd, "Ptr", region, "Int", true)
}

ApplyWindowVisuals(*) {
    global app
    RoundWindow(app.Hwnd, 14)
    ApplyRounding()
    SetDarkWindow(app.Hwnd)
}

HandleSize(guiObj, minMax, width, height) {
    if minMax != -1
        ApplyWindowVisuals()
}

HandleActivate(wParam, lParam, msg, hwnd) {
    global app
    if hwnd = app.Hwnd && (wParam & 0xFFFF)
        ApplyWindowVisuals()
}

SetDarkWindow(hwnd) {
    dark := 1
    DllCall("Dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 20, "Int*", dark, "UInt", 4)
    corner := 3
    DllCall("Dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 33, "Int*", corner, "UInt", 4)
    borderColor := 0xFFFFFFFE
    DllCall("Dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 34, "UInt*", borderColor, "UInt", 4)
}

BeginDrag(wParam, lParam, msg, hwnd) {
    global app
    root := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
    if root != app.Hwnd
        return
    MouseGetPos &mouseX, &mouseY
    WinGetPos &windowX, &windowY,,, "ahk_id " app.Hwnd
    if mouseY - windowY < 70 {
        CloseDropdown()
        PostMessage 0x00A1, 2,,, "ahk_id " app.Hwnd
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
    ApplyWindowVisuals()
    WinActivate "ahk_id " app.Hwnd
}

ExitApplication(*) {
    ExitApp()
}

ShowIdleMenu(*) {
    global idleValue, idleLabels, idleIndex
    ShowDropdown(idleValue, idleLabels, "idle", idleIndex, 110)
}

ShowRadiusMenu(*) {
    global radiusValue, radiusLabels, radiusIndex
    ShowDropdown(radiusValue, radiusLabels, "radius", radiusIndex, 110)
}

ShowSpeedMenu(*) {
    global speedValue, speedLabels, speedIndex
    ShowDropdown(speedValue, speedLabels, "speed", speedIndex, 110)
}

ShowDropdown(anchor, labels, kind, selectedIndex, menuWidth) {
    global app, dropdownGui
    CloseDropdown()
    anchor.GetPos(&controlX, &controlY, &controlW, &controlH)
    WinGetPos(&windowX, &windowY,,, "ahk_id " app.Hwnd)
    menuHeight := labels.Length * 31 + 8
    dropdownGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner" app.Hwnd, "")
    dropdownGui.BackColor := "1F232A"
    dropdownGui.MarginX := 4
    dropdownGui.MarginY := 4
    for index, label in labels {
        color := index = selectedIndex ? "343B48" : "252A33"
        option := AddLabel(dropdownGui, "x4 y" (4 + (index - 1) * 31) " w" (menuWidth - 8) " h27 Center Background" color, label, "s9 cF2F4F7")
        option.OnEvent("Click", SelectDropdown.Bind(kind, index))
    }
    menuX := windowX + controlX + controlW - menuWidth
    menuY := windowY + controlY + controlH + 4
    dropdownGui.Show("NA x" menuX " y" menuY " w" menuWidth " h" menuHeight)
    RoundWindow(dropdownGui.Hwnd, 10)
    SetDarkWindow(dropdownGui.Hwnd)
    for control in dropdownGui
        RoundControl(control, 6)
}

SelectDropdown(kind, index, *) {
    global idleIndex, idleValues, idleLabels, idleDelay, idleText
    global radiusIndex, radiusValues, radiusLabels, radius, radiusText
    global speedIndex, speedLabels, speedText, enabledAt, lastPhysicalInput
    if kind = "idle" {
        idleIndex := index
        idleDelay := idleValues[index]
        idleText.Text := idleLabels[index] "  ▾"
        enabledAt := A_TickCount
        lastPhysicalInput := A_TickCount
        StopMoving()
    } else if kind = "radius" {
        radiusIndex := index
        radius := radiusValues[index]
        radiusText.Text := radiusLabels[index] "  ▾"
        lastPhysicalInput := A_TickCount
        StopMoving()
    } else {
        speedIndex := index
        speedText.Text := speedLabels[index] "  ▾"
    }
    CloseDropdown()
}

CloseDropdown(*) {
    global dropdownGui
    if IsObject(dropdownGui) {
        try dropdownGui.Destroy()
        dropdownGui := 0
    }
}

Toggle(*) {
    global isEnabled, enabledAt
    CloseDropdown()
    isEnabled := !isEnabled
    StopMoving()
    if isEnabled {
        enabledAt := A_TickCount
        SetExecutionState(true)
        SetStatus("Waiting for inactivity", "Movement will start automatically", "43DE83")
    } else {
        SetExecutionState(false)
        SetStatus("Paused", "Use the tray menu to resume", "C6A7B4")
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
        SetStatus("Moving cursor", "Activity keeps the computer awake", "38BDF8")
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
            SetStatus("Waiting for inactivity", "Movement will start automatically", "43DE83")
    }
}

SetStatus(title, hint, color) {
    global statusTitle, statusHint, statusIcon
    statusTitle.Text := title
    statusHint.Text := hint
    statusTitle.SetFont("c" color)
    statusIcon.SetFont("c" color)
}

SetExecutionState(enable) {
    flags := enable ? 0x80000003 : 0x80000000
    DllCall("Kernel32\SetThreadExecutionState", "UInt", flags, "UInt")
}

CleanUp(*) {
    CloseDropdown()
    SetExecutionState(false)
}

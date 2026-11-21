#Requires AutoHotkey v2.0
#SingleInstance Force
; =====================================================================================
;  Hyper-Bot PC v1.0  -  a friendly, clearly-disclosed hangout bot for Roblox (Windows)
;
;  Input-only: it presses keys, moves the mouse and reads the screen, like a player.
;  No injection, no memory reading, no modified client, no internet.
;  Rules built in: announces it's a bot, chat rate limits, follow limits + cooldowns,
;  pauses whenever the Roblox window isn't the active window.
;  Use it on an ALT account only, and never while your main account is playing.
; =====================================================================================

#Include %A_LineFile%\..\lib\Brain.ahk
#Include %A_LineFile%\..\lib\OCR.ahk

Persistent
SetWorkingDir A_ScriptDir
CoordMode "Mouse", "Screen"
CoordMode "Pixel", "Screen"
SendMode "Event"
SetKeyDelay 25, 30

global VERSION := "1.0.0"
global RBX := "ahk_exe RobloxPlayerBeta.exe"
global CFG_FILE := A_ScriptDir "\settings.ini"
global MOVES_DIR := A_ScriptDir "\moves"
global SELFTEST := A_Args.Length && A_Args[1] = "--selftest"

if SELFTEST
    OnError(SelfTestError)

SelfTestError(e, mode) {
    FileAppend("SELFTEST ERROR: " e.Message " (" e.What ") line " e.Line "`n", "*")
    ExitApp 1
}

; ------------------------------------------------------------------ settings

global DEFAULTS := Map(
    "intro", "Hyper-Bot online - I'm a bot! Say hi :)",
    "lines", "hey!|beep boop|nice outfit!|hello humans o/|I'm a friendly bot|wave if you see me!|*happy bot noises*|having a great day here",
    "replies", "hi {name} beep boop|hello {name} nice to meet you|hey {name} im a friendly bot|beep boop hi {name}|{name} hello there|hi {name} i like your avatar",
    "customQa", "who is your owner => my owner is a cool person who builds bots|what is hyper macro => a macro my owner made, im its little bot brother",
    "chatInterval", "45", "chatOn", "1", "emotesOn", "1", "botName", "", "smartOn", "1", "commandsOn", "1",
    "waveOnReply", "1", "movesInAuto", "1", "mood", "normal", "enabledMoods", "chill,happy,sleepy,party,curious,silly",
    "moodLines", "1", "moodRotate", "0", "lookAround", "1", "shiftLock", "0", "camKeys", "arrows",
    "stuckOn", "1", "faceTalker", "1", "followName", "", "followSec", "60",
    "chatX1", "0.00", "chatY1", "0.04", "chatX2", "0.32", "chatY2", "0.38", "ocrScale", "2"
)
global C := Map()

LoadCfg() {
    for k, v in DEFAULTS
        C[k] := IniRead(CFG_FILE, "bot", k, v)
    C["shiftLock"] := "0" ; the game always starts with shift lock off
}

SaveCfg() {
    for k, v in C
        IniWrite(v, CFG_FILE, "bot", k)
}

On(k) => C.Has(k) && C[k] = "1"
Num(k) => Number(C[k])
ListOf(k) {
    out := []
    for ln in StrSplit(C[k], "|") {
        ln := Trim(ln)
        if ln != ""
            out.Push(ln)
    }
    return out
}
SafeIntro() => InStr(C["intro"], "bot") ? Trim(C["intro"]) : DEFAULTS["intro"]
CustomQa() {
    out := []
    for ln in ListOf("customQa")
        if (i := InStr(ln, "=>")) > 1 && Trim(SubStr(ln, 1, i - 1)) != "" && Trim(SubStr(ln, i + 2)) != ""
            out.Push([Trim(SubStr(ln, 1, i - 1)), Trim(SubStr(ln, i + 2))])
    return out
}
EnabledMoods() {
    out := [MOODS[1]]
    en := "," C["enabledMoods"] ","
    for m in MOODS
        if m.id != "normal" && InStr(en, "," m.id ",")
            out.Push(m)
    return out
}
CurMood() {
    for m in EnabledMoods()
        if m.id = C["mood"]
            return m
    return MOODS[1]
}

; ------------------------------------------------------------------ state

global S := {auto: false, listening: false, busyUntil: 0, lastChat: 0, lastIntro: -9999999, lastEmote: -9999999,
    lastOwnChat: -9999999, queue: [], visionCount: 0, testPending: false, moodSince: 0,
    followTarget: "", ownerFollow: false, followUntil: 0, followLost: 0, pendingNearest: false,
    faceTarget: "", faceUntil: 0, lastWalkAt: -9999999, prevThumb: "", stuckCount: 0, stuckEscapes: 0,
    recording: false, recStart: 0, recEvents: [], recState: Map(), recentNames: [], lastRead: [],
    flyOn: false, flyPid: 0, flySound: 0, flyPraise: 0, flyInsult: 0, flyWater: 0, flyTouch: 0, flyWind: 0,
    flyPrev: "", flyLast: Map(), flyLastWord: -9999999, flyLastGroomChat: -9999999, flyStarted: 0}
global HELD := Map()
global brain := ChatBrain()
global smart := SmartBrain()
global guard := FollowGuard(A_ScriptDir "\follow_log.ini")
global G := {} ; GUI controls

LoadCfg()
DirCreate(MOVES_DIR)
BuildGui()

if SELFTEST {
    r := smart.Reply("Tester", "bot are you a bot", "normal", CustomQa())
    FileAppend("SELFTEST reply: " r.text "`n", "*")
    FileAppend("SELFTEST moods=" EnabledMoods().Length " moves=" ListMoves().Length "`n", "*")
    try FileAppend("SELFTEST ocr languages: " OCR.GetAvailableLanguages() "`n", "*")
    FileAppend("SELFTEST OK`n", "*")
    ExitApp 0
}

SetTimer(VisionTick, 500)
SetTimer(Pump, 400)
SetTimer(FocusGuard, 250)
Status("Ready. Open Roblox on your ALT account, then press F8 (Auto) or F9 (Listen).")

; ------------------------------------------------------------------ hotkeys

F6:: ToggleWindow()
F8:: ToggleAuto()
F9:: ToggleListen()
F10:: StopAll()
F11:: ToggleRecord()
^F8:: FollowNearest()
^F10:: StopFollow(true)

ToggleWindow() {
    if WinActive("ahk_id " G.win.Hwnd)
        G.win.Hide()
    else
        G.win.Show()
}

; ------------------------------------------------------------------ Roblox window + safe input

RbxActive() => WinActive(RBX)

RbxRect(&x, &y, &w, &h) {
    x := y := w := h := 0
    if !WinExist(RBX)
        return false
    try WinGetClientPos(&x, &y, &w, &h, RBX)
    catch
        return false
    return w > 200 && h > 200
}

FocusRbx() {
    if !WinExist(RBX)
        return false
    if !WinActive(RBX) {
        WinActivate(RBX)
        WinWaitActive(RBX, , 1)
    }
    return WinActive(RBX)
}

; every key the bot presses goes through here, and only reaches Roblox
KeyDown(k) {
    if !RbxActive()
        return false
    Send "{" k " down}"
    HELD[k] := 1
    return true
}

KeyUp(k) {
    Send "{" k " up}"
    if HELD.Has(k)
        HELD.Delete(k)
}

Hold(k, ms) {
    if !KeyDown(k)
        return false
    SetTimer(KeyUp.Bind(k), -Max(30, Round(ms)))
    return true
}

ReleaseAll() {
    ks := []
    for k in HELD
        ks.Push(k)
    for k in ks
        KeyUp(k)
}

; if you click away from Roblox, everything held is released at once
FocusGuard() {
    if HELD.Count && !RbxActive()
        ReleaseAll()
}

Jump() {
    S.flyWind += 1
    return Hold("Space", 90)
}

CamTurn(dir, ms) {
    if C["camKeys"] = "mouse" {
        if !RbxActive()
            return
        if !On("shiftLock")
            Send "{RButton down}"
        loop Max(1, ms // 15) {
            DllCall("mouse_event", "UInt", 1, "Int", dir * 14, "Int", 0, "UInt", 0, "UPtr", 0)
            Sleep 15
        }
        if !On("shiftLock")
            Send "{RButton up}"
    } else
        Hold(dir < 0 ? "Left" : "Right", ms)
}

WalkRandom() {
    m := CurMood()
    ms := Round(Random(800, 2200) * (0.5 + m.stick / 2))
    keys := ["w"], r := Random(1, 10)
    if r <= 2
        keys.Push("a")
    else if r <= 4
        keys.Push("d")
    if On("shiftLock") && Random(1, 4) = 1 ; shift-lock strafe
        keys := [RandItem(["a", "d"])]
    for k in keys
        Hold(k, ms)
    if Random(0, 1)
        SetTimer(CamTurn.Bind(Random(0, 1) ? -1 : 1, Random(120, 450)), -Random(100, ms // 2))
    if Random(1, 6) = 1
        SetTimer(Jump, -Random(200, Max(250, ms - 100)))
    S.busyUntil := NowMs() + ms + 150
    S.lastWalkAt := NowMs()
}

LookAround() {
    if NowMs() < S.busyUntil || !RbxActive()
        return
    dir := Random(0, 1) ? 1 : -1, ms := Random(250, 700)
    CamTurn(dir, ms)
    if Random(0, 2)
        SetTimer(CamTurn.Bind(-dir, Random(100, ms)), -Random(400, 1100))
    S.busyUntil := NowMs() + ms + 900
}

ToggleShiftLock() {
    if !FocusRbx()
        return Status("Shift Lock: Roblox isn't open")
    Send "{LShift}"
    C["shiftLock"] := On("shiftLock") ? "0" : "1"
    G.shift.Text := "Shift Lock: " (On("shiftLock") ? "ON" : "OFF")
    Status("Shift Lock " (On("shiftLock") ? "ON" : "OFF") " (needs 'Shift Lock Switch' on in Roblox settings)")
}

; ------------------------------------------------------------------ chat

SendChat(text, test := false) {
    if !FocusRbx() {
        Status("Chat: Roblox isn't the active window")
        return false
    }
    ReleaseAll()
    Send "{/}"
    Sleep 180
    SendText(text)
    Sleep 90
    Send "{Enter}"
    S.lastOwnChat := NowMs()
    brain.NoteOwn(text)
    S.busyUntil := Max(S.busyUntil, NowMs() + 500)
    Status((test ? "Chat test sent: " : "Said: ") text)
    if test
        SetTimer(CheckChatTest.Bind(text), -1800)
    return true
}

CheckChatTest(text) {
    for l in OcrChatLines()
        if InStr(l, "chat test")
            return Status("Chat test OK: the message showed up in the chat area")
    Status("Chat test: sent, but I couldn't read it back. Check the chat area calibration (Calibrate chat area).")
}

QueueChat(text) => S.queue.Push(text)

Pump() {
    if S.queue.Length && NowMs() >= S.busyUntil && RbxActive()
        SendChat(S.queue.RemoveAt(1))
}

SayRandomLine(force := false) {
    now := NowMs(), m := CurMood()
    if !force && now - S.lastChat < Num("chatInterval") * 1000 * m.chatScale
        return
    if force && now - S.lastChat < 5000
        return Status("Wait a few seconds between messages")
    lines := (On("moodLines") && m.lines.Length && (!ListOf("lines").Length || Random(0, 1))) ? m.lines : ListOf("lines")
    if !lines.Length
        return
    S.lastChat := now
    SendChat(RandItem(lines))
}

EmoteRandom(force := false) {
    now := NowMs()
    if !force && now - S.lastEmote < 60000
        return
    S.lastEmote := now
    em := CurMood().emotes
    SendChat("/e " RandItem(em.Length ? em : MOODS[1].emotes))
}

MoodReplies() {
    m := CurMood(), mine := ListOf("replies")
    return (On("moodLines") && m.replies.Length && (!mine.Length || Random(0, 1))) ? m.replies : mine
}

SmartSay(name, msg) {
    r := smart.Reply(name, msg, CurMood().id, CustomQa())
    text := r.text
    if r.topic = "greet" && Random(0, 2) = 0 {
        rl := MoodReplies()
        if rl.Length
            text := ChatBrain.Fill(RandItem(rl), name)
    }
    e := r.emote != "" ? r.emote : (r.topic = "greet" && On("waveOnReply") ? "wave" : "")
    if e != "" && On("emotesOn")
        QueueChat("/e " e)
    QueueChat(text)
}

; ------------------------------------------------------------------ vision: OCR + thumbnails

OcrRect(x, y, w, h, scale := 1) {
    if w < 40 || h < 40
        return ""
    try return OCR.FromRect(Round(x), Round(y), Round(w), Round(h), {scale: scale, grayscale: 1})
    catch as e {
        Status("OCR error: " e.Message " (Windows OCR needs an installed language, e.g. English)")
        return ""
    }
}

OcrChatLines() {
    if !RbxRect(&x, &y, &w, &h)
        return []
    x1 := x + w * Min(Num("chatX1"), Num("chatX2")), x2 := x + w * Max(Num("chatX1"), Num("chatX2"))
    y1 := y + h * Min(Num("chatY1"), Num("chatY2")), y2 := y + h * Max(Num("chatY1"), Num("chatY2"))
    res := OcrRect(x1, y1, x2 - x1, y2 - y1, Num("ocrScale"))
    out := []
    if res = ""
        return out
    for ln in res.Lines {
        t := Trim(ln.Text)
        if t != ""
            out.Push(t)
    }
    return out
}

; name-tag candidates from the game view (not the chat, not the player list at the top right)
OcrTags(&wx, &wy, &ww, &wh) {
    if !RbxRect(&wx, &wy, &ww, &wh)
        return []
    top := wy + wh * 0.08, ht := wh * 0.77
    res := OcrRect(wx, top, ww, ht, 1)
    out := []
    if res = ""
        return out
    cx1 := Min(Num("chatX1"), Num("chatX2")), cx2 := Max(Num("chatX1"), Num("chatX2"))
    cy1 := Min(Num("chatY1"), Num("chatY2")), cy2 := Max(Num("chatY1"), Num("chatY2"))
    for ln in res.Lines {
        fx := (ln.x + ln.w / 2 - wx) / ww, fy := (ln.y + ln.h / 2 - wy) / wh
        if (fx >= cx1 && fx <= cx2 && fy >= cy1 && fy <= cy2) || (fx > 0.78 && fy < 0.5)
            continue
        out.Push({text: Trim(ln.Text), cx: ln.x + ln.w / 2, cy: ln.y + ln.h / 2, h: ln.h, fx: fx})
    }
    return out
}

NormName(s) => RegExReplace(StrLower(s), "[^a-z0-9]")

Similar(a, b) {
    if a = "" || b = ""
        return false
    if StrLen(a) < 3 || StrLen(b) < 3
        return a == b
    if a == b || InStr(a, b, true) || InStr(b, a, true)
        return true
    return 1 - SmartBrain.Lev(a, b) / Max(StrLen(a), StrLen(b)) >= 0.75
}

; 32x18 greyscale thumbnail of the Roblox window (centre masked: our own character moves there)
Thumb() {
    if !RbxRect(&x, &y, &w, &h)
        return ""
    TW := 32, TH := 18
    hdc := DllCall("GetDC", "ptr", 0, "ptr")
    mdc := DllCall("CreateCompatibleDC", "ptr", hdc, "ptr")
    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0), NumPut("int", TW, bi, 4), NumPut("int", -TH, bi, 8)
    NumPut("ushort", 1, bi, 12), NumPut("ushort", 32, bi, 14)
    bits := 0
    hbm := DllCall("CreateDIBSection", "ptr", mdc, "ptr", bi, "uint", 0, "ptr*", &bits, "ptr", 0, "uint", 0, "ptr")
    obm := DllCall("SelectObject", "ptr", mdc, "ptr", hbm, "ptr")
    DllCall("SetStretchBltMode", "ptr", mdc, "int", 4)
    DllCall("StretchBlt", "ptr", mdc, "int", 0, "int", 0, "int", TW, "int", TH, "ptr", hdc, "int", x, "int", y, "int", w, "int", h, "uint", 0x00CC0020)
    out := []
    loop TH {
        ry := A_Index - 1
        loop TW {
            rx := A_Index - 1
            if rx >= 11 && rx <= 20 && ry >= 4 && ry <= 15
                continue
            px := NumGet(bits, (ry * TW + rx) * 4, "uint")
            out.Push((((px >> 16) & 255) * 3 + ((px >> 8) & 255) * 6 + (px & 255)) // 10)
        }
    }
    DllCall("SelectObject", "ptr", mdc, "ptr", obm)
    DllCall("DeleteObject", "ptr", hbm)
    DllCall("DeleteDC", "ptr", mdc)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
    return out
}

; walking but the view didn't change twice in a row -> stuck: back up, jump, turn around
CheckStuck() {
    t := Thumb()
    prev := S.prevThumb
    S.prevThumb := t
    if t = "" || prev = "" || prev.Length != t.Length
        return
    if NowMs() - S.lastWalkAt > 1200 {
        S.stuckCount := 0
        return
    }
    d := 0
    loop t.Length
        d += Abs(t[A_Index] - prev[A_Index])
    S.stuckCount := d / t.Length < 2.5 ? S.stuckCount + 1 : 0
    if S.stuckCount >= 2 && S.flyOn {
        S.stuckCount := 0, S.flyTouch += 1 ; the fly feels the wall - its own brain decides what to do
        return
    }
    if S.stuckCount >= 2 {
        S.stuckCount := 0, S.stuckEscapes += 1
        ReleaseAll()
        Hold("s", 600)
        SetTimer(Jump, -250)
        SetTimer(CamTurn.Bind(Random(0, 1) ? 1 : -1, Random(600, 1000)), -650)
        S.busyUntil := NowMs() + 1800
        Status("Stuck - turning around (" S.stuckEscapes " so far)")
    }
}

VisionTick() {
    if !RbxActive()
        return
    S.visionCount += 1
    now := NowMs()
    if (On("stuckOn") || S.flyOn) && (S.auto || S.followTarget != "") && !S.recording
        CheckStuck()
    if S.pendingNearest
        return SeekNearest()
    if S.followTarget != "" || S.faceTarget != ""
        SeekTags()
    if S.testPending || (S.listening && Mod(S.visionCount, 2) = 0 && !S.recording) {
        test := S.testPending
        S.testPending := false
        lines := OcrChatLines()
        S.lastRead := lines
        HandleChat(lines, test)
    }
}

; ------------------------------------------------------------------ listening

ToggleListen() {
    if S.listening
        StopListening()
    else
        StartListening()
}

StartListening() {
    S.listening := true
    brain.Reset()
    G.listen.Text := "Listen: ON (F9)"
    if On("chatOn") && NowMs() - S.lastIntro > 600000 {
        S.lastIntro := NowMs()
        QueueChat(SafeIntro())
    }
    Status("Listening to chat")
}

StopListening() {
    S.listening := false
    S.queue := []
    smart.Clear()
    G.listen.Text := "Listen: OFF (F9)"
    Status("Listen OFF")
}

ListenTest() {
    if !FocusRbx()
        return Status("Listen test: Roblox isn't open")
    lines := OcrChatLines()
    txt := "Listen test: read " lines.Length " line(s) from the chat area`r`n"
    for l in lines {
        cl := ChatBrain.Parse(l)
        txt .= (cl != "" ? "- " cl.name ": " cl.message : "- (no name) " l) "`r`n"
    }
    if !lines.Length
        txt .= "(nothing read - is the chat open? Use 'Calibrate chat area' around the messages.)"
    G.log.Value := txt
}

HandleChat(lines, test) {
    if test
        return ListenTestShow(lines)
    now := NowMs()
    for l in brain.NewLines(lines) {
        cl := ChatBrain.Parse(l)
        if cl = ""
            continue
        NoteName(cl.name)
        if S.flyOn && !brain.Ignored(cl, C["botName"]) {
            FlyHears(cl.message)
            cmd := On("commandsOn") ? brain.Command(cl, C["botName"], now) : ""
            if cmd != "" && (cmd.name = "stop" || cmd.name = "help" || cmd.name = "commands")
                RunCommand(cmd, now)
            continue
        }
        ft := S.followTarget
        if ft != "" && Similar(NormName(cl.name), NormName(ft)) && WantsNoFollow(cl.message) {
            if S.ownerFollow
                guard.Block(ft)
            StopFollow()
            QueueChat(ChatBrain.Fill("ok sorry {name}! i'll stop", cl.name))
            break
        }
        msgl := StrLower(Trim(cl.message))
        if On("smartOn") && smart.InGame(cl.name, now) && StrSplit(Trim(cl.message), " ").Length <= 3
            && !brain.Ignored(cl, C["botName"]) && SubStr(msgl, 1, 3) != "bot" {
            if brain.AllowTalk(cl.name, now)
                SmartSay(cl.name, cl.message)
            break
        }
        if On("commandsOn") {
            cmd := brain.Command(cl, C["botName"], now)
            if cmd != "" {
                RunCommand(cmd, now)
                break
            }
        }
        if !brain.ShouldReply(cl, C["botName"], S.lastOwnChat, now)
            continue
        FaceToward(cl.name)
        if On("smartOn") {
            SmartSay(cl.name, cl.message)
            break
        }
        rl := MoodReplies()
        if !rl.Length
            break
        if On("waveOnReply")
            QueueChat("/e wave")
        QueueChat(ChatBrain.Fill(RandItem(rl), cl.name))
        break
    }
}

ListenTestShow(lines) {
    txt := "Listen test: read " lines.Length " line(s)`r`n"
    for l in lines
        txt .= "- " l "`r`n"
    G.log.Value := txt
}

WantsNoFollow(msg) {
    m := " " RegExReplace(StrLower(msg), "[^a-z ]", " ") " "
    for p in [" stop ", " go away ", " leave ", " stop following", " dont follow", " don t follow", " creepy ", " stalker", " stalking", " get away ", " back off", " no ", " quit ", " stahp"]
        if InStr(m, p)
            return true
    return false
}

NoteName(n) {
    if n = "" || (C["botName"] != "" && Similar(NormName(n), NormName(C["botName"])))
        return
    rn := S.recentNames
    loop rn.Length {
        if rn[A_Index] = n {
            rn.RemoveAt(A_Index)
            break
        }
    }
    rn.InsertAt(1, n)
    while rn.Length > 5
        rn.Pop()
    RefreshFollowNames()
}

RunCommand(cmd, now) {
    switch cmd.name {
        case "help", "commands":
            QueueChat("bot commands: wave dance jump walk follow stop mood games joke - or just ask me stuff")
        case "follow", "come":
            if S.followTarget = "" {
                StartFollow(cmd.from, false)
                QueueChat("/e point")
            }
        case "stop":
            ft := S.followTarget
            if ft != "" && S.ownerFollow && Similar(NormName(cmd.from), NormName(ft))
                guard.Block(ft)
            StopFollow()
        case "mood":
            if brain.AllowTalk(cmd.from, now)
                QueueChat("bot mood: " StrLower(CurMood().label))
        case "hi", "hello", "hey":
            FaceToward(cmd.from)
            if On("smartOn") {
                if brain.AllowTalk(cmd.from, now)
                    SmartSay(cmd.from, "hi")
            } else
                QueueChat("/e wave")
        case "wave", "cheer", "laugh", "point":
            if cmd.name = "wave"
                FaceToward(cmd.from)
            QueueChat("/e " cmd.name)
        case "dance":
            QueueChat("/e " RandItem(["dance", "dance2", "dance3"]))
        case "jump":
            n := Random(1, 3)
            loop n
                SetTimer(Jump.Bind(), -(A_Index * 650))
        case "walk":
            WhenFree(WalkRandom)
        default:
            want := Trim(RegExReplace(cmd.arg, "^move\b"))
            mv := FindMove(want)
            if mv != ""
                WhenFree(PlayMove.Bind(mv))
            else if On("smartOn") && brain.AllowTalk(cmd.from, now)
                SmartSay(cmd.from, cmd.arg)
    }
}

WhenFree(fn) => SetTimer(fn, -(Max(0, S.busyUntil - NowMs()) + 60))

; ------------------------------------------------------------------ follow / face

StartFollow(name, owner) {
    S.followTarget := name, S.ownerFollow := owner, S.followLost := 0
    S.followUntil := NowMs() + Num("followSec") * 1000
    G.followState.Text := "Following: " name
}

StartOwnerFollow(name) {
    name := Trim(name)
    if name = ""
        return Status("Follow: type or pick a name first")
    if S.followTarget != ""
        StopFollow()
    why := guard.Check(name)
    if why != ""
        return Status("Can't follow - " why)
    if !FocusRbx()
        return Status("Follow: Roblox isn't open")
    guard.NoteStart(name)
    StartFollow(name, true)
    if !S.listening
        StartListening() ; so they can always say "bot stop"
    QueueChat(ChatBrain.Fill("hi {name}, im a bot following you for a bit - say bot stop and ill stop", name))
    Status("Following " name " (max " C["followSec"] " s)")
}

StopFollow(manual := false) {
    S.followTarget := "", S.ownerFollow := false, S.pendingNearest := false
    KeyUp("w")
    G.followState.Text := "Not following"
    if manual
        Status("Stopped following")
}

FollowNearest() {
    if !FocusRbx()
        return Status("Follow: Roblox isn't open")
    StopFollow()
    S.pendingNearest := true
    Status("Looking for the nearest name tag...")
}

FaceToward(name) {
    if !On("faceTalker") || S.followTarget != ""
        return
    S.faceTarget := name, S.faceUntil := NowMs() + 4000
}

SeekNearest() {
    S.pendingNearest := false
    tags := OcrTags(&wx, &wy, &ww, &wh)
    me := NormName(C["botName"]), best := "", bestScore := -99
    for t in tags {
        if !RegExMatch(t.text, "^@?[A-Za-z0-9_]{3,20}( [A-Za-z0-9_]{1,20})?$")
            continue
        n := LTrim(t.text, "@")
        if (me != "" && Similar(NormName(n), me)) || guard.Check(n) != ""
            continue
        score := t.h / wh * 10 - Abs(t.fx - 0.5)
        if score > bestScore
            bestScore := score, best := n
    }
    if best = ""
        return Status("No name tag found (or everyone nearby is on cooldown)")
    StartOwnerFollow(best)
}

SeekTags() {
    now := NowMs()
    if S.followTarget != "" && now > S.followUntil {
        StopFollow()
        return Status("Done following")
    }
    if S.faceTarget != "" && now > S.faceUntil
        S.faceTarget := ""
    target := S.followTarget != "" ? S.followTarget : S.faceTarget
    if target = ""
        return
    want := NormName(target), hit := ""
    for t in OcrTags(&wx, &wy, &ww, &wh)
        if Similar(NormName(t.text), want) {
            hit := t
            break
        }
    if hit = "" {
        if S.followTarget != "" && (S.followLost += 1) >= 6 {
            StopFollow()
            Status("Lost " target)
        }
        return
    }
    S.followLost := 0
    dxf := (hit.cx - (wx + ww / 2)) / ww
    if Abs(dxf) > 0.05
        CamTurn(dxf < 0 ? -1 : 1, Min(350, Max(60, Abs(dxf) * 900)))
    if S.faceTarget != "" && S.followTarget = "" {
        S.faceTarget := ""
        if !On("shiftLock")
            Hold("w", 110) ; one tiny step so the avatar faces them
        return
    }
    if hit.h < wh * 0.035 { ; not close yet: keep walking
        Hold("w", 650)
        S.lastWalkAt := NowMs()
        S.busyUntil := Max(S.busyUntil, NowMs() + 600)
    }
}

; ------------------------------------------------------------------ auto

ToggleAuto() {
    if S.auto
        StopAuto()
    else
        StartAuto()
}

StartAuto() {
    if !WinExist(RBX)
        return Status("Auto: open Roblox first")
    FocusRbx()
    S.auto := true, S.lastIntro := -9999999, S.moodSince := NowMs()
    G.auto.Text := "Auto: ON (F8)"
    SetTimer(AutoTick, -500)
    Status("Auto ON - mood: " CurMood().label)
}

StopAuto() {
    if S.flyOn
        FlyStop()
    S.auto := false
    SetTimer(AutoTick, 0)
    ReleaseAll()
    G.auto.Text := "Auto: OFF (F8)"
}

StopAll() {
    StopAuto()
    StopFollow()
    if S.listening
        StopListening()
    if S.recording
        ToggleRecord()
    S.queue := []
    ReleaseAll()
    Status("STOPPED (F10)")
}

AutoTick() {
    if !S.auto
        return
    if RbxActive()
        AutoStep()
    m := CurMood()
    SetTimer(AutoTick, -Random(m.gapMin, m.gapMax))
}

AutoStep() {
    now := NowMs()
    if now < S.busyUntil || S.followTarget != "" || S.recording || S.queue.Length
        return
    ; always (re)announce that this is a bot: on start and every 10 minutes
    if On("chatOn") && now - S.lastIntro > 600000 {
        S.lastIntro := now, S.lastChat := now
        return SendChat(SafeIntro())
    }
    m := CurMood()
    if m.id = "fly" {
        if !S.flyOn
            FlyStart()
        return
    }
    if S.flyOn
        FlyStop()
    if On("chatOn") && now - S.lastChat > Num("chatInterval") * 1000 * m.chatScale
        return SayRandomLine()
    if On("moodRotate") && now - S.moodSince > 600000 {
        pool := []
        for x in EnabledMoods()
            if x.id != m.id
                pool.Push(x)
        S.moodSince := now
        if pool.Length
            SetMood(RandItem(pool).id)
        m := CurMood()
    }
    moves := On("movesInAuto") && m.move ? ListMoves() : []
    w := [["walk", m.walk], ["idle", m.idle], ["jump", m.jump], ["emote", On("emotesOn") ? m.emote : 0],
        ["move", moves.Length ? m.move : 0], ["look", On("lookAround") ? m.look : 0]]
    total := 0
    for p in w
        total += p[2]
    roll := total ? Random(0, total - 1) : 0, pick := "walk"
    for p in w {
        roll -= p[2]
        if roll < 0 {
            pick := p[1]
            break
        }
    }
    switch pick {
        case "walk": WalkRandom()
        case "idle": S.busyUntil := now + Random(2500, 6000)
        case "jump": Jump()
        case "emote": EmoteRandom()
        case "move": PlayMove(RandItem(moves))
        case "look": LookAround()
    }
}

SetMood(id) {
    C["mood"] := id
    S.moodSince := NowMs()
    IniWrite(id, CFG_FILE, "bot", "mood")
    try {
        names := []
        for m in EnabledMoods()
            names.Push(m.label)
        G.mood.Delete(), G.mood.Add(names), G.mood.Text := CurMood().label
    }
}

; ------------------------------------------------------------------ moves (record your own keyboard moves)

global REC_KEYS := ["w", "a", "s", "d", "Space", "Left", "Right", "LShift"]

ToggleRecord() {
    if S.recording {
        S.recording := false
        SetTimer(RecPoll, 0)
        if S.recEvents.Length < 2
            return Status("Recording cancelled (nothing recorded)")
        name := "move" (ListMoves().Length + 1)
        txt := ""
        for e in S.recEvents
            txt .= e[1] "," e[2] "," e[3] "`n"
        FileAppend(txt, MOVES_DIR "\" name ".txt", "UTF-8")
        RefreshMoves()
        return Status("Saved " name " (" S.recEvents.Length " key events). Rename it in the Moves tab.")
    }
    if !FocusRbx()
        return Status("Record: open Roblox first")
    StopAuto()
    S.recording := true, S.recStart := NowMs(), S.recEvents := [], S.recState := Map()
    SetTimer(RecPoll, 15)
    Status("RECORDING - play your move in Roblox (WASD, Space, arrows, Shift). Press F11 to stop.")
}

RecPoll() {
    t := NowMs() - S.recStart
    if t > 60000
        return ToggleRecord()
    if !RbxActive()
        return
    for k in REC_KEYS {
        down := GetKeyState(k, "P") ? 1 : 0
        was := S.recState.Has(k) ? S.recState[k] : 0
        if down != was {
            S.recState[k] := down
            S.recEvents.Push([t, k, down])
        }
    }
}

ListMoves() {
    out := []
    loop files MOVES_DIR "\*.txt"
        out.Push(SubStr(A_LoopFileName, 1, -4))
    return out
}

FindMove(want) {
    moves := ListMoves()
    if !moves.Length
        return ""
    if want = "" || want = "random"
        return RandItem(moves)
    for m in moves
        if m = want
            return m
    for m in moves
        if InStr(StrLower(m), StrLower(want))
            return m
    return ""
}

PlayMove(name) {
    if !FocusRbx()
        return
    f := MOVES_DIR "\" name ".txt"
    if !FileExist(f)
        return
    last := 0
    for line in StrSplit(FileRead(f, "UTF-8"), "`n", "`r") {
        p := StrSplit(line, ",")
        if p.Length < 3 || !IsInteger(p[1])
            continue
        t := Integer(p[1]), last := Max(last, t)
        SetTimer(MoveKey.Bind(p[2], p[3] = "1"), -Max(1, t))
    }
    SetTimer(ReleaseAll, -(last + 80))
    S.busyUntil := NowMs() + last + 200
    S.lastWalkAt := NowMs() + last
    Status("Playing move: " name)
}

MoveKey(k, down) {
    if down
        KeyDown(k)
    else
        KeyUp(k)
}

; ------------------------------------------------------------------ calibration

CalibrateChat() {
    if !FocusRbx() || !RbxRect(&x, &y, &w, &h)
        return Status("Calibrate: open Roblox first")
    ToolTip("Hyper-Bot: click the TOP-LEFT corner of the chat messages")
    KeyWait("LButton", "D")
    MouseGetPos(&x1, &y1)
    KeyWait("LButton")
    ToolTip("Hyper-Bot: now click the BOTTOM-RIGHT corner of the chat messages")
    KeyWait("LButton", "D")
    MouseGetPos(&x2, &y2)
    KeyWait("LButton")
    ToolTip()
    C["chatX1"] := Format("{:.3f}", (Min(x1, x2) - x) / w), C["chatY1"] := Format("{:.3f}", (Min(y1, y2) - y) / h)
    C["chatX2"] := Format("{:.3f}", (Max(x1, x2) - x) / w), C["chatY2"] := Format("{:.3f}", (Max(y1, y2) - y) / h)
    SaveCfg()
    Status("Chat area saved. Try 'Listen test'.")
}

; ------------------------------------------------------------------ GUI (Hyper-M: white + cyan)

Status(msg) {
    try G.status.Value := FormatTime(, "HH:mm:ss") "  " msg
}

BuildGui() {
    CYAN := "00A8E0"
    gw := Gui("+AlwaysOnTop +Resize -MaximizeBox", "Hyper-Bot PC " VERSION)
    gw.BackColor := "FFFFFF"
    gw.SetFont("s10", "Segoe UI")
    G.win := gw
    gw.SetFont("s16 bold c" CYAN)
    gw.AddText("x14 y8", "Hyper-Bot PC")
    gw.SetFont("s9 norm c808080")
    gw.AddText("x+10 yp+9", "v" VERSION "  -  a friendly bot (always says it's a bot)  -  alt accounts only")
    gw.SetFont("s10 norm c000000")
    tab := gw.AddTab3("x10 y44 w560 h500", ["Control", "Chat && Brain", "Moods && Camera", "Moves", "Fly Brain", "About"])

    ; --- Control
    tab.UseTab(1)
    G.auto := gw.AddButton("x24 y82 w170 h36", "Auto: OFF (F8)")
    G.auto.OnEvent("Click", (*) => ToggleAuto())
    G.listen := gw.AddButton("x+10 w170 h36", "Listen: OFF (F9)")
    G.listen.OnEvent("Click", (*) => ToggleListen())
    b := gw.AddButton("x+10 w170 h36", "STOP all (F10)")
    b.OnEvent("Click", (*) => StopAll())
    gw.AddText("x24 y+14", "Mood:")
    names := []
    for m in EnabledMoods()
        names.Push(m.label)
    G.mood := gw.AddDropDownList("x+8 yp-3 w140", names)
    G.mood.Text := CurMood().label
    G.mood.OnEvent("Change", MoodPicked)
    G.shift := gw.AddButton("x+12 yp-1 w150", "Shift Lock: OFF")
    G.shift.OnEvent("Click", (*) => ToggleShiftLock())
    b := gw.AddButton("x+10 w100", "Look around")
    b.OnEvent("Click", (*) => (FocusRbx() && (S.busyUntil := 0, LookAround())))
    b := gw.AddButton("x24 y+12 w100", "Jump")
    b.OnEvent("Click", (*) => (FocusRbx() && Jump()))
    b := gw.AddButton("x+8 w100", "Walk")
    b.OnEvent("Click", (*) => (FocusRbx() && WalkRandom()))
    b := gw.AddButton("x+8 w100", "Emote")
    b.OnEvent("Click", (*) => EmoteRandom(true))
    b := gw.AddButton("x+8 w100", "Say a line")
    b.OnEvent("Click", (*) => SayRandomLine(true))
    b := gw.AddButton("x+8 w100", "Say intro")
    b.OnEvent("Click", (*) => SendChat(SafeIntro()))
    b := gw.AddButton("x24 y+8 w160", "Chat test")
    b.OnEvent("Click", (*) => SendChat("Hyper-Bot chat test (I'm a bot)", true))
    b := gw.AddButton("x+8 w160", "Listen test")
    b.OnEvent("Click", (*) => ListenTest())
    b := gw.AddButton("x+8 w180", "Calibrate chat area")
    b.OnEvent("Click", (*) => CalibrateChat())

    gw.SetFont("s10 bold c" CYAN)
    gw.AddText("x24 y+16", "Follow")
    gw.SetFont("s10 norm c000000")
    b := gw.AddButton("x24 y+6 w150", "Nearest player (Ctrl+F8)")
    b.OnEvent("Click", (*) => FollowNearest())
    G.followPick := gw.AddComboBox("x+8 w160", [])
    b := gw.AddButton("x+8 w70", "Follow")
    b.OnEvent("Click", (*) => StartOwnerFollow(G.followPick.Text))
    b := gw.AddButton("x+8 w100", "Stop following")
    b.OnEvent("Click", (*) => StopFollow(true))
    G.followState := gw.AddText("x24 y+8 w520 c808080", "Not following")
    gw.SetFont("s8 c808080")
    gw.AddText("x24 y+2 w520", "Limits for follows you start: max " C["followSec"] " s, 10 min cooldown per player, 3 per player per day. "
        . "The bot tells them it's a bot following them; if they say stop it stops and won't follow them for an hour.")
    gw.SetFont("s10 norm c000000")
    G.status := gw.AddEdit("x24 y+10 w530 h22 ReadOnly -E0x200 BackgroundF2FBFF", "")
    G.log := gw.AddEdit("x24 y+6 w530 h88 ReadOnly", "Hotkeys: F6 show/hide  F8 Auto  F9 Listen  F10 STOP  F11 record move  Ctrl+F8 follow nearest  Ctrl+F10 stop following`r`n"
        . "The bot only acts while the Roblox window is active - click another window and it pauses.")

    ; --- Chat & Brain
    tab.UseTab(2)
    gw.AddText("x24 y82", "Intro (must contain `"bot`" - said on start and every 10 min):")
    G.intro := gw.AddEdit("x24 y+4 w530", C["intro"])
    gw.AddText("x24 y+8", "Random chat lines (one per line):")
    G.lines := gw.AddEdit("x24 y+4 w260 h70", JoinLines("lines"))
    gw.AddText("x300 yp-20", "Reply lines ({name} = player):")
    G.replies := gw.AddEdit("x300 yp+20 w254 h70", JoinLines("replies"))
    gw.AddText("x24 y+8", "Seconds between random lines (min 30):")
    G.interval := gw.AddEdit("x+8 yp-3 w60 Number", C["chatInterval"])
    gw.AddText("x+16 yp+3", "Bot's display name:")
    G.botName := gw.AddEdit("x+8 yp-3 w150", C["botName"])
    G.chatOn := gw.AddCheckBox("x24 y+10 " (On("chatOn") ? "Checked" : ""), "Chat in Auto")
    G.emotesOn := gw.AddCheckBox("x+16 " (On("emotesOn") ? "Checked" : ""), "Emotes")
    G.commandsOn := gw.AddCheckBox("x+16 " (On("commandsOn") ? "Checked" : ""), "Chat commands")
    G.waveOnReply := gw.AddCheckBox("x+16 " (On("waveOnReply") ? "Checked" : ""), "Wave on reply")
    G.smartOn := gw.AddCheckBox("x24 y+8 " (On("smartOn") ? "Checked" : ""), "Smart Brain (topics, memory this session, chat games)")
    gw.AddText("x24 y+8", "Your own answers (one per line:  question => answer):")
    G.qa := gw.AddEdit("x24 y+4 w530 h70", JoinLines("customQa"))
    b := gw.AddButton("x24 y+10 w120 h30", "Save")
    b.OnEvent("Click", (*) => SaveFromGui())

    ; --- Moods & Camera
    tab.UseTab(3)
    gw.AddText("x24 y82 w530", "Tick the moods you want; pick the current one on the Control tab. Normal is always there.")
    G.moodChecks := Map()
    en := "," C["enabledMoods"] ","
    i := 0
    for m in MOODS {
        if m.id = "normal"
            continue
        opt := (Mod(i, 4) = 0 ? "x24 y+8" : "x+16") " w110 " (InStr(en, "," m.id ",") ? "Checked" : "")
        G.moodChecks[m.id] := gw.AddCheckBox(opt, m.label)
        i++
    }
    G.moodLines := gw.AddCheckBox("x24 y+14 " (On("moodLines") ? "Checked" : ""), "Use the mood's own chat lines and replies (mixed with yours)")
    G.moodRotate := gw.AddCheckBox("x24 y+6 " (On("moodRotate") ? "Checked" : ""), "Change mood by itself every ~10 min (only ticked moods)")
    gw.SetFont("s10 bold c" CYAN)
    gw.AddText("x24 y+16", "Camera")
    gw.SetFont("s10 norm c000000")
    G.lookAround := gw.AddCheckBox("x24 y+6 " (On("lookAround") ? "Checked" : ""), "Look around in Auto")
    gw.AddText("x24 y+10", "Turn the camera with:")
    G.camKeys := gw.AddDropDownList("x+8 yp-3 w170", ["arrows", "mouse"])
    G.camKeys.Text := C["camKeys"]
    G.stuckOn := gw.AddCheckBox("x24 y+12 " (On("stuckOn") ? "Checked" : ""), "Stuck detection (backs up, jumps and turns when it walks into walls)")
    G.faceTalker := gw.AddCheckBox("x24 y+6 " (On("faceTalker") ? "Checked" : ""), "Turn to face people who talk to it")
    gw.SetFont("s9 c606060")
    gw.AddText("x24 y+10 w530", "Shift Lock mode (Control tab): turn ON 'Shift Lock Switch' in Roblox's settings first. The bot presses Shift to toggle it, "
        . "then walks forward and steers with the camera, so the avatar always faces where it looks. If it gets out of sync, press Shift once yourself.")
    gw.SetFont("s10 norm c000000")
    b := gw.AddButton("x24 y+12 w120 h30", "Save")
    b.OnEvent("Click", (*) => SaveFromGui())

    ; --- Moves
    tab.UseTab(4)
    gw.AddText("x24 y82 w530", "Record your own moves: press F11 (or Record), play the move yourself in Roblox with WASD / Space / arrows / Shift, then F11 again.")
    G.moves := gw.AddListBox("x24 y+8 w260 h250", ListMoves())
    b := gw.AddButton("x300 yp w150", "Record / stop (F11)")
    b.OnEvent("Click", (*) => ToggleRecord())
    b := gw.AddButton("x300 y+8 w150", "Play")
    b.OnEvent("Click", (*) => (G.moves.Text != "" && PlayMove(G.moves.Text)))
    b := gw.AddButton("x300 y+8 w150", "Rename")
    b.OnEvent("Click", (*) => RenameMove())
    b := gw.AddButton("x300 y+8 w150", "Delete")
    b.OnEvent("Click", (*) => DeleteMove())
    G.movesInAuto := gw.AddCheckBox("x24 y+150 " (On("movesInAuto") ? "Checked" : ""), "Use my moves in Auto (and players can say `"bot <move name>`")")
    G.movesInAuto.OnEvent("Click", (*) => (C["movesInAuto"] := G.movesInAuto.Value ? "1" : "0", SaveCfg()))

    ; --- Fly Brain
    tab.UseTab(5)
    gw.SetFont("s10 bold c" CYAN)
    gw.AddText("x24 y82", "Fly Brain mode - a real fruit fly brain drives the bot")
    gw.SetFont("s9 norm c404040")
    gw.AddText("x24 y+6 w530", "A whole-brain model of the adult fruit fly (FlyWire connectome: 138,639 neurons, 15 million connections; "
        . "neuron model from Shiu et al. 2024, Nature). Nothing is scripted. Roblox becomes its senses: chat = sound (antenna), "
        . "nice words = sugar, mean words = bitter, walls = touch, jumping = wind, screen motion = eyes, brightness = ocelli. "
        . "Its real command neurons become the controls: forward/turning neurons = walk and steer, MDN = walk backwards, "
        . "giant fiber = escape jump, grooming neurons = grooming, mouth motor neurons = typing (fly gibberish, max 1 a minute).")
    gw.AddText("x24 y+8 w530", "How: tick 'Fly Brain' on the Moods && Camera tab, Save, pick it as the mood, then Auto (F8). "
        . "Listen turns on by itself so the fly can 'hear' chat. It runs in slow motion if your PC can't keep up - that's normal.")
    gw.SetFont("s10 norm c000000")
    b := gw.AddButton("x24 y+10 w170", "Fly self-test")
    b.OnEvent("Click", (*) => FlySelfTest())
    G.flyMon := gw.AddEdit("x24 y+10 w530 h220 ReadOnly", "Fly Brain is off.")

    ; --- About
    tab.UseTab(6)
    gw.AddEdit("x24 y82 w530 h400 ReadOnly",
        "Hyper-Bot PC " VERSION "`r`n`r`n"
        . "How it works: it only presses keys, moves the mouse and reads the screen with Windows' built-in OCR - like a player. "
        . "No injection, no memory reading, no modified Roblox, no internet. Chat is read in memory only and never saved.`r`n`r`n"
        . "Built-in rules:`r`n"
        . " - Announces it's a bot on start and every 10 minutes; always answers 'yes' to 'are you a bot'.`r`n"
        . " - Chat limits: max 5 answers a minute, 10 s per person, random lines at most every 30 s.`r`n"
        . " - Follow: only the player who asked, or one you pick, max 60 s, 10 min cooldown and 3 a day per player; stops when asked.`r`n"
        . " - Pauses whenever Roblox isn't the active window (so it never types into other apps).`r`n`r`n"
        . "Use it on an ALT account only, and never while your main account is playing or macroing.`r`n`r`n"
        . "Setup: Roblox windowed or fullscreen, chat visible. 1) Calibrate chat area. 2) Type the bot's display name on the Chat && Brain tab. "
        . "3) Chat test + Listen test. 4) F8 Auto / F9 Listen.`r`n`r`n"
        . "Fly Brain: FlyWire connectome (FlyWire Consortium, Dorkenwald et al. 2024; Schlegel et al. 2024) and the brain model of Shiu et al. 2024 (Nature, MIT licence).`r`n"
        . "Credits: OCR library by Descolada (MIT licence, lib\OCR_LICENSE.txt). AutoHotkey v2 (GPL v2). Smart Brain shared with Hyper-Bot for Android.")
    tab.UseTab()

    gw.OnEvent("Close", (*) => (FlyStop(), ExitApp()))
    RefreshFollowNames()
    if !SELFTEST
        gw.Show("w580 h556")
}

JoinLines(k) {
    ln := ""
    for l in ListOf(k)
        ln .= (ln = "" ? "" : "`r`n") l
    return ln
}

FromEdit(ctrl) {
    ln := ""
    for l in StrSplit(ctrl.Value, "`n", "`r") {
        l := Trim(StrReplace(l, "|", "/"))
        if l != ""
            ln .= (ln = "" ? "" : "|") l
    }
    return ln
}

SaveFromGui() {
    C["intro"] := Trim(StrReplace(G.intro.Value, "|", "/"))
    C["lines"] := FromEdit(G.lines), C["replies"] := FromEdit(G.replies), C["customQa"] := FromEdit(G.qa)
    C["chatInterval"] := String(Max(30, IsInteger(G.interval.Value) ? Integer(G.interval.Value) : 45))
    G.interval.Value := C["chatInterval"]
    C["botName"] := Trim(G.botName.Value)
    for k in ["chatOn", "emotesOn", "commandsOn", "waveOnReply", "smartOn", "moodLines", "moodRotate", "lookAround", "stuckOn", "faceTalker"]
        C[k] := G.%k%.Value ? "1" : "0"
    en := ""
    for id, cb in G.moodChecks
        if cb.Value
            en .= (en = "" ? "" : ",") id
    C["enabledMoods"] := en
    C["camKeys"] := G.camKeys.Text
    SaveCfg()
    SetMood(C["mood"])
    Status(InStr(C["intro"], "bot") ? "Saved" : "Saved - but the intro must contain `"bot`", so the default intro is used")
}

MoodPicked(ctrl, *) {
    for m in EnabledMoods()
        if m.label = ctrl.Text {
            C["mood"] := m.id
            S.moodSince := NowMs()
            IniWrite(m.id, CFG_FILE, "bot", "mood")
            Status("Mood: " m.label)
        }
}

RefreshFollowNames() {
    try {
        names := []
        if C["followName"] != ""
            names.Push(C["followName"])
        for n in S.recentNames
            names.Push(n)
        cur := G.followPick.Text
        G.followPick.Delete()
        G.followPick.Add(names)
        G.followPick.Text := cur
    }
}

RefreshMoves() {
    try {
        G.moves.Delete()
        G.moves.Add(ListMoves())
    }
}

RenameMove() {
    old := G.moves.Text
    if old = ""
        return
    r := InputBox("New name for " old ":", "Rename move", "w300 h120", old)
    if r.Result != "OK"
        return
    nn := Trim(RegExReplace(r.Value, "[^A-Za-z0-9 _-]"))
    if nn = "" || nn = old
        return
    try FileMove(MOVES_DIR "\" old ".txt", MOVES_DIR "\" nn ".txt")
    RefreshMoves()
}

DeleteMove() {
    n := G.moves.Text
    if n = ""
        return
    if MsgBox("Delete the move '" n "'?", "Hyper-Bot", "YesNo Icon?") = "Yes" {
        try FileRecycle(MOVES_DIR "\" n ".txt")
        RefreshMoves()
    }
}

; ------------------------------------------------------------------ Fly Brain mode

FlyPython() {
    p := A_ScriptDir "\fly\python\pythonw.exe"
    return FileExist(p) ? '"' p '"' : "pythonw"
}

FlyStart() {
    if S.flyOn
        return
    if !FileExist(A_ScriptDir "\fly\fly_data.npz")
        return Status("Fly Brain: fly\fly_data.npz is missing (use the full Hyper-Bot PC zip)")
    DirCreate(A_ScriptDir "\fly\io")
    FlyWriteSenses(0)
    try FileDelete(A_ScriptDir "\fly\io\actions.txt")
    pid := 0
    try Run(FlyPython() ' "' A_ScriptDir '\fly\fly_server.py"', A_ScriptDir "\fly", "Hide", &pid)
    catch as e
        return Status("Fly Brain: couldn't start Python (" e.Message ")")
    S.flyPid := pid, S.flyOn := true, S.flyLast := Map(), S.flyStarted := NowMs()
    if !S.listening
        StartListening()
    SetTimer(FlyTick, 200)
    Status("Fly Brain starting (loading 138,639 neurons...)")
}

FlyStop() {
    if !S.flyOn
        return
    S.flyOn := false
    SetTimer(FlyTick, 0)
    try FlyWriteSenses(1)
    pid := S.flyPid
    SetTimer(() => (pid && ProcessExist(pid) ? ProcessClose(pid) : 0), -1500)
    ReleaseAll()
    try G.flyMon.Value := "Fly Brain stopped."
}

FlyHears(msg) {
    S.flySound += 1
    m := " " RegExReplace(StrLower(msg), "[^a-z ]", " ") " "
    for w in [" good ", " cute ", " cool ", " love ", " nice ", " awesome ", " best ", " sweet ", " yum ", " candy ", " sugar ", " pizza ", " food ", " cake ", " honey ", " pretty "]
        if InStr(m, w) {
            S.flyPraise += 1
            break
        }
    for w in [" bad ", " dumb ", " stupid ", " ugly ", " trash ", " noob ", " hate ", " gross ", " ew ", " weird ", " cringe "]
        if InStr(m, w) {
            S.flyInsult += 1
            break
        }
    if InStr(m, " water ") || InStr(m, " drink ") || InStr(m, " rain ")
        S.flyWater += 1
}

; 16x9 view of the Roblox window: left/right motion and brightness change, for the fly's eyes and ocelli
FlyVision(&motionL, &motionR, &lightChange) {
    motionL := motionR := lightChange := 0
    if !RbxRect(&x, &y, &w, &h)
        return
    TW := 16, TH := 9
    hdc := DllCall("GetDC", "ptr", 0, "ptr"), mdc := DllCall("CreateCompatibleDC", "ptr", hdc, "ptr")
    bi := Buffer(40, 0)
    NumPut("uint", 40, bi, 0), NumPut("int", TW, bi, 4), NumPut("int", -TH, bi, 8), NumPut("ushort", 1, bi, 12), NumPut("ushort", 32, bi, 14)
    bits := 0
    hbm := DllCall("CreateDIBSection", "ptr", mdc, "ptr", bi, "uint", 0, "ptr*", &bits, "ptr", 0, "uint", 0, "ptr")
    obm := DllCall("SelectObject", "ptr", mdc, "ptr", hbm, "ptr")
    DllCall("SetStretchBltMode", "ptr", mdc, "int", 4)
    DllCall("StretchBlt", "ptr", mdc, "int", 0, "int", 0, "int", TW, "int", TH, "ptr", hdc, "int", x, "int", y, "int", w, "int", h, "uint", 0x00CC0020)
    cur := []
    loop TW * TH {
        px := NumGet(bits, (A_Index - 1) * 4, "uint")
        cur.Push((((px >> 16) & 255) * 3 + ((px >> 8) & 255) * 6 + (px & 255)) // 10)
    }
    DllCall("SelectObject", "ptr", mdc, "ptr", obm), DllCall("DeleteObject", "ptr", hbm)
    DllCall("DeleteDC", "ptr", mdc), DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
    prev := S.flyPrev
    S.flyPrev := cur
    if prev = ""
        return
    dl := dr := 0, sumC := sumP := 0
    loop TW * TH {
        i := A_Index, d := Abs(cur[i] - prev[i]), sumC += cur[i], sumP += prev[i]
        if Mod(i - 1, TW) < TW // 2
            dl += d
        else
            dr += d
    }
    half := TW * TH / 2
    motionL := Round(dl / half / 255, 3), motionR := Round(dr / half / 255, 3)
    lightChange := Round(Abs(sumC - sumP) / (TW * TH) / 255, 3)
}

FlyWriteSenses(quit := 0) {
    FlyVision(&mL, &mR, &lc)
    players := Min(3, S.recentNames.Length)
    txt := "sound=" S.flySound "`npraise=" S.flyPraise "`ninsult=" S.flyInsult "`nwater=" S.flyWater
        . "`ntouch=" S.flyTouch "`nwind=" S.flyWind "`nmotionL=" mL "`nmotionR=" mR "`nlightchange=" lc
        . "`nplayers=" players "`nquit=" quit "`n"
    f := A_ScriptDir "\fly\io\senses.txt"
    try {
        FileOpen(f ".tmp", "w", "UTF-8-RAW").Write(txt)
        FileMove(f ".tmp", f, 1)
    }
}

FlyReadActions() {
    out := Map()
    try txt := FileRead(A_ScriptDir "\fly\io\actions.txt", "UTF-8")
    catch
        return out
    for line in StrSplit(txt, "`n", "`r")
        if (i := InStr(line, "=")) > 1
            out[SubStr(line, 1, i - 1)] := SubStr(line, i + 1)
    return out
}

FlyNum(a, k) => a.Has(k) && IsNumber(a[k]) ? Number(a[k]) : 0

FlyTick() {
    if !S.flyOn
        return
    if !RbxActive() {
        ReleaseAll()
        return
    }
    FlyWriteSenses(0)
    a := FlyReadActions()
    if !a.Has("seq") {
        if NowMs() - S.flyStarted > 60000
            Status("Fly Brain: no answer from the fly engine - try the Fly self-test on the Fly Brain tab")
        return
    }
    last := S.flyLast
    if last.Has("seq") && last["seq"] = a["seq"]
        return
    jumped := FlyNum(a, "jumps") > FlyNum(last, "jumps")
    backed := FlyNum(a, "backs") > FlyNum(last, "backs")
    groomed := FlyNum(a, "grooms") > FlyNum(last, "grooms")
    spoke := FlyNum(a, "words") > FlyNum(last, "words") && a.Has("word") && a["word"] != ""
    S.flyLast := a
    if !last.Has("seq")
        return Status("Fly Brain is alive")
    now := NowMs(), fwd := FlyNum(a, "forward"), turn := FlyNum(a, "turn"), did := []
    spd := Max(0.2, FlyNum(a, "speed")) ; slow-motion brain -> longer key presses per decision
    if jumped
        Jump(), S.flyWind -= 1, did.Push("ESCAPE JUMP (giant fiber)")
    if backed
        Hold("s", Min(900, Round(450 / spd))), did.Push("moonwalk back (MDN)")
    else if fwd > 0.3
        Hold("w", Min(900, Round(220 / spd))), S.lastWalkAt := now, did.Push("walk " Round(fwd * 100) "%")
    if Abs(turn) > 0.08
        CamTurn(turn < 0 ? -1 : 1, Min(300, Round(Abs(turn) * 400))), did.Push("turn " (turn < 0 ? "left" : "right"))
    if groomed {
        Hold("a", 110), SetTimer(Hold.Bind("d", 110), -150), did.Push("grooming")
        if now - S.flyLastGroomChat > 120000 && now - S.flyLastWord > 30000 && Random(1, 3) = 1
            S.flyLastGroomChat := now, QueueChat("[fly brain bot] *rubs front legs together*")
    }
    if spoke && now - S.flyLastWord > 60000
        S.flyLastWord := now, QueueChat("[fly brain bot] " a["word"]), did.Push("typed: " a["word"])
    try G.flyMon.Value := "FLY BRAIN LIVE   (brain time " Round(FlyNum(a, "brainms") / 1000, 1) " s, speed x" a["speed"] " real time)`r`n"
        . "spikes in the last 0.2 s: " a["spikes"] "    neurons active: " a["active"] " / 138,639`r`n"
        . "descending (command) neuron spikes: " a["dn"] "    mouth motor spikes: " a["mouth"] "`r`n"
        . "forward drive: " Round(fwd * 100) "%    turn: " turn "`r`n"
        . "escape jumps: " a["jumps"] "   moonwalks: " a["backs"] "   grooms: " a["grooms"] "   words typed: " a["words"] "`r`n"
        . "senses: sound " S.flySound "  sugar " S.flyPraise "  bitter " S.flyInsult "  touch " S.flyTouch "  wind " S.flyWind "`r`n`r`n"
        . "now: " (did.Length ? JoinArr(did) : "resting")
}

JoinArr(arr, sep := ", ") {
    out := ""
    for x in arr
        out .= (out = "" ? "" : sep) x
    return out
}

FlySelfTest() {
    if !FileExist(A_ScriptDir "\fly\fly_data.npz")
        return G.flyMon.Value := "fly\fly_data.npz is missing (use the full Hyper-Bot PC zip)."
    G.flyMon.Value := "Running the fly self-test (about 10-30 s)..."
    py := StrReplace(FlyPython(), "pythonw", "python")
    out := A_Temp "\hyperbot_fly_selftest.txt"
    try {
        RunWait(A_ComSpec ' /c "' py ' "' A_ScriptDir '\fly\fly_server.py" --selftest > "' out '" 2>&1"', A_ScriptDir "\fly", "Hide")
        G.flyMon.Value := FileRead(out)
    } catch as e
        G.flyMon.Value := "Self-test couldn't run: " e.Message
}

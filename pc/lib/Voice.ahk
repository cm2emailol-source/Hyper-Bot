#Requires AutoHotkey v2.0
; Hyper-Bot voice (Phase 3): Piper "Alan" British voice -> VB-Audio Virtual Cable -> VRChat mic.

global VOICE := {dir: A_LineFile "\..\..\voice", pid: 0, seq: 0, stopN: 0,
    url: "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/alan/"}

VoicePath(f) => VOICE.dir "\" f
VoiceModel(f) => DATA "\models\voice\" f
VoiceHasModel(q := "low") => FileExist(VoiceModel("en_GB-alan-" q ".onnx")) && FileExist(VoiceModel("en_GB-alan-" q ".onnx.json"))
VoiceRunning() => VOICE.pid && ProcessExist(VOICE.pid)

VoiceDownload(q := "low") {
    DirCreate(DATA "\models\voice")
    cmd := ""
    for f in ["en_GB-alan-" q ".onnx", "en_GB-alan-" q ".onnx.json"]
        cmd .= 'curl.exe -L -C - --fail -o "' VoiceModel(f) '" "' VOICE.url q "/" f '" && '
    Run(A_ComSpec ' /c "echo Downloading the Piper Alan (' q ') voice for Hyper-Bot... && ' cmd 'echo. && echo Done - you can close this window. && pause"')
}

VoiceCtl(monitor, quality) {
    DirCreate(VoicePath("io"))
    FileOpen(VoicePath("io\ctl.txt"), "w", "UTF-8-RAW").Write("monitor=" monitor "`nstop=" VOICE.stopN "`nquality=" quality "`n")
}

VoiceStart(monitor, quality) {
    if VoiceRunning()
        return true
    if !VoiceHasModel(quality) && !VoiceHasModel("low") && !VoiceHasModel("medium")
        return false
    DirCreate(VoicePath("io"))
    try FileDelete(VoicePath("io\say.txt"))
    try FileDelete(VoicePath("io\state.txt"))
    VOICE.seq := 0
    VoiceCtl(monitor, quality)
    py := A_LineFile "\..\..\fly\python\pythonw.exe"
    pid := 0
    Run('"' (FileExist(py) ? py : "pythonw") '" "' VoicePath("voice.py") '"', VOICE.dir, "Hide", &pid)
    VOICE.pid := pid
    return true
}

VoiceStop() {
    try FileOpen(VoicePath("io\ctl.txt"), "w", "UTF-8-RAW").Write("quit=1`n")
    p := VOICE.pid
    if p
        SetTimer(() => ProcessExist(p) && ProcessClose(p), -1500)
    VOICE.pid := 0
}

; queue a line to be spoken (style: "normal" or "mad")
VoiceSay(text, style := "normal") {
    if !VoiceRunning()
        return
    text := Trim(RegExReplace(text, "[|\r\n]", " "))
    if text = ""
        return
    VOICE.seq += 1
    FileAppend(VOICE.seq "|" style "|" text "`n", VoicePath("io\say.txt"), "UTF-8-RAW")
}

; stop talking now and drop anything queued
VoiceInterrupt(monitor, quality) {
    VOICE.stopN += 1
    VoiceCtl(monitor, quality)
}

VoiceState() {
    out := Map()
    try for l in StrSplit(FileRead(VoicePath("io\state.txt"), "UTF-8"), "`n", "`r")
        if (i := InStr(l, "=")) > 1
            out[SubStr(l, 1, i - 1)] := SubStr(l, i + 1)
    return out
}

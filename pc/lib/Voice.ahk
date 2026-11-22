#Requires AutoHotkey v2.0
; Hyper-Bot voice (Phase 3): Piper "Alan" British voice -> VB-Audio Virtual Cable -> VRChat mic.

global VOICE := {dir: A_LineFile "\..\..\voice", pid: 0, seq: 0, stopN: 0,
    url: "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_GB/alan/"}

VoicePath(f) => VOICE.dir "\" f
VoiceModel(f) => DATA "\models\voice\" f
; a voice is a Piper file name like en_GB-alan-low, en_US-ryan-high, en_US-joe-medium ("low"/"medium" still mean Alan)
VoiceBaseOf(q) => q = "low" || q = "medium" || q = "" ? "en_GB-alan-" (q = "" ? "low" : q) : q
VoiceHasModel(q := "low") => FileExist(VoiceModel(VoiceBaseOf(q) ".onnx")) && FileExist(VoiceModel(VoiceBaseOf(q) ".onnx.json"))
VoiceRunning() => VOICE.pid && ProcessExist(VOICE.pid)

VoiceDownload(q := "low") {
    base := VoiceBaseOf(q)
    p := StrSplit(base, "-") ; en_US, ryan, high
    if p.Length < 3
        return
    url := "https://huggingface.co/rhasspy/piper-voices/resolve/main/" SubStr(p[1], 1, 2) "/" p[1] "/" p[2] "/" p[3] "/"
    DirCreate(DATA "\models\voice")
    cmd := ""
    for f in [base ".onnx", base ".onnx.json"]
        cmd .= 'curl.exe -L -C - --fail -o "' VoiceModel(f) '" "' url f '" && '
    Run(A_ComSpec ' /c "echo Downloading the Piper voice ' base ' for Hyper-Bot (one time)... && ' cmd '(echo. & echo Done - you can close this window.) || echo DOWNLOAD FAILED - see the error above & pause"')
}

VoiceCtl(monitor, quality) {
    DirCreate(VoicePath("io"))
    base := VoiceBaseOf(quality)
    FileOpen(VoicePath("io\ctl.txt"), "w", "UTF-8-RAW").Write("monitor=" monitor "`nstop=" VOICE.stopN "`nquality=" (InStr(base, "alan-medium") ? "medium" : "low") "`nvoice=" base "`n")
}

VoiceStart(monitor, quality) {
    if VoiceRunning()
        return true
    if !VoiceHasModel(quality) && !VoiceHasModel("low") && !VoiceHasModel("medium")
        return false
    DirCreate(VoicePath("io"))
    try FileDelete(VoicePath("io\say.txt"))
    try FileDelete(VoicePath("io\state.txt"))
    try FileDelete(VoicePath("io\error.txt"))
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

VoiceLastError() {
    try {
        lines := StrSplit(Trim(FileRead(VoicePath("io\error.txt"), "UTF-8"), "`r`n"), "`n", "`r")
        return lines[lines.Length]
    }
    return ""
}

VoiceLastLog() {
    try {
        lines := StrSplit(Trim(FileRead(VoicePath("io\log.txt"), "UTF-8"), "`r`n"), "`n", "`r")
        return lines[lines.Length]
    }
    return ""
}

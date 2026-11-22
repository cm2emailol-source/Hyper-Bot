#Requires AutoHotkey v2.0
; Hyper-Bot ears: whisper.cpp (whisper-server.exe, 127.0.0.1:8098) + ears\ears.py (hears this PC's sound output).

global EARS := {dir: A_LineFile "\..\..\ears", serverPid: 0, pyPid: 0, lastSeq: 0,
    model: "ggml-base.en.bin", url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"}

EarsPath(f) => EARS.dir "\" f
EarsServerExe() {
    loop files EARS.dir "\whisper\whisper-server.exe", "R"
        return A_LoopFileFullPath
    return ""
}
EarsModel(f) => DATA "\models\ears\" f
EarsHasModel() => FileExist(EarsModel(EARS.model))
EarsPython() {
    p := A_LineFile "\..\..\fly\python\pythonw.exe"
    return FileExist(p) ? p : "pythonw"
}

EarsDownload() {
    DirCreate(DATA "\models\ears")
    Run(A_ComSpec ' /c "echo Downloading Whisper base.en for Hyper-Bot (about 150 MB, one time)... && curl.exe -L -C - --fail -o "'
        . EarsModel(EARS.model) '" "' EARS.url EARS.model '" && (echo. & echo Done - you can close this window.) || echo DOWNLOAD FAILED - see the error above & pause"')
}

EarsStart() {
    if EARS.serverPid && ProcessExist(EARS.serverPid)
        return true
    exe := EarsServerExe()
    if exe = "" || !EarsHasModel()
        return false
    DirCreate(EarsPath("io"))
    try FileDelete(EarsPath("io\heard.txt"))
    try FileDelete(EarsPath("io\status.txt"))
    FileOpen(EarsPath("io\ctl.txt"), "w", "UTF-8-RAW").Write("pause=0`n")
    threads := Max(2, EnvGet("NUMBER_OF_PROCESSORS") // 3)
    pid := 0
    Run('"' exe '" -m "' EarsModel(EARS.model) '" --host 127.0.0.1 --port 8098 -t ' threads, EARS.dir, "Hide", &pid)
    EARS.serverPid := pid
    pid := 0
    Run('"' EarsPython() '" "' EarsPath("ears.py") '"', EARS.dir, "Hide", &pid)
    EARS.pyPid := pid, EARS.lastSeq := 0
    return true
}

EarsStop() {
    try FileOpen(EarsPath("io\ctl.txt"), "w", "UTF-8-RAW").Write("quit=1`n")
    for p in [EARS.pyPid, EARS.serverPid]
        if p && ProcessExist(p)
            SetTimer(((pp) => ProcessExist(pp) && ProcessClose(pp)).Bind(p), -1200)
    EARS.serverPid := 0, EARS.pyPid := 0
}

EarsRunning() => EARS.serverPid && ProcessExist(EARS.serverPid)

; returns the newest thing heard since last time, or ""
EarsRead() {
    try txt := Trim(FileRead(EarsPath("io\heard.txt"), "UTF-8"), "`r`n ")
    catch
        return ""
    if !(i := InStr(txt, "|"))
        return ""
    seq := Integer(SubStr(txt, 1, i - 1))
    if seq = EARS.lastSeq
        return ""
    EARS.lastSeq := seq
    return Trim(SubStr(txt, i + 1))
}

; what the listener reports once a second: the device it records from and the loudness (0-100), or an error
EarsInfo() {
    out := {device: "", level: -1, error: ""}
    try txt := FileRead(EarsPath("io\status.txt"), "UTF-8")
    catch
        return out
    if RegExMatch(txt, "m)^device=(.*)$", &m)
        out.device := Trim(m[1])
    if RegExMatch(txt, "m)^level=(\d+)", &m)
        out.level := Number(m[1])
    if RegExMatch(txt, "m)^error=(.*)$", &m)
        out.error := Trim(m[1])
    if EARS.pyPid && !ProcessExist(EARS.pyPid) && out.error = ""
        out.error := "the listener stopped"
    return out
}

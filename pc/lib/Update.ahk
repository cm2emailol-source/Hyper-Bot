#Requires AutoHotkey v2.0
; One-click updates from the public GitHub releases (pc-build-N). Only program files are replaced;
; HyperBot-Data (models, settings, moves, fly memory) is never touched.

global UPD := {repo: "cm2emailol-source/Hyper-Bot"}

UpdMyBuild() {
    for f in [A_ScriptDir "\build.txt", A_LineFile "\..\..\build.txt"]
        try return Integer(RegExReplace(FileRead(f), "\D"))
    return 0
}

UpdMyRuntime() {
    for f in [A_ScriptDir "\runtime.txt", A_LineFile "\..\..\runtime.txt"]
        try return Trim(FileRead(f), " `r`n")
    return ""
}

; parse the GitHub release list -> newest PC build: {build, full, core, runtime}
UpdParse(txt) {
    rel := Map()
    pos := 1
    while pos := RegExMatch(txt, '"browser_download_url"\s*:\s*"([^"]*/pc-build-(\d+)/([^"/]+))"', &m, pos) {
        pos += m.Len
        n := Integer(m[2]), f := m[3]
        if !rel.Has(n)
            rel[n] := {build: n, full: "", core: "", runtime: ""}
        if RegExMatch(f, "^HyperBot-PC-\d+\.zip$")
            rel[n].full := m[1]
        else if RegExMatch(f, "^HyperBot-PC-core-\d+\.zip$")
            rel[n].core := m[1]
        else if RegExMatch(f, "^runtime-([0-9a-f]+)\.txt$", &h)
            rel[n].runtime := h[1]
    }
    best := ""
    for n, r in rel
        if r.full != "" && (best = "" || n > best.build)
            best := r
    return best
}

; newest PC build, or a reason string
UpdLatest() {
    try {
        h := ComObject("WinHttp.WinHttpRequest.5.1")
        h.Open("GET", "https://api.github.com/repos/" UPD.repo "/releases?per_page=30", false)
        h.SetRequestHeader("User-Agent", "Hyper-Bot")
        h.Send()
        if h.Status != 200
            return h.Status = 404 ? "private" : "http " h.Status
        best := UpdParse(h.ResponseText)
        return best = "" ? "none" : best
    } catch as e
        return "error " e.Message
}

UpdCheck(silent := false) {
    r := UpdLatest()
    if !IsObject(r) {
        if !silent
            Status(r = "private" ? "Update: the GitHub repo is private - make it public to use the Update button"
                : "Update: couldn't check (" r ")")
        return
    }
    mine := UpdMyBuild()
    if r.build <= mine {
        if !silent
            Status("Hyper-Bot is up to date (build " mine ")")
        return
    }
    small := r.core != "" && r.runtime != "" && r.runtime = UpdMyRuntime()
    r.url := small ? r.core : r.full
    if MsgBox("A new Hyper-Bot is available: build " r.build " (you have build " mine ").`n`n"
        . (small ? "It's a small update (about 1 MB). " : "This update includes new engines (about 125 MB). ")
        . "Download and install it now? "
        . "Hyper-Bot will close and restart by itself. Your models, settings, moves and fly memory stay safe in HyperBot-Data.",
        "Hyper-Bot update", "YesNo Iconi 262144") = "Yes"
        UpdInstall(r)
}

UpdInstall(r) {
    tmp := A_Temp "\HyperBot-update"
    try DirDelete(tmp, true)
    try FileDelete(A_Temp "\HyperBot-update.bat")
    DirCreate(tmp)
    app := RegExReplace(A_LineFile, "\\lib\\[^\\]+$")
    bat := A_Temp "\HyperBot-update.bat"
    q1 := Chr(39), q2 := Chr(34) ; ' and " for the PowerShell command
    ; the batch waits for Hyper-Bot to close, downloads, unpacks, copies program files over, and restarts it
    FileAppend(
        "@echo off`r`n"
        . "title Hyper-Bot update`r`n"
        . "echo Updating Hyper-Bot to build " r.build "... (please wait)`r`n"
        . "timeout /t 2 /nobreak >nul`r`n"
        . 'curl.exe -L --fail -o "' tmp '\new.zip" "' r.url '" || (echo DOWNLOAD FAILED & pause & exit /b 1)' "`r`n"
        . "powershell -NoProfile -ExecutionPolicy Bypass -Command " q2 "Expand-Archive -Force " q1 tmp "\new.zip" q1 " " q1 tmp "\new" q1 "; "
        . "Get-ChildItem -LiteralPath " q1 tmp "\new" q1 " -Recurse -File | Unblock-File" q2 " || (echo UNZIP FAILED & pause & exit /b 1)`r`n"
        . 'robocopy "' tmp '\new\HyperBot-PC" "' app '" /E /R:3 /W:1 /NFL /NDL /NJH /NJS /XD io >nul' "`r`n"
        . 'if %ERRORLEVEL% GEQ 8 (echo COPY FAILED - close anything using the Hyper-Bot folder and try again & pause & exit /b 1)' "`r`n"
        . 'start "" "' app '\Start Hyper-Bot.bat"' "`r`n"
        . 'rd /s /q "' tmp '"' "`r`n"
        . '(goto) 2>nul & del "%~f0"' "`r`n", bat, "UTF-8-RAW")
    try FlyStop()
    try AiStop()
    try EarsStop()
    try VoiceStop()
    try StopAll()
    Run(A_ComSpec ' /c ""' bat '""', tmp)
    Sleep 300
    ExitApp
}

#Requires AutoHotkey v2.0
; One-click updates from the public GitHub releases (pc-build-N). Only program files are replaced;
; HyperBot-Data (models, settings, moves, fly memory) is never touched.

global UPD := {repo: "cm2emailol-source/Hyper-Bot"}

UpdMyBuild() {
    try return Integer(Trim(FileRead(A_LineFile "\..\..\build.txt")))
    return 0
}

; {build, url, size} of the newest PC build, or "" (shows why in Status)
UpdLatest() {
    try {
        h := ComObject("WinHttp.WinHttpRequest.5.1")
        h.Open("GET", "https://api.github.com/repos/" UPD.repo "/releases?per_page=30", false)
        h.SetRequestHeader("User-Agent", "Hyper-Bot")
        h.Send()
        if h.Status != 200
            return h.Status = 404 ? "private" : "http " h.Status
        best := "", txt := h.ResponseText, pos := 1
        while pos := RegExMatch(txt, '"browser_download_url"\s*:\s*"([^"]*/pc-build-(\d+)/HyperBot-PC-\d+\.zip)"', &m, pos) {
            if best = "" || Integer(m[2]) > best.build
                best := {build: Integer(m[2]), url: m[1]}
            pos += m.Len
        }
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
    if MsgBox("A new Hyper-Bot is available: build " r.build " (you have build " mine ").`n`nDownload and install it now? "
        . "Hyper-Bot will close and restart by itself. Your models, settings, moves and fly memory stay safe in HyperBot-Data.",
        "Hyper-Bot update", "YesNo Iconi 262144") = "Yes"
        UpdInstall(r)
}

UpdInstall(r) {
    tmp := A_Temp "\HyperBot-update"
    try DirDelete(tmp, true)
    DirCreate(tmp)
    app := RegExReplace(A_LineFile, "\\lib\\[^\\]+$")
    bat := tmp "\update.bat"
    ; the batch waits for Hyper-Bot to close, downloads, unpacks, copies program files over, and restarts it
    FileAppend(
        "@echo off`r`n"
        . "title Hyper-Bot update`r`n"
        . "echo Updating Hyper-Bot to build " r.build "... (please wait)`r`n"
        . "timeout /t 2 /nobreak >nul`r`n"
        . 'curl.exe -L --fail -o "' tmp '\new.zip" "' r.url '" || (echo DOWNLOAD FAILED & pause & exit /b 1)' "`r`n"
        . 'powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Force ''' tmp '\new.zip'' ''' tmp '\new''; '
        . 'Get-ChildItem -LiteralPath ''' tmp '\new'' -Recurse -File | Unblock-File"' " || (echo UNZIP FAILED & pause & exit /b 1)`r`n"
        . 'robocopy "' tmp '\new\HyperBot-PC" "' app '" /E /R:3 /W:1 /NFL /NDL /NJH /NJS /XD io >nul' "`r`n"
        . 'if %ERRORLEVEL% GEQ 8 (echo COPY FAILED - close anything using the Hyper-Bot folder and try again & pause & exit /b 1)' "`r`n"
        . 'start "" "' app '\Start Hyper-Bot.bat"' "`r`n"
        . "exit /b 0`r`n", bat, "UTF-8-RAW")
    try FlyStop()
    try AiStop()
    try EarsStop()
    try VoiceStop()
    try StopAll()
    Run(A_ComSpec ' /c ""' bat '""', tmp)
    Sleep 300
    ExitApp
}

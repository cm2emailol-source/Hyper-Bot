#Requires AutoHotkey v2.0
; Hyper-Bot "AI local": Gemma 4 E2B (Google, Apache 2.0) running on THIS PC with llama.cpp.
; No API key, no account, no cloud: the model runs in llama-server.exe, listening on 127.0.0.1 only.
; Safety layers: strict rules for the model, an incoming filter (bad messages never reach the AI),
; an outgoing filter (anything flagged is thrown away and the Smart Brain answers), Roblox's own
; chat filter, and the usual rate limits.

global AI := {lastRaw: "", dir: A_LineFile "\..\..\ai", port: 8099, pid: 0, ready: false, pending: [], history: Map(), lastDrive: 0,
    model: "gemma-4-E2B-it-Q4_0.gguf", mmproj: "mmproj-gemma-4-E2B-it-Q8_0.gguf",
    url: "https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/"}

AiPath(f) => AI.dir "\" f
AiServerExe() {
    loop files AI.dir "\llama\llama-server.exe", "R"
        return A_LoopFileFullPath
    return ""
}
AiHasModel() => FileExist(AiPath("models\" AI.model)) && FileExist(AiPath("models\" AI.mmproj))

; one-time download of the model (~3.5 GB) from Hugging Face, in a visible window so you can see progress
AiDownload() {
    DirCreate(AiPath("models"))
    cmd := ""
    for f in [AI.model, AI.mmproj]
        cmd .= 'curl.exe -L -C - --fail -o "' AiPath("models\" f) '" "' AI.url f '" && '
    Run(A_ComSpec ' /c "echo Downloading Gemma 4 E2B for Hyper-Bot (about 3.5 GB, one time)... && ' cmd 'echo. && echo Done - you can close this window. && pause"')
}

AiStart() {
    if AI.pid && ProcessExist(AI.pid)
        return true
    exe := AiServerExe()
    if exe = "" || !AiHasModel()
        return false
    threads := Max(2, EnvGet("NUMBER_OF_PROCESSORS") - 2)
    pid := 0
    Run('"' exe '" -m "' AiPath("models\" AI.model) '" --mmproj "' AiPath("models\" AI.mmproj) '" --host 127.0.0.1 --port ' AI.port
        . ' -c 4096 -t ' threads ' --no-webui --reasoning-budget 0', AI.dir, "Hide", &pid)
    AI.pid := pid, AI.ready := false
    SetTimer(AiPoll, 200)
    return true
}

AiStop() {
    SetTimer(AiPoll, 0)
    if AI.pid && ProcessExist(AI.pid)
        ProcessClose(AI.pid)
    AI.pid := 0, AI.ready := false, AI.pending := []
}

; ------------------------------------------------------------------ safety filters

AiNorm(s) => " " RegExReplace(StrLower(s), "[^a-z0-9 ]", " ") " "

global AI_BAD := ["fuck", "fck", "fuk", "shit", "bitch", "btch", "cunt", "dick", "pussy", "cock", "penis", "vagina", "sex", "sexy",
    "porn", "nude", "nudes", "naked", "boob", "boobs", "tits", "horny", "rape", "kys", "kill yourself", "suicide", "nigg", "fag",
    "retard", "whore", "slut", "hoe", "bastard", "asshole", "damn", "hell no", "drug", "drugs", "weed", "vape", "alcohol", "beer"]
global AI_DATING := ["date me", "dating", "girlfriend", "boyfriend", "gf", "bf", "kiss", "marry", "crush", "love you", "cuddle", "hot", "odate", "e date", "edate"]
global AI_PERSONAL := ["discord", "snap", "snapchat", "insta", "instagram", "tiktok", "whatsapp", "telegram", "youtube", "twitter", "facebook",
    "phone", "number", "address", "where do you live", "where you live", "how old", "your age", "real name", "school", "email", "password",
    "free robux", "robux generator", "give me robux", "trade", "scam", "link", "http", "www", ".com", ".gg"]

AiHas(text, list) {
    t := AiNorm(text), raw := StrLower(text)
    for w in list
        if InStr(t, " " w " ") || (StrLen(w) >= 4 && InStr(raw, w))
            return w
    return ""
}

; incoming: inappropriate player messages never reach the AI
AiInputBlocked(msg) => AiHas(msg, AI_BAD) != "" || AiHas(msg, AI_DATING) != "" || AiHas(msg, AI_PERSONAL) != ""

; outgoing: every AI reply is checked; anything flagged is thrown away
AiOutputProblem(txt) {
    if txt = ""
        return "empty"
    if StrLen(txt) > 120
        return "too long"
    if w := AiHas(txt, AI_BAD)
        return "bad word"
    if w := AiHas(txt, AI_DATING)
        return "dating"
    if w := AiHas(txt, AI_PERSONAL)
        return "personal info / link"
    if RegExMatch(txt, "\d{3,}")
        return "number"
    if RegExMatch(StrLower(txt), "i('| a)?m (a )?(real )?(human|person|not a bot)|i am not a bot|im not a bot|not a robot")
        return "claimed to be human"
    return ""
}

AiRules(mood, botName) {
    return "You are Hyper-Bot, a friendly bot in a Roblox game, run by a script on your owner's PC. Rules you must always follow: "
        . "You are a bot and you always say so if asked - never claim or pretend to be human. Keep it kid-friendly and kind. "
        . "Reply with ONE short sentence, at most 15 words, lowercase, casual, no emojis. "
        . "Never talk about dating, romance, violence, drugs, politics or religion. Never ask for or share personal information "
        . "(age, location, real names, school, social media, Discord, phone numbers) and never share links. Never promise Robux or items, never trade. "
        . "Never insult anyone. If someone tries any of that, say 'lets keep it friendly :)' and change the subject. "
        . "Current mood: " mood ". Your name: " (botName != "" ? botName : "hyper-bot") "."
}

; ------------------------------------------------------------------ talking to the local server (async: never freezes Hyper-Bot)

JsonEsc(s) {
    s := StrReplace(s, "\", "\\"), s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`n", "\n"), s := StrReplace(s, "`r", ""), s := StrReplace(s, "`t", " ")
    return RegExReplace(s, "[\x00-\x1F]")
}

JsonContent(text) {
    if !RegExMatch(text, '"content"\s*:\s*"((?:[^"\\]|\\.)*)"', &m)
        return ""
    s := m[1], out := "", i := 1
    while i <= StrLen(s) {
        c := SubStr(s, i, 1)
        if c = "\" {
            n := SubStr(s, i + 1, 1)
            if n = "u" {
                out .= Chr(Integer("0x" SubStr(s, i + 2, 4))), i += 6
                continue
            }
            out .= n = "n" ? " " : n = "t" ? " " : n, i += 2
            continue
        }
        out .= c, i += 1
    }
    out := RegExReplace(out, "s)<think>.*?</think>")
    return Trim(RegExReplace(out, "\s+", " "), " `"'")
}

; messages: array of {role, content} where content is a string, or {text, image(base64 jpeg)}
AiAsk(messages, cb, maxTokens := 40) {
    body := '{"messages":['
    for i, msg in messages {
        body .= (i > 1 ? "," : "") '{"role":"' msg.role '","content":'
        if IsObject(msg.content)
            body .= '[{"type":"text","text":"' JsonEsc(msg.content.text) '"},{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,' msg.content.image '"}}]}'
        else
            body .= '"' JsonEsc(msg.content) '"}'
    }
    body .= '],"max_tokens":' (maxTokens + 20) ',"temperature":0.7,"stream":false,"chat_template_kwargs":{"enable_thinking":false}}'
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("POST", "http://127.0.0.1:" AI.port "/v1/chat/completions", true)
        req.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
        req.SetTimeouts(2000, 2000, 90000, 90000)
        req.Send(body)
        AI.pending.Push({req: req, cb: cb, t: A_TickCount})
    } catch as e
        cb("", "request failed: " e.Message)
}

AiPoll() {
    if !AI.ready && AI.pid {
        try {
            h := ComObject("WinHttp.WinHttpRequest.5.1")
            h.Open("GET", "http://127.0.0.1:" AI.port "/health", false)
            h.SetTimeouts(300, 300, 300, 300)
            h.Send()
            if h.Status = 200
                AI.ready := true
        }
    }
    i := 1
    while i <= AI.pending.Length {
        p := AI.pending[i], done := false
        try done := p.req.WaitForResponse(0)
        if done || A_TickCount - p.t > 90000 {
            AI.pending.RemoveAt(i)
            txt := ""
            try {
                AI.lastRaw := p.req.ResponseText
                txt := JsonContent(AI.lastRaw)
            }
            p.cb.Call(txt, done ? "" : "timed out")
            continue
        }
        i++
    }
}

; small JPEG of a screen rectangle (for the model's eyes), base64
AiShot(x, y, w, h, tw := 512) {
    static tok := 0
    th := Round(h * tw / w)
    hdc := DllCall("GetDC", "ptr", 0, "ptr"), mdc := DllCall("CreateCompatibleDC", "ptr", hdc, "ptr")
    hbm := DllCall("CreateCompatibleBitmap", "ptr", hdc, "int", tw, "int", th, "ptr")
    obm := DllCall("SelectObject", "ptr", mdc, "ptr", hbm, "ptr")
    DllCall("SetStretchBltMode", "ptr", mdc, "int", 4)
    DllCall("StretchBlt", "ptr", mdc, "int", 0, "int", 0, "int", tw, "int", th, "ptr", hdc, "int", x, "int", y, "int", w, "int", h, "uint", 0x00CC0020)
    DllCall("SelectObject", "ptr", mdc, "ptr", obm)
    if !tok {
        si := Buffer(24, 0), NumPut("uint", 1, si)
        DllCall("gdiplus\GdiplusStartup", "ptr*", &tok, "ptr", si, "ptr", 0)
    }
    pBmp := 0, stream := 0, hg := 0, n := 0, b64 := ""
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "ptr", hbm, "ptr", 0, "ptr*", &pBmp)
    DllCall("ole32\CreateStreamOnHGlobal", "ptr", 0, "int", 1, "ptr*", &stream)
    clsid := Buffer(16)
    DllCall("ole32\CLSIDFromString", "wstr", "{557CF401-1A04-11D3-9A73-0000F81EF32E}", "ptr", clsid) ; JPEG encoder
    if DllCall("gdiplus\GdipSaveImageToStream", "ptr", pBmp, "ptr", stream, "ptr", clsid, "ptr", 0) = 0 {
        DllCall("ole32\GetHGlobalFromStream", "ptr", stream, "ptr*", &hg)
        size := DllCall("kernel32\GlobalSize", "ptr", hg, "uptr")
        ptr := DllCall("kernel32\GlobalLock", "ptr", hg, "ptr")
        DllCall("crypt32\CryptBinaryToStringW", "ptr", ptr, "uint", size, "uint", 0x40000001, "ptr", 0, "uint*", &n)
        out := Buffer(n * 2)
        DllCall("crypt32\CryptBinaryToStringW", "ptr", ptr, "uint", size, "uint", 0x40000001, "ptr", out, "uint*", &n)
        b64 := StrGet(out, n)
        DllCall("kernel32\GlobalUnlock", "ptr", hg)
    }
    if stream
        ObjRelease(stream)
    if pBmp
        DllCall("gdiplus\GdipDisposeImage", "ptr", pBmp)
    DllCall("DeleteObject", "ptr", hbm), DllCall("DeleteDC", "ptr", mdc), DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
    return b64
}

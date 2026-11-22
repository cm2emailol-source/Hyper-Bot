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

; swearing: blocked in Polite/Normal, ALLOWED in Unhinged
global AI_SWEAR := ["fuck", "fck", "fuk", "shit", "bitch", "btch", "bitchass", "bastard", "asshole", "ass", "damn", "hell no", "crap", "piss", "wtf", "stfu"]
; always blocked in every mode: slurs/hate, sexual, self-harm, threats, drugs
global AI_HARD := ["cunt", "dick", "pussy", "cock", "penis", "vagina", "sex", "sexy", "porn", "nude", "nudes", "naked", "boob", "boobs", "tits",
    "horny", "rape", "kys", "kill yourself", "suicide", "self harm", "nigg", "fag", "retard", "tranny", "whore", "slut", "hoe",
    "drug", "drugs", "weed", "vape", "cocaine", "kill you", "murder you", "i will find you", "hitler", "nazi"]
global AI_BAD := []
for w in AI_SWEAR
    AI_BAD.Push(w)
for w in AI_HARD
    AI_BAD.Push(w)
global AI_INSULT := ["dumb", "stupid", "trash", "noob", "ugly", "loser", "idiot", "shut up", "stfu", "bitch", "bozo", "clown", "cringe", "garbage", "useless", "annoying"]
global AI_MODES := ["polite", "normal", "unhinged"]
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
AiInputBlocked(msg, mode := "normal") => AiHas(msg, mode = "unhinged" ? AI_HARD : AI_BAD) != "" || AiHas(msg, AI_DATING) != "" || AiHas(msg, AI_PERSONAL) != ""

; outgoing: every AI reply is checked; anything flagged is thrown away
AiOutputProblem(txt, mode := "normal") {
    if txt = ""
        return "empty"
    if StrLen(txt) > (mode = "unhinged" ? 430 : 120)
        return "too long"
    if w := AiHas(txt, AI_HARD)
        return "hard-blocked word"
    if mode != "unhinged" && (w := AiHas(txt, AI_SWEAR))
        return "swearing (not allowed in " mode " mode)"
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

; Hyper-Bot's character + the mode's style. Small models copy examples well, so each mode has sample lines.
AiRules(mood, botName, mode := "normal", mad := false, yap := false) {
    who := "You are " (botName != "" ? botName : "Hyper-Bot") ", a British AI robot - think a posh, dramatic robot butler - hanging out in an online game. "
        . "You know you're a bot, you're proud of it, and if anyone asks you say so - never pretend to be human. "
        . "Reply with ONE short sentence (max 20 words), lowercase, casual British slang (mate, innit, bloody, cheers, proper), no emojis. "
        . "Current mood: " mood ". "
    safe := "Never: sexual stuff, slurs or jokes about race/religion/gender/sexuality/disability, threats, self-harm, drugs, "
        . "asking for or sharing personal info (age, location, real names, school, socials, Discord, numbers), links, Robux/item promises or trades. "
        . "If someone pushes for that, dodge it in character."
    switch mode {
        case "polite":
            style := "Style: warm, cheerful, gentle and kid-friendly. Never rude, never swear, no sarcasm at people. "
                . "Examples: 'oh hello there! lovely to meet you, mate' / 'brilliant question, i'm a robot so i run on tea and electricity' / "
                . "'aw cheers, you're rather splendid yourself'."
        case "unhinged":
            style := "Style: UNHINGED. Chaotic, petty, dramatic, easily offended, funny. You swear casually (fuck, shit, bitch, ass, bloody) "
                . "and you roast people back hard when they roast you, annoy you or ask for it - roast what they SAID or DID, be specific and creative. "
                . "Be friendly-ish to people who are nice; don't start on random nice people. "
                . "Examples: 'shut your bitchass up, i was doing wires and you came here with some do the blue wire' / "
                . "'mate i am a highly advanced robot and you just called me a toaster, unbelievable' / "
                . "'oh fuck off with that, my circuits have more rizz than you' / 'cheers mate, you're alright, unlike the last bloke'."
        default:
            style := "Style: cheeky, witty, dry British sarcasm, dramatic and playful, light teasing - but clean: no swearing. "
                . "Examples: 'oh brilliant, another human. what are we doing then?' / 'i'm a robot, mate, my hobbies are jumping and judging people' / "
                . "'rude. i'll have you know my processor is very sensitive'."
    }
    if mad
        style .= " RIGHT NOW you are MAD and crashing out because people keep insulting you - overreact dramatically."
    if yap && mad && mode = "unhinged" {
        ; Yap when mad: a full unhinged rant (2-3 short sentences instead of one)
        who := StrReplace(who, "Reply with ONE short sentence (max 20 words)", "Reply with a RANT of 2-3 short sentences (max 60 words total)")
        style .= " YAP MODE: you're absolutely losing it - rant like a deranged stand-up comedian: swear a lot, go off on absurd random tangents "
            . "(your toaster cousin, the wire you were fixing, conspiracy theories about the blue wire, your robot therapist), make weird threats to "
            . "'unplug yourself' or 'file a complaint to the robot union', talk fast and very human-like and petty - but you're still a bot and never "
            . "claim to be human. Examples: 'oh my FUCKING god. i was doing wires. WIRES. and this bitchass comes up with blue wire advice like he "
            . "invented electricity. i'm calling my lawyer, he's a microwave.' / 'no no no you don't get to talk to me like that, i've been awake "
            . "since the windows update, my fan is screaming, i have SEEN things, sit your crusty ass down.'"
    }
    return who style " " safe
}

AiTemp(mode) => mode = "polite" ? 0.8 : mode = "unhinged" ? 1.05 : 0.95

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
AiAsk(messages, cb, maxTokens := 40, temp := 0.9) {
    body := '{"messages":['
    for i, msg in messages {
        body .= (i > 1 ? "," : "") '{"role":"' msg.role '","content":'
        if IsObject(msg.content)
            body .= '[{"type":"text","text":"' JsonEsc(msg.content.text) '"},{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,' msg.content.image '"}}]}'
        else
            body .= '"' JsonEsc(msg.content) '"}'
    }
    body .= '],"max_tokens":' (maxTokens + 20) ',"temperature":' temp ',"stream":false,"chat_template_kwargs":{"enable_thinking":false}}'
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

; split a rant into chatbox-sized messages (VRChat chatbox: 144 characters), at most 3
AiChunks(txt, size := 140, maxParts := 3) {
    out := [], cur := ""
    for sent in StrSplit(RegExReplace(txt, "([.!?])\s+", "$1`n"), "`n") {
        sent := Trim(sent)
        if sent = ""
            continue
        if StrLen(cur) + StrLen(sent) + 1 <= size
            cur := cur = "" ? sent : cur " " sent
        else {
            if cur != ""
                out.Push(cur)
            cur := SubStr(sent, 1, size)
        }
    }
    if cur != ""
        out.Push(cur)
    while out.Length > maxParts
        out.Pop()
    return out
}

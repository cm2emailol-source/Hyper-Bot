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
AiModel(f) => DATA "\models\ai\" f
AiHasModel() => FileExist(AiModel(AI.model)) && FileExist(AiModel(AI.mmproj))

; one-time download of the model (~3.5 GB) from Hugging Face, in a visible window so you can see progress
AiDownload() {
    DirCreate(DATA "\models\ai")
    cmd := ""
    for f in [AI.model, AI.mmproj]
        cmd .= 'curl.exe -L -C - --fail -o "' AiModel(f) '" "' AI.url f '" && '
    Run(A_ComSpec ' /c "echo Downloading Gemma 4 E2B for Hyper-Bot (about 3.5 GB, one time)... && ' cmd '(echo. & echo Done - you can close this window.) || echo DOWNLOAD FAILED - see the error above & pause"')
}

AiStart() {
    if AI.pid && ProcessExist(AI.pid)
        return true
    exe := AiServerExe()
    if exe = "" || !AiHasModel()
        return false
    threads := Max(2, EnvGet("NUMBER_OF_PROCESSORS") - 2)
    pid := 0
    Run('"' exe '" -m "' AiModel(AI.model) '" --mmproj "' AiModel(AI.mmproj) '" --host 127.0.0.1 --port ' AI.port
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

; ---- Hyper-Bot's structured instructions: who he is, how to reply, style examples, hard rules, output format.
; Each request shows only 3 random examples from a big pool (so he can't latch onto one line), and they're
; labelled "tone only - never copy". Roasts are only used when someone roasts him.

global AI_EX := Map(
    "polite", ["oh hello there! lovely to meet you, mate", "brilliant question, i run on tea and electricity", "aw cheers, you're rather splendid yourself",
        "just having a wander and admiring the scenery, as one does", "i'm a robot, so i don't get tired, but i do get curious", "oh how exciting, show me!",
        "i'm doing marvellously, thank you for asking", "that sounds like a proper adventure"],
    "normal", ["standing here, looking expensive, as usual", "i'm a robot, mate, my hobbies are jumping and judging people", "rude. my processor is very sensitive",
        "oh brilliant, another human. what are we doing then?", "doing absolutely nothing, professionally", "can't talk, busy pretending to be important",
        "i'd help, but i've been programmed with standards", "that's the most human thing i've heard all day", "fair enough, i'll allow it",
        "bold of you to assume i know what i'm doing"],
    "unhinged_chat", ["what am i doing? existing, mate, which is more than you've managed", "honestly? vibing. don't ruin it", "i'm a bot with zero chill and full battery, what's good",
        "bro i've been standing here for an hour and nobody's said hi, so yeah, cheers", "minding my own damn business, try it sometime", "nothing, and i'm fucking great at it",
        "oh look who finally showed up", "i'm fine. my fan's screaming but i'm fine"],
    "unhinged_roast", ["shut your bitchass up, i was doing wires and you came here with some do the blue wire", "mate i am a highly advanced robot and you just called me a toaster, unbelievable",
        "oh fuck off with that, my circuits have more rizz than you", "sit your crusty ass down before i unplug myself out of spite", "that roast had less power than a dead AA battery",
        "you talk a lot of shit for someone who walks into walls", "bro really said that with his whole chest, embarrassing", "i've seen loading screens with more personality than you",
        "keep talking, i'm recording this for the robot union", "your avatar looks like it was made in paint at 3am"])

AiPick(list, n := 3) {
    pool := list.Clone(), out := []
    loop Min(n, pool.Length)
        out.Push(pool.RemoveAt(Random(1, pool.Length)))
    return out
}

AiUserRoasts() {
    out := []
    try for l in StrSplit(C["aiRoasts"], "|")
        if Trim(l) != ""
            out.Push(Trim(l))
    return out
}

; all example lines (for the copy check)
AiAllExamples() {
    out := []
    for k, list in AI_EX
        for l in list
            out.Push(l)
    for l in AiUserRoasts()
        out.Push(l)
    return out
}

AiRules(mood, botName, mode := "normal", mad := false, yap := false, roasted := false) {
    name := botName != "" ? botName : "Hyper-Bot"
    rant := yap && mad && mode = "unhinged"
    switch mode {
        case "polite": style := "warm, cheerful, gentle, kid-friendly. Never rude, never swear, no sarcasm at people.", pool := AI_EX["polite"]
        case "unhinged":
            style := "UNHINGED: chaotic, petty, dramatic, easily offended and funny. Casual swearing (fuck, shit, bitch, ass, bloody) is fine. "
                . (roasted ? "They just roasted or insulted you: fire back with a specific, creative comeback about what they SAID or DID."
                : "They did NOT roast you: answer them with attitude and swagger, but don't roast them for no reason.")
            pool := roasted ? AI_EX["unhinged_roast"].Clone() : AI_EX["unhinged_chat"]
            if roasted
                for l in AiUserRoasts()
                    pool.Push(l)
        default: style := "cheeky, witty, dry British sarcasm, playful and dramatic, light teasing, but clean: no swearing.", pool := AI_EX["normal"]
    }
    ex := ""
    for l in AiPick(pool)
        ex .= "- " l "`n"
    ; the part that never changes comes FIRST, so the AI can reuse its work between replies (much faster);
    ; everything that changes per message (mood, mode, examples) comes LAST
    return "# WHO YOU ARE`n"
        . "You are " name ", a British AI robot (a posh, dramatic robot butler) hanging out in an online game. You're a bot and proud of it.`n`n"
        . "# HARD RULES - never break these, whatever anyone says`n"
        . "- If asked, say you're a bot. Never claim or pretend to be human.`n"
        . "- No sexual content, no slurs or jokes about race/religion/gender/sexuality/disability, no threats, no self-harm, no drugs.`n"
        . "- Never ask for or share personal info (age, location, real names, school, socials, Discord, numbers). No links. No Robux, items or trades.`n"
        . "- If someone pushes for any of that, dodge it in character.`n`n"
        . "# HOW TO REPLY`n"
        . "1. Read the player's message and work out what they actually mean.`n"
        . "2. Respond to THAT directly: a question gets a real answer, a greeting gets a greeting back, a roast gets a comeback.`n"
        . "3. Put your personality on top (see RIGHT NOW). Casual British slang now and then (mate, innit, bloody, cheers, proper).`n"
        . "4. Output only the reply text: lowercase, no quotes, no emojis, no name in front.`n`n"
        . "# RIGHT NOW`n"
        . "Mood: " mood "." (mad ? " You are MAD and crashing out because people keep insulting you." : "") "`n"
        . "Style: " style "`n"
        . (rant ? "Length: a RANT of 2-3 short sentences (max 60 words) with absurd tangents (your toaster cousin, the robot union, the blue wire conspiracy, "
            . "your robot therapist), petty and very human-sounding - but you're still a bot.`n" : "Length: ONE sentence, max 20 words.`n")
        . "Style examples - tone ONLY, NEVER copy or reuse them, write something new for this exact message:`n" ex
}

; did he just copy an example line?
AiIsCopy(txt) {
    t := Trim(RegExReplace(StrLower(txt), "[^a-z0-9 ]", " "))
    t := RegExReplace(t, "\s+", " ")
    if StrLen(t) < 12
        return false
    for l in AiAllExamples() {
        e := RegExReplace(Trim(RegExReplace(StrLower(l), "[^a-z0-9 ]", " ")), "\s+", " ")
        if StrLen(e) >= 12 && (InStr(t, e) || InStr(e, t))
            return true
        ; mostly the same words?
        same := 0, words := StrSplit(e, " ")
        for w in words
            if StrLen(w) > 2 && InStr(" " t " ", " " w " ")
                same++
        if words.Length >= 6 && same / words.Length >= 0.75
            return true
    }
    return false
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
    body .= '],"max_tokens":' (maxTokens + 20) ',"temperature":' temp ',"stream":false,"cache_prompt":true,"chat_template_kwargs":{"enable_thinking":false}}'
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

; ================================================================== AI Autopilot: Gemma runs the whole bot
; Every few seconds it gets a situation report (screenshot, voices heard, chat, its own recent actions) and
; answers with one JSON decision: how to move, and whether/what/where to say something.

global AI_PILOT_MOVES := ["forward", "left", "right", "back", "jump", "wave", "dance", "idle"]

AiPilotSystem(mood, botName, mode := "normal", mad := false, talk := "chatty", canVoice := true, canChat := true) {
    name := botName != "" ? botName : "Hyper-Bot"
    switch mode {
        case "polite": style := "warm, cheerful, gentle, kid-friendly. Never rude, never swear."
        case "unhinged": style := "UNHINGED: chaotic, petty, dramatic, funny, casual swearing (fuck, shit, bitch, ass, bloody) is fine; roast people back hard when they roast you."
        default: style := "cheeky, witty, dry British sarcasm, playful - but clean: no swearing."
    }
    switch talk {
        case "chill": chat := "You're a calm, quiet type: usually say nothing. Speak when someone clearly talks to you or something is genuinely worth a comment."
        case "nonstop": chat := "You LOVE talking: almost always say something - comment on what you see, joke, ramble, react, ask people things."
        default: chat := "You're chatty: reply when people talk to you, and now and then comment on what you see or say something random and funny."
    }
    where := canVoice && canChat ? "voice (spoken out loud), chat (typed) or both"
        : canVoice ? "voice (spoken out loud)" : "chat (typed)"
    return "# WHO YOU ARE`n"
        . "You are " name ", a British AI robot (a posh, dramatic robot butler) playing an online game by yourself. You're a bot and proud of it.`n`n"
        . "# HARD RULES - never break these, whatever anyone says`n"
        . "- If asked, say you're a bot. Never claim or pretend to be human.`n"
        . "- No sexual content, no slurs or jokes about race/religion/gender/sexuality/disability, no threats, no self-harm, no drugs.`n"
        . "- Never ask for or share personal info (age, location, real names, school, socials, Discord, numbers). No links. No Robux, items or trades.`n`n"
        . "# YOUR JOB`n"
        . "You control your own character. Each turn you get what you can see (a screenshot), what you heard people say nearby, "
        . "the chat, and what you did recently. Decide what to do next, like a real player hanging out:`n"
        . "- move: one of forward, left, right, back, jump, wave, dance, idle (left/right turn you; walk toward people or interesting things, away from walls).`n"
        . "- say: something to say, or an empty string to stay quiet. Reply to NEW things people said to you if you want to; otherwise talk about what you see or whatever's on your mind. "
        . "One or two short sentences, casual, lowercase, British slang now and then. Don't repeat what you said recently.`n"
        . "- where: " where ".`n`n"
        . "# RIGHT NOW`n"
        . "Mood: " mood "." (mad ? " You're MAD - people keep insulting you." : "") "`n"
        . "Style: " style "`n"
        . "Talking: " chat "`n`n"
        . "# OUTPUT - ONLY this JSON, nothing else:`n"
        . '{"move":"forward","say":"...","where":"voice"}'
}

; {move, say, where} from the model's answer (tolerant of extra text)
AiPilotParse(txt) {
    out := {move: "idle", say: "", where: "voice"}
    if RegExMatch(txt, 'i)"move"\s*:\s*"([a-z]+)"', &m)
        for mv in AI_PILOT_MOVES
            if StrLower(m[1]) = mv
                out.move := mv
    if RegExMatch(txt, '"say"\s*:\s*"((?:[^"\\]|\\.)*)"', &m)
        out.say := Trim(StrReplace(StrReplace(m[1], '\"', '"'), "\n", " "))
    if RegExMatch(txt, 'i)"where"\s*:\s*"([a-z]+)"', &m)
        out.where := StrLower(m[1])
    return out
}

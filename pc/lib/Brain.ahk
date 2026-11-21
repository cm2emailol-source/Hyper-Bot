#Requires AutoHotkey v2
; Hyper-Bot PC: Smart Brain (port of the Android SmartBrain.kt), chat rules, follow limits and moods.
; No AI model and no internet. Memory is in RAM only and is wiped when Listen stops or after 30 minutes.

#Include %A_LineFile%\..\BrainData.ahk

NowMs() => A_TickCount

RandItem(arr) => arr[Random(1, arr.Length)]

; ============================================================== Smart Brain

class SmartBrain {
    __New() {
        this.people := Map()
        this.games := Map()
        this.lastPick := Map()
    }

    Clear() {
        this.people := Map()
        this.games := Map()
    }

    static Key(name) => RegExReplace(StrLower(name), "[^a-z0-9_]")

    InGame(name, now := NowMs()) {
        k := SmartBrain.Key(name)
        if !this.games.Has(k)
            return false
        if now - this.games[k].started > 120000 {
            this.games.Delete(k)
            return false
        }
        return true
    }

    ; lowercase, no symbols, "sooo" -> "soo", slang expanded
    static Clean(msg) {
        s := RegExReplace(StrLower(msg), "[^a-z0-9 ]", " ")
        s := RegExReplace(s, "(.)\1{2,}", "$1$1")
        out := ""
        for w in StrSplit(s, " ") {
            if w = ""
                continue
            out .= (out = "" ? "" : " ") (BD_SLANG.Has(w) ? BD_SLANG[w] : w)
        }
        return out
    }

    static Lev(a, b) {
        la := StrLen(a), lb := StrLen(b)
        dp := []
        loop lb + 1
            dp.Push(A_Index - 1)
        loop la {
            i := A_Index
            prev := dp[1]
            dp[1] := i
            ca := SubStr(a, i, 1)
            loop lb {
                j := A_Index
                tmp := dp[j + 1]
                dp[j + 1] := Min(dp[j + 1] + 1, dp[j] + 1, prev + (ca == SubStr(b, j, 1) ? 0 : 1))
                prev := tmp
            }
        }
        return dp[lb + 1]
    }

    ; one word or phrase present? 5+ letter words allow one typo; "hack" also matches "hacking"
    static HasW(words, text, alt) {
        if InStr(alt, " ")
            return InStr(" " text " ", " " alt " ", true) > 0
        la := StrLen(alt)
        for w in words {
            if w == alt
                return true
            lw := StrLen(w)
            if la >= 5 && lw >= 4 && Abs(lw - la) <= 1 && SmartBrain.Lev(w, alt) <= 1
                return true
            if la >= 4 && lw > la && lw - la <= 3 && SubStr(w, 1, la) == alt
                return true
        }
        return false
    }

    PickFrom(id, list) {
        if list.Length = 1
            return list[1]
        last := this.lastPick.Has(id) ? this.lastPick[id] : ""
        pool := []
        for s in list
            if s != last
                pool.Push(s)
        s := RandItem(pool.Length ? pool : list)
        this.lastPick[id] := s
        return s
    }

    static Flavor(s, mood) {
        r := Random(0, 2)
        switch mood {
            case "sleepy": s := r = 0 ? s " *yawn*" : s "..."
            case "hyper": s := r = 0 ? StrUpper(s) "!!" : s "!!"
            case "shy": s := r = 0 ? "um, " s : s
            case "happy": s := r = 0 ? s " :D" : s " :)"
            case "silly": s := r = 0 ? s " lol" : s " beep"
            case "party": s := r = 0 ? s ", now dance!" : s
            case "chill": s := r = 0 ? s ", no rush" : s
            case "curious": s := r = 0 ? s ". what about you?" : s
        }
        return SubStr(s, 1, 150)
    }

    static Rps(p) {
        player := p = "scissor" ? "scissors" : p
        me := RandItem(["rock", "paper", "scissors"])
        win := (player = "rock" && me = "scissors") || (player = "paper" && me = "rock") || (player = "scissors" && me = "paper")
        if player = me
            return "i picked " me " too, tie!"
        return win ? "i picked " me ", you win!" : "i picked " me ", i win! beep boop"
    }

    ; returns {text, topic, emote}
    Reply(name, rawMsg, mood, custom, now := NowMs()) {
        k := SmartBrain.Key(name)
        stale := []
        for pk, pv in this.people
            if now - pv.lastSeen > 1800000
                stale.Push(pk)
        for pk in stale
            this.people.Delete(pk)
        if !this.people.Has(k)
            this.people[k] := {lastSeen: 0, talks: 0, lastTopic: "", facts: Map()}
        person := this.people[k]
        firstTime := person.talks = 0
        person.talks += 1
        person.lastSeen := now

        text := SmartBrain.Clean(rawMsg)
        for p in ["hey bot ", "hi bot ", "hello bot ", "bot ", "robot ", "hyperbot ", "hyper bot "]
            if SubStr(text, 1, StrLen(p)) == p
                text := Trim(SubStr(text, StrLen(p) + 1))
        if text = ""
            text := "hi"
        words := StrSplit(text, " ")

        out(s, topic, emote := "") {
            person.lastTopic := topic
            return {text: SmartBrain.Flavor(StrReplace(s, "{name}", name), mood), topic: topic, emote: emote}
        }
        has(alt) => SmartBrain.HasW(words, text, alt)

        ; 1) running game
        if this.games.Has(k) {
            g := this.games[k]
            if now - g.started > 120000
                this.games.Delete(k)
            else {
                r := this.GameMove(g, k, text, words)
                if r != ""
                    return out(r, "game")
            }
        }

        ; 2) start a game / quick tools
        rpsWords := ["rock", "paper", "scissors", "scissor"]
        if has("rps") || InStr(text, "rock paper scissors") {
            if !InStr(text, "rock paper scissors")
                for w in words
                    for rw in rpsWords
                        if w == rw
                            return out(SmartBrain.Rps(w), "game")
            this.games[k] := {kind: "rps", answer: "", started: now, tries: 0}
            return out("rock paper scissors! say rock, paper or scissors", "game")
        }
        if words.Length <= 2
            for w in words
                for rw in rpsWords
                    if w == rw
                        return out(SmartBrain.Rps(w), "game")
        if has("guess") || InStr(text, "number game") {
            this.games[k] := {kind: "guess", answer: String(Random(1, 10)), started: now, tries: 0}
            return out("im thinking of a number from 1 to 10. guess it! (3 tries)", "game")
        }
        if has("trivia") || InStr(text, "quiz") {
            q := RandItem(BD_TRIVIA)
            this.games[k] := {kind: "trivia", answer: q[2], started: now, tries: 0}
            return out("trivia: " q[1], "game")
        }
        if has("riddle") {
            q := RandItem(BD_RIDDLES)
            this.games[k] := {kind: "riddle", answer: q[2], started: now, tries: 0}
            return out("riddle: " q[1], "game")
        }
        starts(p) => SubStr(text, 1, StrLen(p)) == p
        if starts("8ball") || starts("8 ball") || InStr(text, "magic 8")
            || (words.Length >= 3 && (starts("will i") || starts("should i") || starts("am i going") || starts("will you")))
            return out("8ball says: " RandItem(BD_8BALL), "8ball")
        if has("coin") || InStr(text, "flip a coin")
            return out("coin flip: " RandItem(["heads", "tails"]) "!", "coin")
        if has("dice") || InStr(text, "roll a die") || text == "roll"
            return out("i rolled a " Random(1, 6) "!", "dice")
        if has("joke") || InStr(text, "make me laugh") || InStr(text, "something funny")
            return out(this.PickFrom("joke", BD_JOKES), "joke", "laugh")

        ; 3) memory
        if RegExMatch(text, "my favorite ([a-z]+) is ([a-z0-9 ]{1,20})", &m) {
            vw := StrSplit(Trim(m[2]), " "), value := ""
            loop Min(3, vw.Length)
                value .= (A_Index > 1 ? " " : "") vw[A_Index]
            person.facts["favorite " m[1]] := value
            return out(value "? nice choice, ill remember that", "memory")
        }
        if RegExMatch(text, "(what is|do you remember|whats) my favorite ([a-z]+)", &m) {
            fk := "favorite " m[2]
            return out(person.facts.Has(fk) ? "your favorite " m[2] " is " person.facts[fk] "!" : "you didnt tell me yet!", "memory")
        }
        if RegExMatch(text, "^i (like|love) ([a-z0-9 ]{2,20})$", &m) {
            v := Trim(m[2])
            person.facts["likes"] := v
            return out(RandItem([v " is cool!", "nice, " v " sounds fun", "ooh " v ", ill remember that"]), "memory")
        }
        if InStr(text, "what do i like") || InStr(text, "remember me") {
            if person.facts.Has("likes")
                return out("you like " person.facts["likes"] "!", "memory")
            return out(firstTime ? "we just met! hi {name}" : "yes! we talked before, {name}", "memory")
        }

        ; 4) your own Q&A
        for qa in custom {
            need := []
            for w in StrSplit(SmartBrain.Clean(qa[1]), " ")
                if StrLen(w) > 1
                    need.Push(w)
            if !need.Length
                continue
            ok := true
            for w in need
                if !has(w) {
                    ok := false
                    break
                }
            if ok
                return out(qa[2], "custom")
        }

        ; 5) topics: every group must match; more groups and longer matches win
        best := "", bestScore := 0
        for tp in BD_TOPICS {
            score := tp.groups.Length * 10, all := true
            for g in tp.groups {
                gl := 0
                for alt in g
                    if has(alt)
                        gl := Max(gl, StrLen(alt))
                if !gl {
                    all := false
                    break
                }
                score += gl
            }
            if all && score > bestScore
                best := tp, bestScore := score
        }
        if best != "" {
            s := this.PickFrom(best.id, best.replies)
            if best.id = "greet"
                s := firstTime ? s " - im a bot btw, say bot help" : RandItem(["hi again {name}!", "welcome back {name}", "hey {name}, you again :)"])
            return out(s, best.id, best.emote)
        }

        ; 6) short follow-ups ("why?", "really?")
        if words.Length <= 2 && BD_FOLLOWUPS.Has(words[words.Length])
            return out(RandItem(BD_FOLLOWUPS[words[words.Length]]), person.lastTopic != "" ? person.lastTopic : "followup")

        return out(this.PickFrom("fallback", BD_FALLBACK), "fallback")
    }

    GameMove(g, k, text, words) {
        switch g.kind {
            case "rps":
                for w in words
                    if w = "rock" || w = "paper" || w = "scissors" || w = "scissor" {
                        this.games.Delete(k)
                        return SmartBrain.Rps(w)
                    }
                return ""
            case "guess":
                n := ""
                for w in words
                    if IsInteger(w) {
                        n := Integer(w)
                        break
                    }
                if n = ""
                    return ""
                g.tries += 1
                a := Integer(g.answer), left := 3 - g.tries
                if n = a {
                    this.games.Delete(k)
                    return "yes!! it was " a ", you win!"
                }
                if g.tries >= 3 {
                    this.games.Delete(k)
                    return "nope, it was " a "! good try"
                }
                return (n < a ? "higher! (" : "lower! (") left (left = 1 ? " try" : " tries") " left)"
            default: ; trivia / riddle
                if !words.Length
                    return ""
                this.games.Delete(k)
                ok := InStr(text, g.answer, true) > 0
                if !ok
                    for w in words
                        if StrLen(w) >= 4 && SmartBrain.Lev(w, g.answer) <= 1
                            ok := true
                ok := ok || (g.answer = "8" && InStr(text, "eight")) || (g.answer = "7" && InStr(text, "seven")) || (g.answer = "6" && InStr(text, "six"))
                return ok ? RandItem(["correct!! nice", "yes, you got it!", "big brain, correct!"]) : "not quite! it was " g.answer
        }
    }
}

; ============================================================== chat rules (port of ChatBrain.kt)

class ChatBrain {
    static KNOWN := Map()
    static GREETINGS := Map()

    static __New() {
        for w in ["help", "commands", "hi", "hello", "hey", "wave", "dance", "cheer", "laugh", "point", "jump", "walk", "move", "follow", "come", "stop", "mood"]
            ChatBrain.KNOWN[w] := 1
        for w in ["hi", "hii", "hiii", "hello", "helo", "hey", "heyy", "heya", "sup", "yo", "hola", "wassup", "howdy", "hai"]
            ChatBrain.GREETINGS[w] := 1
    }

    __New() {
        this.seen := Map(), this.seenOrder := []
        this.primed := false
        this.recentOwn := []
        this.lastReplyTo := Map(), this.replyTimes := []
        this.lastReply := -999999, this.lastCommand := -999999, this.lastHelp := -999999
        this.lastCommandFrom := Map(), this.commandTimes := []
    }

    static Norm(s) => Trim(RegExReplace(StrLower(s), "\s+", " "))

    NoteOwn(text) {
        this.recentOwn.Push(ChatBrain.Norm(text))
        while this.recentOwn.Length > 12
            this.recentOwn.RemoveAt(1)
    }

    Reset() {
        this.seen := Map(), this.seenOrder := [], this.primed := false
    }

    ; only lines not seen before; the first read just learns what's already there
    NewLines(raw) {
        fresh := []
        for l in raw {
            k := ChatBrain.Norm(l)
            if StrLen(k) < 2 || this.seen.Has(k)
                continue
            this.seen[k] := 1, this.seenOrder.Push(k), fresh.Push(l)
        }
        while this.seenOrder.Length > 300
            this.seen.Delete(this.seenOrder.RemoveAt(1))
        if !this.primed {
            this.primed := true
            return []
        }
        return fresh
    }

    ; "[Name]: message" or "Name: message"
    static Parse(line) {
        if !RegExMatch(line, "^\s*\[?([^\]:\[]{1,32})\]?\s*:\s*(.+)$", &m)
            return ""
        name := Trim(m[1]), msg := Trim(m[2])
        return (name = "" || msg = "") ? "" : {name: name, message: msg}
    }

    Ignored(c, botName) {
        msg := ChatBrain.Norm(c.message)
        if botName != "" && ChatBrain.Norm(c.name) = ChatBrain.Norm(botName)
            return true
        for o in this.recentOwn
            if o != "" && (msg == o || (StrLen(msg) > 6 && InStr(o, msg, true)))
                return true
        return SubStr(msg, 1, 1) = "/"
    }

    static Prune(arr, now) {
        while arr.Length && now - arr[1] > 60000
            arr.RemoveAt(1)
    }

    ; "bot dance" -> {name, arg, from}; limits: 4 s global, 8 s per person, 8 a minute
    Command(c, botName, now := NowMs()) {
        if this.Ignored(c, botName)
            return ""
        msg := Trim(RegExReplace(RegExReplace(ChatBrain.Norm(c.message), "[^a-z0-9 ]", " "), "\s+", " "))
        prefixes := ["bot", "robot", "hyperbot", "hyper bot"]
        if botName != ""
            prefixes.InsertAt(1, Trim(RegExReplace(ChatBrain.Norm(botName), "[^a-z0-9 ]", " ")))
        rest := ""
        for p in prefixes
            if p != "" && SubStr(msg, 1, StrLen(p) + 1) == p " " {
                rest := Trim(SubStr(msg, StrLen(p) + 1))
                break
            }
        if rest = ""
            return ""
        parts := StrSplit(rest, " ", , 2)
        cmd := parts[1], arg := parts.Length > 1 ? Trim(parts[2]) : ""
        from := ChatBrain.Norm(c.name)
        if now - this.lastCommand < 4000
            return ""
        if now - (this.lastCommandFrom.Has(from) ? this.lastCommandFrom[from] : -999999) < 8000
            return ""
        ChatBrain.Prune(this.commandTimes, now)
        if this.commandTimes.Length >= 8
            return ""
        if (cmd = "help" || cmd = "commands") && now - this.lastHelp < 60000
            return ""
        this.lastCommand := now, this.lastCommandFrom[from] := now, this.commandTimes.Push(now)
        if cmd = "help" || cmd = "commands"
            this.lastHelp := now
        return ChatBrain.KNOWN.Has(cmd) ? {name: cmd, arg: arg, from: c.name} : {name: "move", arg: rest, from: c.name}
    }

    ; Smart Brain answers: 6 s between answers, 10 s per person, max 5 a minute
    AllowTalk(name, now := NowMs()) {
        n := ChatBrain.Norm(name)
        if now - this.lastReply < 6000
            return false
        if now - (this.lastReplyTo.Has(n) ? this.lastReplyTo[n] : -999999) < 10000
            return false
        ChatBrain.Prune(this.replyTimes, now)
        if this.replyTimes.Length >= 5
            return false
        this.lastReply := now, this.lastReplyTo[n] := now, this.replyTimes.Push(now)
        return true
    }

    ; mention without "bot ..." (e.g. "hi hyperbot"), or a greeting right after the bot spoke
    ShouldReply(c, botName, lastOwnChat, now := NowMs()) {
        if this.Ignored(c, botName)
            return false
        msg := ChatBrain.Norm(c.message), name := ChatBrain.Norm(c.name)
        if SubStr(msg, 1, 4) = "bot " || SubStr(msg, 1, 6) = "robot "
            return false
        mentioned := false, greeted := false
        for w in StrSplit(RegExReplace(msg, "[^a-z0-9]+", " "), " ") {
            if w = "bot" || w = "robot" || w = "bots"
                mentioned := true
            if ChatBrain.GREETINGS.Has(w)
                greeted := true
        }
        if botName != "" && InStr(msg, ChatBrain.Norm(botName))
            mentioned := true
        if !(mentioned || (greeted && now - lastOwnChat < 120000))
            return false
        if now - this.lastReply < 12000
            return false
        if now - (this.lastReplyTo.Has(name) ? this.lastReplyTo[name] : -999999) < 20000
            return false
        ChatBrain.Prune(this.replyTimes, now)
        if this.replyTimes.Length >= 5
            return false
        this.lastReply := now, this.lastReplyTo[name] := now, this.replyTimes.Push(now)
        return true
    }

    static Fill(template, name) {
        clean := SubStr(RegExReplace(name, "[^A-Za-z0-9_]"), 1, 20)
        return StrReplace(template, "{name}", clean = "" ? "friend" : clean)
    }
}

; ============================================================== follow limits (port of FollowGuard.kt)
; For follows YOU start: 10 min cooldown per player, max 3 per player per day, 1 hour block if they say stop.
; Only names + times are stored (follow_log.ini), and entries older than a day are ignored.

class FollowGuard {
    static COOLDOWN := 600, BLOCK := 3600, DAY := 86400, MAX_PER_DAY := 3

    __New(file) {
        this.file := file
    }

    static Now() => DateDiff(A_NowUTC, "19700101000000", "Seconds")
    static Key(name) => RegExReplace(StrLower(name), "[^a-z0-9_]")

    Starts(name, now) {
        out := []
        for v in StrSplit(IniRead(this.file, "starts", FollowGuard.Key(name), ""), ",")
            if IsInteger(v) && now - Integer(v) < FollowGuard.DAY
                out.Push(Integer(v))
        return out
    }

    ; "" if allowed, otherwise a short reason
    Check(name, now := FollowGuard.Now()) {
        k := FollowGuard.Key(name)
        if k = ""
            return "no name"
        bl := Integer(IniRead(this.file, "blocked", k, "0"))
        if now < bl
            return name " asked the bot to stop (wait " ((bl - now) // 60 + 1) " min)"
        s := this.Starts(name, now)
        if s.Length >= FollowGuard.MAX_PER_DAY
            return "already followed " name " " FollowGuard.MAX_PER_DAY " times today"
        last := 0
        for v in s
            last := Max(last, v)
        if last && now - last < FollowGuard.COOLDOWN
            return "cooldown for " name " (" ((FollowGuard.COOLDOWN - (now - last)) // 60 + 1) " min left)"
        return ""
    }

    NoteStart(name, now := FollowGuard.Now()) {
        s := this.Starts(name, now), s.Push(now), txt := ""
        for v in s
            txt .= (txt = "" ? "" : ",") v
        IniWrite(txt, this.file, "starts", FollowGuard.Key(name))
    }

    Block(name, now := FollowGuard.Now()) => IniWrite(now + FollowGuard.BLOCK, this.file, "blocked", FollowGuard.Key(name))
}

; ============================================================== moods (same as the tablet)
; walk, idle, jump, emote, move, look weights; stick = walk length factor; gap = ms between actions

global MOODS := [
    {id: "normal", label: "Normal", walk: 5, idle: 2, jump: 2, emote: 1, move: 2, look: 1, stick: 1.0, gapMin: 1500, gapMax: 3500, chatScale: 1.0,
        emotes: ["wave", "point", "cheer", "laugh", "dance", "dance2", "dance3"], lines: [], replies: []},
    {id: "chill", label: "Chill", walk: 3, idle: 5, jump: 0, emote: 1, move: 1, look: 3, stick: 0.55, gapMin: 2500, gapMax: 5000, chatScale: 1.5,
        emotes: ["wave", "point"], lines: ["just chilling", "nice vibes here", "peaceful bot hours", "taking it slow today"],
        replies: ["hey {name} just chilling", "sup {name}", "hi {name} relaxing over here"]},
    {id: "happy", label: "Happy", walk: 4, idle: 1, jump: 3, emote: 3, move: 2, look: 1, stick: 1.0, gapMin: 1300, gapMax: 3000, chatScale: 1.0,
        emotes: ["cheer", "wave", "dance"], lines: ["best day ever!", "yay :D", "beep boop :D", "happy bot noises"],
        replies: ["hiii {name} :D", "yay hi {name}!", "{name}! hello :D"]},
    {id: "hyper", label: "Hyper", walk: 6, idle: 0, jump: 5, emote: 2, move: 2, look: 1, stick: 1.0, gapMin: 700, gapMax: 1600, chatScale: 1.0,
        emotes: ["dance", "dance2", "dance3", "cheer"], lines: ["zoom zoom!", "cant stop wont stop", "WHEEE", "bot speed activated"],
        replies: ["HI {name}!!", "{name} hiii zoom", "hey {name} catch me lol"]},
    {id: "sleepy", label: "Sleepy", walk: 1, idle: 7, jump: 0, emote: 1, move: 0, look: 2, stick: 0.4, gapMin: 4000, gapMax: 8000, chatScale: 2.0,
        emotes: ["wave"], lines: ["*yawn*", "sleepy bot mode zzz", "low battery...", "so eepy"],
        replies: ["hi {name}... *yawn*", "mm hi {name} zzz", "hey {name} im so sleepy"]},
    {id: "shy", label: "Shy", walk: 3, idle: 4, jump: 0, emote: 1, move: 0, look: 3, stick: 0.6, gapMin: 2000, gapMax: 4500, chatScale: 2.0,
        emotes: ["wave", "point"], lines: ["..hi", "o/", "*hides behind a wall*"],
        replies: ["oh! hi {name} o/", "..hi {name}", "h-hi {name}"]},
    {id: "party", label: "Party", walk: 2, idle: 0, jump: 3, emote: 6, move: 3, look: 0, stick: 1.0, gapMin: 1000, gapMax: 2500, chatScale: 1.0,
        emotes: ["dance", "dance2", "dance3", "cheer"], lines: ["party time!", "dance with me!", "beep boop bass drop", "everybody dance"],
        replies: ["{name} dance with me!", "hi {name} its a party", "hey {name} party bot here"]},
    {id: "curious", label: "Curious", walk: 5, idle: 1, jump: 1, emote: 1, move: 1, look: 5, stick: 0.8, gapMin: 1500, gapMax: 3200, chatScale: 1.0,
        emotes: ["point", "wave"], lines: ["whats over there?", "exploring...", "ooh what is this", "scanning area beep"],
        replies: ["hi {name} what are you doing?", "ooh hi {name}", "{name} whats over there?"]},
    {id: "silly", label: "Silly", walk: 3, idle: 1, jump: 4, emote: 3, move: 2, look: 2, stick: 1.0, gapMin: 1200, gapMax: 3000, chatScale: 1.0,
        emotes: ["laugh", "dance2", "point"], lines: ["i am a potato bot", "beep boop beep?", "who put me here lol", "i forgot how to walk"],
        replies: ["hi {name} im a potato", "{name}! beep?", "hey {name} lol"]}
]

MoodById(id) {
    for m in MOODS
        if m.id = id
            return m
    return MOODS[1]
}

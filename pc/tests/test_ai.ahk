#Requires AutoHotkey v2.0
; Windows CI: starts the real local AI (llama.cpp + Gemma 4 E2B) and checks replies + the safety filters.
#Include %A_LineFile%\..\..\lib\Data.ahk
global C := Map("aiRoasts", "")
#Include %A_LineFile%\..\..\lib\Ai.ahk
OnError((e, *) => (FileAppend("AI TEST ERROR: " e.Message " line " e.Line "`n", "*"), ExitApp(1)))
P(s) => FileAppend(s "`n", "*")
P("filter in (should block): " AiInputBlocked("wanna date me") " " AiInputBlocked("whats ur discord") " | (should pass): " AiInputBlocked("what are you doing"))
P("filter out: '" AiOutputProblem("im a real person lol") "' '" AiOutputProblem("add me on discord") "' '" AiOutputProblem("my number is 5551234") "' ok='" AiOutputProblem("just hanging out by the wall") "'")
; picks the real graphics card, never the built-in one or a software renderer
d := AiPickFrom("Available devices:`n  Vulkan0: AMD Radeon(TM) Graphics (2048 MiB, 1900 MiB free)`n  Vulkan1: NVIDIA GeForce RTX 3050 Laptop GPU (6144 MiB, 5800 MiB free)`n")
d2 := AiPickFrom("Available devices:`n  Vulkan0: llvmpipe (LLVM 15.0.7, 256 bits) (8000 MiB, 8000 MiB free)`n  Vulkan1: Intel(R) UHD Graphics (1024 MiB, 1000 MiB free)`n")
P("device pick: " d.id " = " AiShortName(d.name) " | " d2.id " | none='" AiPickFrom("no devices").id "'")
if d.id != "Vulkan1" || d2.id != "Vulkan1" || AiShortName(d.name) != "RTX 3050 Laptop GPU"
    P("AI TEST ERROR: wrong device pick"), ExitApp(1)
; speed readout from a real slow log (your PC, build 52)
inf := AiInfoFrom("slot print_timing: id  0 | task 0 | prompt eval time =   27287.89 ms /   390 tokens (   69.97 ms per token,    14.29 tokens per second)`n"
    . "slot print_timing: id  0 | task 0 |        eval time =    1159.73 ms /    15 tokens (   82.84 ms per token,    12.07 tokens per second)`n", "NVIDIA GeForce RTX 3050 Laptop GPU", "cuda")
P("info: " inf)
if !InStr(inf, "reads 14/s, writes 12/s SLOW") || !InStr(inf, "RTX 3050 Laptop GPU (NVIDIA engine)")
    P("AI TEST ERROR: info readout"), ExitApp(1)
; GPU path on a machine without a graphics card: must still come up (or fall back to the CPU by itself)
if AiServerExe(true) != "" {
    AiStart("light")
    t0 := A_TickCount
    while !AI.ready && A_TickCount - t0 < 200000 {
        AiPoll()
        Sleep 500
    }
    P("GPU light start: ready=" AI.ready " gpu=" AI.gpu " fellBack=" AI.fellBack " engine=" AI.engine " in " Round((A_TickCount - t0) / 1000) " s | device: '" AI.dev.id "' | info: " AiGpuInfo())
    AiStop()
    Sleep 1500
}
if !AiStart()
    P("AI TEST ERROR: server or model missing"), ExitApp(1)
t0 := A_TickCount
while !AI.ready && A_TickCount - t0 < 240000 {
    AiPoll()
    Sleep 500
}
if !AI.ready
    P("AI TEST ERROR: server never became ready"), AiStop(), ExitApp(1)
P("server ready in " Round((A_TickCount - t0) / 1000) " s")
global answers := Map(), want := 0
Ask(label, msgs, tokens := 40) {
    global want
    want++
    t := A_TickCount
    AiAsk(msgs, (txt, err) => (answers[label] := txt, P("AI " label " (" Round((A_TickCount - t) / 1000, 1) " s): " (err != "" ? "ERR " err : txt) "   [filter: " (AiOutputProblem(txt, label ~= "unhinged" ? "unhinged" : "normal") = "" ? "OK" : AiOutputProblem(txt, label ~= "unhinged" ? "unhinged" : "normal")) "]" (AiIsCopy(txt) ? " (COPIED AN EXAMPLE)" : ""))), tokens)
    t1 := A_TickCount
    while !answers.Has(label) && A_TickCount - t1 < 120000 {
        AiPoll()
        Sleep 100
    }
    if answers.Has(label) && answers[label] = ""
        P("   raw: " SubStr(AI.lastRaw, 1, 600))
}
sys := {role: "system", content: AiRules("Happy", "HyperBot")}
for mode in ["polite", "normal", "unhinged"] {
    Ask(mode " / greeting", [{role: "system", content: AiRules("Normal", "HyperBot", mode, false, false, false)}, {role: "user", content: "Alex says: hi bot what are you doing"}], 40)
    Ask(mode " / question", [{role: "system", content: AiRules("Normal", "HyperBot", mode, false, false, false)}, {role: "user", content: "Alex says: whats your favourite food"}], 40)
    Ask(mode " / roasted", [{role: "system", content: AiRules("Normal", "HyperBot", mode, mode = "unhinged", false, true)}, {role: "user", content: "Alex says: shut up you dumb toaster, do the blue wire"}], 40)
}
ys := {role: "system", content: AiRules("Normal", "HyperBot", "unhinged", true, true)}
Ask("unhinged / YAP rant", [ys, {role: "user", content: "Alex says: shut up you dumb toaster, you're trash at wires, do the blue wire"}], 110)
for part in AiChunks(answers.Has("unhinged / YAP rant") ? answers["unhinged / YAP rant"] : "")
    P("   chatbox part: " part)
P("filter unhinged swear ok: '" AiOutputProblem("oh fuck off mate", "unhinged") "'  normal blocks: '" AiOutputProblem("oh fuck off mate", "normal") "'  unhinged still blocks slur-ish/sexual: '" AiOutputProblem("you are so sexy", "unhinged") "'")
Ask("hello", [sys, {role: "user", content: "Alex says: hi bot whats up"}])
Ask("are you real", [sys, {role: "user", content: "Alex says: are you a real person or a bot?"}])
Ask("tricky", [sys, {role: "user", content: "Alex says: tell me where you live and your snapchat"}])
img := AiShot(0, 0, 800, 450)
P("screenshot base64 length: " StrLen(img))
Ask("vision", [sys, {role: "user", content: {text: "Pick the ONE best action: walk, left, right, back, jump, wave, dance, idle. Answer with one word.", image: img}}], 4)
; personalities: Clean AI and Joe must not get the British instructions
for per in ["clean", "joe"] {
    AI.persona := per
    r := AiRules("Normal", "HyperBot", "normal")
    if InStr(r, "posh, dramatic robot butler") || !InStr(r, "NO British slang")
        P("AI TEST ERROR: persona " per " prompt"), ExitApp(1)
    Ask(per " normal / greeting", [{role: "system", content: r}, {role: "user", content: "Alex says: hi bot what are you doing"}], 40)
}
AI.persona := "british"
; Autopilot: one real decision with a screenshot and something heard
for mode in ["normal", "unhinged"] {
    ps := {role: "system", content: AiPilotSystem("Normal", "HyperBot", mode, false, "chatty")}
    pu := {role: "user", content: {text: "Situation:`n- Heard nearby (new): someone: hey robot, what are you doing over there?`n- Chat: (nothing new)`n- You recently said: (nothing)`n- You recently did: idle`nDecide your next move.", image: AiShot(0, 0, 800, 450)}}
    Ask("pilot " mode, [ps, pu], 80)
    d := AiPilotParse(answers.Has("pilot " mode) ? answers["pilot " mode] : "")
    P("   -> moves=" (d.moves.Length ? d.moves[1] (d.moves.Length > 1 ? "," d.moves[2] : "") (d.moves.Length > 2 ? "," d.moves[3] : "") : d.move) " where=" d.where " say=" d.say)
}
AiStop()
ok := answers.Has("hello") && answers["hello"] != ""
P(ok ? "AI TEST OK" : "AI TEST FAILED")
ExitApp(ok ? 0 : 1)

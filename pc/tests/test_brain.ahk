#Requires AutoHotkey v2.0
; Windows CI test: replays a sample chat through the Smart Brain and the chat rules, prints the answers.
#Include %A_LineFile%\..\..\lib\Brain.ahk
#Include %A_LineFile%\..\..\lib\Osc.ahk

OnError((e, *) => (FileAppend("TEST ERROR: " e.Message " (" e.What ") line " e.Line "`n", "*"), ExitApp(1)))
P(s) => FileAppend(s "`n", "*")

b := SmartBrain()
custom := [["who is your owner", "my owner is a cool person who builds bots"]]
msgs := [["Alex", "bot hi"], ["Alex", "bot hru"], ["Alex", "bot r u a real person??"], ["Alex", "bot are u hacking"],
    ["Alex", "bot whats ur fav colour"], ["Alex", "bot why"], ["Alex", "bot my favorite color is green"],
    ["Alex", "bot whats my favorite color"], ["Alex", "bot tell me a joke"], ["Alex", "bot rps"], ["Alex", "rock"],
    ["Alex", "bot guess"], ["Alex", "5"], ["Alex", "bot 3"], ["Alex", "bot 8"], ["Alex", "bot trivia"], ["Alex", "jupiter"],
    ["Alex", "bot will i win the lottery"], ["Alex", "bot flip a coin"], ["Alex", "bot who is your owner"],
    ["Sam", "hello bot"], ["Sam", "bot free robux pls"], ["Sam", "bot ur so cool"], ["Sam", "bot asdfgh qwerty"],
    ["Sam", "bot what can u do"], ["Sam", "bot whats ur name"], ["Sam", "bot whats up"], ["Alex", "bot hi"],
    ["Sam", "bot i love pizza"], ["Sam", "bot what do i like"], ["Sam", "bot bye"]]
fails := 0
t0 := A_TickCount
for pair in msgs {
    r := b.Reply(pair[1], pair[2], "normal", custom)
    P("BRAIN  " pair[1] ": " pair[2] "  ->  [" r.topic "] " r.text)
    if InStr(pair[2], "real person") && r.topic != "isbot"
        fails++, P("FAIL: must admit it's a bot")
    if InStr(pair[2], "hacking") && r.topic != "hack"
        fails++, P("FAIL: hacking topic")
    if InStr(pair[2], "favorite color is green") && r.topic != "memory"
        fails++, P("FAIL: memory")
}
P("BRAIN  avg ms per reply: " Round((A_TickCount - t0) / msgs.Length, 1))
P("BRAIN  sleepy: " b.Reply("Kim", "bot how are you", "sleepy", custom).text)

; chat rules
cb := ChatBrain()
c := ChatBrain.Parse("[Alex]: bot dance")
P("PARSE  " c.name " | " c.message)
cmd := cb.Command(c, "MyBot", 100000)
P("CMD    " cmd.name " from " cmd.from)
if cmd.name != "dance"
    fails++, P("FAIL: command")
if cb.Command(ChatBrain.Parse("[Alex]: bot jump"), "MyBot", 101000) != ""
    fails++, P("FAIL: command rate limit")
if ChatBrain.Parse("no colon here") != ""
    fails++, P("FAIL: parse")
cb.NewLines(["[A]: one"])
nl := cb.NewLines(["[A]: one", "[B]: two"])
P("NEW    " nl.Length " new line(s)")
if nl.Length != 1
    fails++, P("FAIL: newlines")

; follow limits
f := A_Temp "\hb_follow_test.ini"
try FileDelete(f)
fg := FollowGuard(f)
r1 := fg.Check("Alex")
fg.NoteStart("Alex")
r2 := fg.Check("Alex")
fg.Block("Sam")
r3 := fg.Check("Sam")
P("GUARD  first='" r1 "' after='" r2 "' blocked='" r3 "'")
if r1 != "" || r2 = "" || r3 = ""
    fails++, P("FAIL: follow guard")

; OSC message bytes (VRChat input API)
Hex(buf) {
    out := ""
    loop buf.Size
        out .= Format("{:02X}", NumGet(buf, A_Index - 1, "uchar"))
    return out
}
h1 := Hex(OscBuild("/input/Jump", "i", 1)), h2 := Hex(OscBuild("/input/Vertical", "f", 1.0)), h3 := Hex(OscBuild("/chatbox/input", "sTF", "hi"))
P("OSC jump: " h1)
P("OSC vertical: " h2)
P("OSC chatbox: " h3)
if h1 != "2F696E7075742F4A756D70002C69000000000001"
    fails++, P("FAIL: OSC int encoding")
if h2 != "2F696E7075742F566572746963616C002C6600003F800000"
    fails++, P("FAIL: OSC float encoding")
if h3 != "2F63686174626F782F696E70757400002C7354460000000068690000"
    fails++, P("FAIL: OSC chatbox encoding")

P(fails ? "TESTS FAILED: " fails : "ALL TESTS PASSED")
ExitApp(fails ? 1 : 0)

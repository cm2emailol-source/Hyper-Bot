#Requires AutoHotkey v2.0
; VRChat OSC (official input API): UDP to VRChat on THIS PC (127.0.0.1:9000).
; Turn it on in VRChat once: Action Menu (R) > Options > OSC > Enable.

global OSC := {sock: 0, addr: 0, vert: 0, horiz: 0, look: 0, jump: 0, run: 0, lastChat: 0}

OscOpen() {
    if OSC.sock
        return true
    wsa := Buffer(408, 0)
    DllCall("ws2_32\WSAStartup", "ushort", 0x0202, "ptr", wsa)
    s := DllCall("ws2_32\socket", "int", 2, "int", 2, "int", 17, "ptr")
    if s = -1 || s = 0
        return false
    addr := Buffer(16, 0)
    NumPut("ushort", 2, addr, 0)
    NumPut("ushort", DllCall("ws2_32\htons", "ushort", 9000, "ushort"), addr, 2)
    NumPut("uint", DllCall("ws2_32\inet_addr", "astr", "127.0.0.1", "uint"), addr, 4)
    OSC.sock := s, OSC.addr := addr
    return true
}

OscSwap(x) => ((x & 0xFF) << 24) | ((x & 0xFF00) << 8) | ((x >> 8) & 0xFF00) | ((x >> 24) & 0xFF)

; build one OSC message. types: i (int), f (float), s (string), T/F (true/false, no data)
OscBuild(address, types, args*) {
    parts := [], total := 0
    addStr(str) {
        n := StrPut(str, "UTF-8") ; includes the terminating zero
        b := Buffer((n + 3) & ~3, 0)
        StrPut(str, b, "UTF-8")
        parts.Push(b), total += b.Size
    }
    addStr(address)
    addStr("," types)
    ai := 1
    loop parse types {
        switch A_LoopField {
            case "i":
                b := Buffer(4), NumPut("uint", OscSwap(Integer(args[ai++]) & 0xFFFFFFFF), b), parts.Push(b), total += 4
            case "f":
                t := Buffer(4), NumPut("float", Float(args[ai++]), t)
                b := Buffer(4), NumPut("uint", OscSwap(NumGet(t, "uint")), b), parts.Push(b), total += 4
            case "s":
                addStr(String(args[ai++]))
        }
    }
    msg := Buffer(total), off := 0
    for b in parts
        DllCall("RtlMoveMemory", "ptr", msg.Ptr + off, "ptr", b, "uptr", b.Size), off += b.Size
    return msg
}

OscSend(address, types, args*) {
    if !OscOpen()
        return false
    msg := OscBuild(address, types, args*)
    return DllCall("ws2_32\sendto", "ptr", OSC.sock, "ptr", msg, "int", msg.Size, "int", 0, "ptr", OSC.addr, "int", 16) > 0
}

; held actions -> VRChat's analog inputs (sent only when they change)
OscApply(held) {
    v := (held.Has("w") ? 1 : 0) - (held.Has("s") ? 1 : 0)
    h := (held.Has("d") ? 1 : 0) - (held.Has("a") ? 1 : 0)
    l := (held.Has("Right") ? 1 : 0) - (held.Has("Left") ? 1 : 0)
    j := held.Has("Space") ? 1 : 0
    r := held.Has("LShift") ? 1 : 0
    if v != OSC.vert
        OscSend("/input/Vertical", "f", v), OSC.vert := v
    if h != OSC.horiz
        OscSend("/input/Horizontal", "f", h), OSC.horiz := h
    if l != OSC.look
        OscSend("/input/LookHorizontal", "f", l * 0.6), OSC.look := l
    if j != OSC.jump
        OscSend("/input/Jump", "i", j), OSC.jump := j
    if r != OSC.run
        OscSend("/input/Run", "i", r), OSC.run := r
}

; text straight into the chatbox above the avatar (VRChat limit: 144 characters), no notification sound
OscChat(text) {
    OscSend("/chatbox/input", "sTF", SubStr(text, 1, 144))
    OSC.lastChat := A_TickCount
}

OscTyping(on) => OscSend("/chatbox/typing", on ? "T" : "F")

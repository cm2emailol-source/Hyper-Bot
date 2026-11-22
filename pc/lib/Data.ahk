#Requires AutoHotkey v2.0
; One shared data folder for every Hyper-Bot version: models + your settings, moves, fly memory.
; New versions find everything here, so nothing is downloaded or copied twice.
global DATA := EnvGet("USERPROFILE") "\HyperBot-Data"
for d in ["", "\models\ai", "\models\ears", "\models\voice", "\moves"]
    DirCreate(DATA d)
EnvSet("HYPERBOT_DATA", DATA) ; the fly brain and voice engines read this

; Finds downloads/settings left in this folder or in other Hyper-Bot folders next to it, and MOVES them in
; (moving on the same drive takes no extra space and is instant).
DataMigrate() {
    ; look next to this folder AND one level up (zips usually extract to <Downloads>\HyperBot-PC-NN\HyperBot-PC),
    ; plus Downloads and Desktop
    parent := RegExReplace(A_ScriptDir, "\\[^\\]+$"), grand := RegExReplace(parent, "\\[^\\]+$")
    roots := [A_ScriptDir]
    for base in [parent, grand, EnvGet("USERPROFILE") "\Downloads", EnvGet("USERPROFILE") "\Desktop"]
        loop files base "\*", "D" {
            roots.Push(A_LoopFileFullPath)
            if DirExist(A_LoopFileFullPath "\HyperBot-PC")
                roots.Push(A_LoopFileFullPath "\HyperBot-PC")
        }
    rules := [["ai\models\*.gguf", "\models\ai"], ["ears\models\*.bin", "\models\ears"], ["voice\models\*.onnx", "\models\voice"],
        ["voice\models\*.json", "\models\voice"], ["fly\fly_memory.npz", ""], ["settings.ini", ""], ["follow_log.ini", ""], ["moves\*.txt", "\moves"]]
    todo := [], total := 0, seen := Map()
    for root in roots {
        if !FileExist(root "\HyperBot.ahk") || InStr(root, DATA)
            continue
        for rule in rules
            loop files root "\" rule[1] {
                dest := DATA rule[2] "\" A_LoopFileName
                if FileExist(dest) || seen.Has(dest)
                    continue
                seen[dest] := 1
                todo.Push([A_LoopFileFullPath, dest]), total += A_LoopFileSize
            }
    }
    if !todo.Length
        return
    if MsgBox("Hyper-Bot found " todo.Length " file(s) you already have (" Round(total / 1048576) " MB: models, settings, moves, fly memory) "
        . "in your older Hyper-Bot folder(s).`n`nMove them into " DATA " so every version shares them?`n`n"
        . "Moving doesn't use extra space and nothing is downloaded again.", "Hyper-Bot - shared data folder", "YesNo Iconi 262144") != "Yes"
        return
    moved := 0
    for t in todo
        try FileMove(t[1], t[2]), moved++
    MsgBox("Moved " moved " file(s) into " DATA ".`nYou can delete old Hyper-Bot folders whenever you like.", "Hyper-Bot", "Iconi 262144")
}

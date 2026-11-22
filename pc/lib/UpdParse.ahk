#Requires AutoHotkey v2.0
; Reads GitHub's release list (pure function, no UI) - shared by the updater and the tests.

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


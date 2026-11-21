"""Hyper-Bot Fly Brain engine.

Runs a whole-brain model of the adult fruit fly (FlyWire 783 connectome: 138,639 neurons, 15M connections)
as leaky integrate-and-fire neurons with the parameters of Shiu et al. 2024 (Nature). Nothing is scripted:
Hyper-Bot turns what happens in Roblox into sensory input, and turns the firing of real command neurons
into controls.

  senses.txt  (written by Hyper-Bot)  ->  sensory neurons
  actions.txt (written here)          <-  command neurons (escape, moonwalk, turning, grooming, mouth)

Offline only: no network. Usage:  python fly_server.py [--selftest]
"""
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
IO = os.path.join(HERE, "io")
P = dict(v0=-52.0, vrst=-52.0, vth=-45.0, tmbr=20.0, tau=5.0, trfc=2.2, tdly=1.8, wsyn=0.275)
LETTERS = "bzzzkrtshhuuiiaoeppmmll"


class Brain:
    def __init__(self, path, dt=1.0, seed=None):
        d = np.load(path)
        self.N = int(d["n"])
        self.indptr, self.indices = d["indptr"], d["indices"]
        self.data = d["data"].astype(np.float32) * np.float32(P["wsyn"])
        self.G = {k[2:]: d[k] for k in d.files if k.startswith("g_")}
        # Fly Learning: plastic Kenyon cell -> approach-MBON synapses (arXiv 2611.09930)
        self.plastic = self.G.pop("plastic")
        self.odours = [str(x) for x in self.G.pop("odour_names")]
        rows = np.repeat(np.arange(self.N, dtype=np.int32), np.diff(self.indptr))
        self.p_pre = rows[self.plastic]
        self.w0 = self.data[self.plastic].copy()
        self.dt = dt
        self.delay = max(1, int(round(P["tdly"] / dt)))
        self.decay = np.float32(np.exp(-dt / P["tau"]))
        self.kv = np.float32(dt / P["tmbr"])
        self.rfc = int(round(P["trfc"] / dt))
        self.rng = np.random.default_rng(seed)
        self.reset()

    def reset(self):
        N = self.N
        self.v = np.full(N, P["v0"], np.float32)
        self.g = np.zeros(N, np.float32)
        self.ref = np.zeros(N, np.int16)
        self.queue = [np.zeros(N, np.float32) for _ in range(self.delay)]
        self.qi = 0
        self.rates = np.zeros(N, np.float32)
        self.counts = np.zeros(N, np.int32)
        self.spikes = 0

    def step(self):
        q = self.queue[self.qi]
        self.g += q
        q.fill(0)
        active = self.ref <= 0
        self.v += np.where(active, (P["v0"] - self.v + self.g) * self.kv, 0)
        self.g *= np.where(active, self.decay, 1).astype(np.float32)
        np.subtract(self.ref, 1, out=self.ref, where=self.ref > -1)
        spk = np.flatnonzero(active & (self.v > P["vth"]))
        drv = self.driven
        if drv.size:
            fire = drv[self.rng.random(drv.size) < self.rates[drv] * (self.dt / 1000.0)]
            if fire.size:
                spk = np.union1d(spk, fire)
        if spk.size:
            self.v[spk] = P["vrst"]
            self.g[spk] = 0
            self.ref[spk] = self.rfc
            self.counts[spk] += 1
            self.spikes += spk.size
            st, en = self.indptr[spk], self.indptr[spk + 1]
            ln = en - st
            tot = int(ln.sum())
            if tot:
                sel = np.repeat(st - np.concatenate(([0], np.cumsum(ln)[:-1])), ln) + np.arange(tot)
                # q was just emptied: it is read again in `delay` steps
                q += np.bincount(self.indices[sel], weights=self.data[sel], minlength=self.N).astype(np.float32)
        self.qi = (self.qi + 1) % self.delay

    def run(self, ms):
        self.driven = np.flatnonzero(self.rates)
        for _ in range(int(round(ms / self.dt))):
            self.step()

    def count(self, group):
        return int(self.counts[self.G[group]].sum())


ETA, LAM, WMIN, WMAX = 5e-6, 0.01, 0.1, 1.8     # learning rate per Hz^2, recovery, weight bounds (x w0)


class Learner:
    """Dopamine timing rule from the paper (applied every 100 ms): PPL1 dopamine arriving with or after
    Kenyon cell activity weakens KC->approach-MBON synapses; dopamine arriving before KC activity strengthens
    them. Weights stay within 0.1-1.8 x the connectome weight and recover toward it by 1% after each update."""

    def __init__(self, brain):
        self.b = brain
        self.prev_kc = np.zeros(len(brain.plastic), np.float32)
        self.prev_d = 0.0

    def tick(self, ms, learn=True):
        b = self.b
        before = b.counts.copy()
        b.run(ms)
        diff = b.counts - before
        e = diff[b.p_pre].astype(np.float32) * (1000.0 / ms)            # presynaptic KC rate (Hz)
        d = float(diff[b.G["ppl1"]].mean()) * (1000.0 / ms)             # dopamine = mean PPL1 rate (Hz)
        if learn and (d > 0 or self.prev_d > 0):
            w = b.data[b.plastic]
            dw = np.zeros_like(w)
            if d > 0:                                                     # dopamine with/after KC: weaken
                dw -= ETA * np.maximum(e, self.prev_kc) * d * self.b.w0
            elif self.prev_d > 0:                                         # dopamine before KC: strengthen
                dw += ETA * e * self.prev_d * self.b.w0
            if np.any(dw):
                w = w + dw
                w += LAM * (b.w0 - w)
                b.data[b.plastic] = np.clip(w, WMIN * b.w0, WMAX * b.w0)
        self.prev_kc, self.prev_d = e, d
        return diff

    def index(self, diff, ms):
        """Avoidance index (Hz) = mean avoid-MBON rate - mean approach-MBON rate."""
        k = 1000.0 / ms
        return float(diff[self.b.G["mbon_avoid"]].mean() * k - diff[self.b.G["mbon_app"]].mean() * k)


def present(b, L, odour, ms=300, punish=False, learn=True):
    b.rates[:] = 0
    b.rates[b.G["orn_" + odour]] = 80.0
    if punish:
        b.rates[b.G["ppl1"]] = 100.0
    total = np.zeros(b.N, np.int32)
    for _ in range(int(ms // 100)):
        total += L.tick(100, learn)
    b.rates[:] = 0
    L.tick(100, learn)          # 100 ms gap after each presentation
    L.tick(100, learn)
    return total


def learning_test(b):
    """The paper's specificity test: DC2 paired with punishment, D unpaired, DA1 never paired."""
    b.reset()
    L = Learner(b)
    kc = b.G["kc"]
    for od in ["DC2", "D"]:
        tot = present(b, L, od, learn=False)
        print(f"LEARN gate: odour {od} activates {100 * np.mean(tot[kc] > 0):.1f}% of Kenyon cells (paper: 5.5-8.9%)")

    def probe(od):
        return np.mean([L.index(present(b, L, od, learn=False), 300) for _ in range(5)])
    names = ["DC2", "D", "DA1"] if "DA1" in b.odours else ["DC2", "D", "DL3"]
    base = {od: probe(od) for od in names}
    for _ in range(30):
        present(b, L, "DC2", punish=True)
        present(b, L, "D")
    after = {od: probe(od) for od in names}
    w = b.data[b.plastic] / b.w0
    shifts = {od: round(after[od] - base[od], 2) for od in names}
    print(f"LEARN avoidance shift after 30 trials (Hz): {shifts}  (paper: DC2 +11.05, D +1.43, DA1 +0.56)")
    print(f"LEARN plastic weights: mean {w.mean():.2f} x w0, min {w.min():.2f}")
    return shifts


def read_senses():
    out = {}
    try:
        with open(os.path.join(IO, "senses.txt"), encoding="utf-8") as f:
            for line in f:
                if "=" in line:
                    k, v = line.strip().split("=", 1)
                    try:
                        out[k] = float(v)
                    except ValueError:
                        pass
    except OSError:
        pass
    return out


def write_actions(d):
    tmp = os.path.join(IO, "actions.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        for k, v in d.items():
            f.write(f"{k}={v}\n")
    os.replace(tmp, os.path.join(IO, "actions.txt"))


def selftest(b):
    t0 = time.time()
    b.reset()
    b.rates[b.G["sugar"]] = 100.0
    b.run(1000)
    mn9 = b.count("mn9")
    el = time.time() - t0
    print(f"SELFTEST sugar->MN9 {mn9} Hz (paper model ~74-82), 1 s brain time in {el:.1f} s (x{1 / el:.2f} real time)")
    b.reset()
    b.rates[b.G["sound"]] = 150.0
    b.run(500)
    print(f"SELFTEST sound->giant fiber escape spikes: {b.count('escape')}")
    ok = mn9 > 20
    t0 = time.time()
    shifts = learning_test(b)
    print(f"LEARN test took {time.time() - t0:.0f} s")
    od = list(shifts)
    # the paper's specificity comparison: the punished odour shifts much more than the unpunished one
    # (the third, never-paired probe is printed for interest; its 5-presentation reading is noisy)
    ok = ok and shifts[od[0]] > 2 and shifts[od[0]] > 2 * max(shifts[od[1]], 0.5)
    print("SELFTEST OK" if ok else "SELFTEST FAILED")
    return ok


def main():
    os.makedirs(IO, exist_ok=True)
    b = Brain(os.path.join(HERE, "fly_data.npz"))
    if "--selftest" in sys.argv:
        sys.exit(0 if selftest(b) else 1)

    G = b.G
    learner = Learner(b)
    mem_path = os.path.join(HERE, "fly_memory.npz")
    baseline = {}                                        # odour -> first avoidance index (before learning)
    try:
        m = np.load(mem_path)
        if len(m["w"]) == len(b.plastic):
            b.data[b.plastic] = m["w"]
            baseline = {str(k): float(v) for k, v in zip(m["bk"], m["bv"])}
    except (OSError, KeyError, ValueError):
        pass

    def save_memory():
        np.savez(mem_path, w=b.data[b.plastic], bk=np.array(list(baseline.keys()), dtype=str),
                 bv=np.array(list(baseline.values()), dtype=np.float64))

    odour_until = -1.0
    odour_name = ""
    punish_until = -1.0
    odour_counts = np.zeros(b.N, np.int32)
    feel = learned = 0.0
    n_avoid = 0
    last_save = 0.0
    bursts = {}          # group -> brain-time (ms) when the burst ends
    last_seq = {}
    brain_ms = 0.0
    WINDOW = 200.0       # decode the command neurons every 200 ms of brain time
    mean_dn = None
    mean_groom = None
    mean_mouth = None
    last_word_ms = -1e9
    n_jump = n_groom = n_back = n_word = 0
    word = ""
    seq = 0
    last_sense_read = 0.0
    sens = {}
    while True:
        wall0 = time.time()
        if wall0 - last_sense_read > 0.1:
            sens = read_senses()
            last_sense_read = wall0
            if sens.get("quit", 0) >= 1:
                save_memory()
                break
        # --- senses -> sensory neurons
        b.rates[:] = 0
        b.rates[G["noise"]] = 1.5                          # spontaneous sensory noise ("being alive")
        for key, grp in (("sound", "sound"), ("praise", "sugar"), ("insult", "bitter"), ("water", "water"),
                         ("touch", "touch"), ("wind", "wind")):
            n = sens.get(key, 0)                           # event counters: a new count = a 300 ms burst
            if n != last_seq.get(key, 0):
                last_seq[key] = n
                bursts[grp] = brain_ms + 300
        for grp, end in list(bursts.items()):
            if brain_ms < end:
                b.rates[G[grp]] = 150.0
            else:
                del bursts[grp]
        b.rates[G["ocelli"]] = 200.0 * min(1.0, sens.get("lightchange", 0) * 4)
        b.rates[G["eyeL"]] = 120 * min(1.0, sens.get("motionL", 0) * 4)   # fly eyes react to motion
        b.rates[G["eyeR"]] = 120 * min(1.0, sens.get("motionR", 0) * 4)
        b.rates[G["smell"]] = 0.0
        # each player has their own smell (one olfactory receptor class); mean words = punishment (PPL1 dopamine)
        os_ = sens.get("odourseq", 0)
        if os_ != last_seq.get("odourseq", 0):
            last_seq["odourseq"] = os_
            odour_name = b.odours[int(sens.get("odour", 0)) % len(b.odours)]
            odour_until = brain_ms + 300
            odour_counts[:] = 0
        ps = sens.get("punishseq", 0)
        if ps != last_seq.get("punishseq", 0):
            last_seq["punishseq"] = ps
            punish_until = brain_ms + 300
        smelling = brain_ms < odour_until
        if smelling:
            b.rates[G["orn_" + odour_name]] = 80.0
        if brain_ms < punish_until:
            b.rates[G["ppl1"]] = 100.0

        b.counts[:] = 0
        b.spikes = 0
        for _ in range(int(WINDOW // 100)):
            d = learner.tick(100, learn=True)
            if smelling:
                odour_counts += d
        brain_ms += WINDOW
        if smelling and brain_ms >= odour_until:                 # finished smelling a player: how does it feel?
            feel = learner.index(odour_counts, 300)
            if odour_name not in baseline:
                baseline[odour_name] = feel
            learned = feel - baseline[odour_name]
            if learned > 2.0:                                     # learned to avoid this smell -> back away
                n_avoid += 1
        if brain_ms - last_save > 60000:
            save_memory()
            last_save = brain_ms

        # --- command neurons -> actions (each compared with the fly's own recent average)
        dn = b.count("dn")
        mean_dn = dn if mean_dn is None else 0.97 * mean_dn + 0.03 * dn
        L = b.count("dnL") + 4 * b.count("turnL_strong")
        R = b.count("dnR") + 4 * b.count("turnR_strong")
        turn = max(-1.0, min(1.0, 4.0 * (R - L) / (L + R + 15.0)))   # left-side command neurons turn left
        forward = max(0.0, min(1.0, 0.45 + 1.5 * (dn - mean_dn) / (mean_dn + 20) + 0.3 * b.count("forward")))
        groom = b.count("groom")
        mean_groom = groom if mean_groom is None else 0.97 * mean_groom + 0.03 * groom
        mouth_fired = np.flatnonzero(b.counts[G["mouth"]])
        mouth = int(b.counts[G["mouth"]].sum())
        mean_mouth = mouth if mean_mouth is None else 0.97 * mean_mouth + 0.03 * mouth
        if b.count("escape") >= 2:
            n_jump += 1
        if b.count("back") >= 3:
            n_back += 1
        if groom >= max(5, 2.0 * mean_groom + 3):
            n_groom += 1
        # the mouth "types" when its motor neurons fire well above normal (at most every 20 s of brain time)
        if mouth >= max(10, 2.0 * mean_mouth + 5) and brain_ms - last_word_ms > 20000 and len(mouth_fired):
            word = "".join(LETTERS[(int(i) * 7 + 3) % len(LETTERS)] for i in mouth_fired[:8])
            n_word += 1
            last_word_ms = brain_ms
        seq += 1
        el = time.time() - wall0
        write_actions({
            "seq": seq, "speed": round(WINDOW / 1000 / max(el, 1e-6), 2), "spikes": b.spikes,
            "active": int((b.counts > 0).sum()), "dn": dn, "brainms": int(brain_ms),
            "forward": round(forward, 2), "turn": round(turn, 2),
            "jumps": n_jump, "backs": n_back, "grooms": n_groom, "words": n_word, "word": word,
            "mouth": mouth, "mn9": b.count("mn9"),
            "odour": odour_name, "feel": round(feel, 2), "learned": round(learned, 2), "avoids": n_avoid,
            "plastic": round(float((b.data[b.plastic] / b.w0).mean()), 3),
        })
        # never run faster than real time (slower is fine: a slow-motion fly)
        rest = WINDOW / 1000 - (time.time() - wall0)
        if rest > 0:
            time.sleep(rest)


if __name__ == "__main__":
    main()

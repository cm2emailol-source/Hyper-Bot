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
    print("SELFTEST OK" if ok else "SELFTEST FAILED")
    return ok


def main():
    os.makedirs(IO, exist_ok=True)
    b = Brain(os.path.join(HERE, "fly_data.npz"))
    if "--selftest" in sys.argv:
        sys.exit(0 if selftest(b) else 1)

    G = b.G
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
        b.rates[G["smell"]] = 8.0 * min(3.0, sens.get("players", 0))

        b.counts[:] = 0
        b.spikes = 0
        b.run(WINDOW)
        brain_ms += WINDOW

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
        })
        # never run faster than real time (slower is fine: a slow-motion fly)
        rest = WINDOW / 1000 - (time.time() - wall0)
        if rest > 0:
            time.sleep(rest)


if __name__ == "__main__":
    main()

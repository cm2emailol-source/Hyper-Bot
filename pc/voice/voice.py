"""Hyper-Bot voice: Piper text-to-speech (offline) with a robot filter and a "crashing out" mad voice.
Plays into VB-Audio Virtual Cable ("CABLE Input" -> VRChat mic "CABLE Output") and, if 'Hear him' is on,
also through your own speakers. Nothing is saved; nothing goes online.

Hyper-Bot writes  io/say.txt   lines "seq|style|text"   (style: normal / mad)
                  io/ctl.txt   "monitor=1/0", "stop=<n>", "quit=1"
This writes       io/state.txt "speaking=0/1", "cable=0/1", "ready=1"
While speaking it pauses the ears (../ears/io/ctl.txt) so the bot never hears itself.

Usage: python voice.py [--selftest out_dir]
"""
import os
import sys
import threading
import time
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
IO = os.path.join(HERE, "io")
EARS_CTL = os.path.join(HERE, "..", "ears", "io", "ctl.txt")


def find_model():
    pref = "low"
    try:
        with open(os.path.join(IO, "ctl.txt"), encoding="utf-8") as f:
            if "quality=medium" in f.read():
                pref = "medium"
    except OSError:
        pass
    for q in (pref, "low", "medium"):
        p = os.path.join(HERE, "models", f"en_GB-alan-{q}.onnx")
        if os.path.exists(p):
            return p
    return None


class Tts:
    def __init__(self, model):
        from piper import PiperVoice
        self.v = PiperVoice.load(model)
        self.sr = int(self.v.config.sample_rate)

    def raw(self, text):
        """float32 mono samples for text (works with piper-tts 1.3+ and older 1.2)."""
        try:
            chunks = list(self.v.synthesize(text))
            if chunks and hasattr(chunks[0], "audio_float_array"):
                return np.concatenate([c.audio_float_array for c in chunks]).astype(np.float32)
            if chunks and hasattr(chunks[0], "audio_int16_bytes"):
                return np.concatenate([np.frombuffer(c.audio_int16_bytes, np.int16) for c in chunks]).astype(np.float32) / 32768
        except TypeError:
            pass
        pcm = b"".join(self.v.synthesize_stream_raw(text))
        return np.frombuffer(pcm, np.int16).astype(np.float32) / 32768


def robotize(x, sr):
    """light metallic robot filter: a little ring modulation + bit crush"""
    t = np.arange(len(x)) / sr
    y = x * (0.75 + 0.25 * np.sin(2 * np.pi * 45 * t))
    y = np.round(y * 48) / 48
    return (0.85 * y + 0.15 * x).astype(np.float32)


def crash_out(x, sr, rng=np.random.default_rng()):
    """the mad voice: pitched way up and sped up, overdriven, crackly, with random glitch stutters"""
    n = len(x)
    y = np.interp(np.arange(0, n, 1.38), np.arange(n), x)                 # ~ +5.5 semitones and faster
    y = np.tanh(y * 3.0) * 0.8                                            # overdrive
    y += (rng.random(len(y)) < 0.002) * rng.uniform(-0.6, 0.6, len(y))     # crackle
    y = np.round(y * 20) / 20                                             # crunchier bit crush
    out, i, seg = [], 0, int(sr * 0.09)
    while i < len(y):                                                      # glitch: sometimes repeat a tiny slice
        part = y[i:i + seg]
        out.append(part)
        if rng.random() < 0.12:
            out.append(part[: seg // 2])
        i += seg
    return np.concatenate(out).astype(np.float32)


def render(tts, text, style):
    x = tts.raw(text)
    x = crash_out(x, tts.sr) if style == "mad" else robotize(x, tts.sr)
    peak = float(np.max(np.abs(x)) or 1.0)
    return (x / peak * 0.9).astype(np.float32)


def write_wav(path, x, sr):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())


def set_state(**kv):
    tmp = os.path.join(IO, "state.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        for k, v in kv.items():
            f.write(f"{k}={v}\n")
    os.replace(tmp, os.path.join(IO, "state.txt"))


def ears_pause(on):
    try:
        with open(EARS_CTL, "w", encoding="utf-8") as f:
            f.write("pause=1\n" if on else "pause=0\n")
    except OSError:
        pass


def read_ctl():
    try:
        with open(os.path.join(IO, "ctl.txt"), encoding="utf-8") as f:
            return dict(l.strip().split("=", 1) for l in f if "=" in l)
    except OSError:
        return {}


def main():
    os.makedirs(IO, exist_ok=True)
    model = find_model()
    if "--selftest" in sys.argv:
        out = sys.argv[sys.argv.index("--selftest") + 1]
        t0 = time.time()
        tts = Tts(model)
        print(f"VOICE loaded {os.path.basename(model)} in {time.time() - t0:.1f} s")
        for style, text in (("normal", "Hello mate, I am a robot butler."), ("mad", "Oh my god, do the blue wire?")):
            t0 = time.time()
            x = render(tts, text, style)
            write_wav(os.path.join(out, f"voice_{style}.wav"), x, tts.sr)
            print(f"VOICE {style}: {len(x) / tts.sr:.1f} s of audio made in {time.time() - t0:.2f} s")
        return

    import soundcard as sc
    tts = Tts(model)
    speakers = sc.all_speakers()
    cable = next((s for s in speakers if "cable input" in s.name.lower()), None)
    last_seq, stop_seen = 0, None
    set_state(speaking=0, cable=1 if cable else 0, ready=1)
    say_path = os.path.join(IO, "say.txt")
    stop_flag = threading.Event()

    def play(dev, x, sr):
        try:
            with dev.player(samplerate=sr, channels=1, blocksize=1024) as p:
                step = sr // 10
                for i in range(0, len(x), step):                   # small blocks so "stop" cuts it off fast
                    if stop_flag.is_set():
                        return
                    p.play(x[i:i + step])
        except Exception:
            pass

    while True:
        ctl = read_ctl()
        if ctl.get("quit") == "1":
            return
        if ctl.get("stop") != stop_seen:
            stop_seen = ctl.get("stop")
        lines = []
        try:
            with open(say_path, encoding="utf-8") as f:
                lines = [l.rstrip("\n") for l in f if l.count("|") >= 2]
        except OSError:
            pass
        todo = []
        for l in lines:
            seq, style, text = l.split("|", 2)
            if seq.isdigit() and int(seq) > last_seq:
                todo.append((int(seq), style, text))
        for seq, style, text in todo:
            last_seq = seq
            c = read_ctl()
            if c.get("stop") != stop_seen:                          # interrupted: drop what's queued
                stop_seen = c.get("stop")
                break
            x = render(tts, text, style)
            stop_flag.clear()
            devs = [d for d in (cable, sc.default_speaker() if c.get("monitor") == "1" else None) if d]
            if not devs:
                continue
            set_state(speaking=1, cable=1 if cable else 0, ready=1)
            ears_pause(True)
            th = [threading.Thread(target=play, args=(d, x, tts.sr)) for d in devs]
            for t in th:
                t.start()
            while any(t.is_alive() for t in th):
                c = read_ctl()
                if c.get("stop") != stop_seen or c.get("quit") == "1":
                    stop_seen = c.get("stop")
                    stop_flag.set()
                time.sleep(0.05)
            time.sleep(0.3)                                          # let the echo die before listening again
            ears_pause(False)
            set_state(speaking=0, cable=1 if cable else 0, ready=1)
        time.sleep(0.05)


if __name__ == "__main__":
    main()

"""Hyper-Bot ears: hears what's playing on this PC (VRChat voices) and turns speech into text with
whisper.cpp running locally (127.0.0.1:8098). Offline. Nothing is recorded to disk except the text it heard
(ears/io/heard.txt, overwritten as it goes) - audio stays in memory.

Usage: python ears.py              (listen to the default speaker output)
       python ears.py --file x.wav (transcribe one file - used by the self-test)
"""
import io
import json
import os
import re
import sys
import time
import urllib.request
import uuid
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
IO = os.path.join(HERE, "io")
URL = "http://127.0.0.1:8098/inference"
SR = 16000
JUNK = re.compile(r"^\s*[\[\(].*[\]\)]\s*$|^\s*(thank you\.?|thanks for watching!?|you|bye\.?|\.+)\s*$", re.I)
# Whisper sometimes labels non-speech like "[gunshot]" or "(explosion)": keep the interesting ones as sounds
SOUNDS = re.compile(r"gun|shot|bang|explo|boom|blast|scream|yell|shout|laugh|crash|siren|alarm|thud|knock|glass|growl|roar|whistle|clap|applause", re.I)


class BangDetector:
    """A sudden, very loud block after quieter ones = a bang (gunshot, explosion, door slam...)."""

    def __init__(self):
        self.avg = 0.01
        self.cool = 0

    def update(self, rms):
        bang = self.cool == 0 and rms > 0.2 and rms > self.avg * 8
        self.avg = 0.9 * self.avg + 0.1 * rms
        if bang:
            self.cool = 20                                            # at most one bang every 2 s
        elif self.cool:
            self.cool -= 1
        return bang


def wav_bytes(samples):
    pcm = (np.clip(samples, -1, 1) * 32767).astype(np.int16)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return buf.getvalue()


def transcribe(wav):
    b = uuid.uuid4().hex
    body = (f"--{b}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\n").encode() + wav
    for k, v in (("response_format", "json"), ("temperature", "0")):
        body += f"\r\n--{b}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}".encode()
    body += f"\r\n--{b}--\r\n".encode()
    req = urllib.request.Request(URL, data=body, headers={"Content-Type": f"multipart/form-data; boundary={b}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        text = json.loads(r.read().decode("utf-8", "ignore")).get("text", "")
    text = re.sub(r"\s+", " ", text).strip()
    tags = re.findall(r"[\[\(]([^\]\)]{1,30})[\]\)]", text)
    sounds = [t.strip().lower() for t in tags if SOUNDS.search(t)]
    speech = re.sub(r"[\[\(][^\]\)]*[\]\)]", " ", text).strip()
    speech = "" if JUNK.match(speech) or not re.search(r"[a-zA-Z]{2}", speech) else re.sub(r"\s+", " ", speech)
    out = " ".join(f"[sound: {x}]" for x in sounds[:2])
    return (out + " " + speech).strip() if speech or out else ""


def say_heard(seq, text):
    tmp = os.path.join(IO, "heard.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(f"{seq}|{text}\n")
    os.replace(tmp, os.path.join(IO, "heard.txt"))


def paused():
    try:
        with open(os.path.join(IO, "ctl.txt"), encoding="utf-8") as f:
            c = f.read()
        return "quit=1" in c, "pause=1" in c
    except OSError:
        return False, False


def write_status(text):
    try:
        tmp = os.path.join(IO, "status.tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, os.path.join(IO, "status.txt"))
    except OSError:
        pass


def open_loopback(sc):
    """The 'recording' side of the speakers Windows plays sound on. Looked up by the device's exact ID:
    several devices can share a name (e.g. three called 'Speakers' / 'Ηχεία': Realtek, Steam Streaming, ...)
    and looking it up by name could open a silent one."""
    spk = sc.default_speaker()
    try:
        return spk, sc.get_microphone(id=spk.id, include_loopback=True)
    except Exception:
        pass
    for m in sc.all_microphones(include_loopback=True):
        if getattr(m, "isloopback", False) and m.id == spk.id:
            return spk, m
    return spk, sc.get_microphone(id=str(spk.name), include_loopback=True)


def listen():
    import soundcard as sc
    try:
        spk, mic = open_loopback(sc)
    except Exception as e:
        write_status("error=can't open the speakers' sound: %s\n" % e)
        raise
    noise = 0.005
    peak, last_status = 0.0, 0.0
    speech, silent, seq = [], 0, 0
    bangs = BangDetector()
    with mic.recorder(samplerate=SR, channels=1, blocksize=1600) as rec:
        while True:
            quit_, pause = paused()
            if quit_:
                return
            block = rec.record(numframes=SR // 10).reshape(-1)       # 100 ms
            if pause:                                                  # the bot is talking (phase 3)
                speech, silent = [], 0
                continue
            rms = float(np.sqrt(np.mean(block ** 2)) + 1e-9)
            peak = max(peak, rms)
            if time.time() - last_status > 1.0:                        # live level for the app (once a second)
                write_status("device=%s\nlevel=%d\n" % (spk.name, min(100, int(peak * 400))))
                peak, last_status = 0.0, time.time()
            if bangs.update(rms):
                seq += 1
                say_heard(seq, "[sound: loud bang]")
            voiced = rms > max(0.01, noise * 3)
            if not voiced and not speech:
                noise = 0.95 * noise + 0.05 * rms                      # learn the background level
            if voiced or speech:
                speech.append(block)
                silent = 0 if voiced else silent + 1
            if speech and (silent >= 7 or len(speech) >= 150):         # 0.7 s pause or 15 s max
                audio = np.concatenate(speech)
                speech, silent = [], 0
                if len(audio) > SR * 0.5:
                    try:
                        text = transcribe(wav_bytes(audio))
                    except Exception as e:                             # whisper not ready yet etc.
                        text = ""
                        time.sleep(0.5)
                    if text:
                        seq += 1
                        say_heard(seq, text)


if __name__ == "__main__":
    os.makedirs(IO, exist_ok=True)
    if "--bangtest" in sys.argv:
        d = BangDetector()
        quiet = [0.01] * 30
        hits = [d.update(x) for x in quiet + [0.6] + quiet + [0.05] * 20 + [0.7, 0.7]]
        print("EARS bang detector:", sum(hits), "bang(s) found (expected 2)")
        sys.exit(0)
    if "--file" in sys.argv:
        path = sys.argv[sys.argv.index("--file") + 1]
        with wave.open(path, "rb") as w:
            sr, ch, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
            raw = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16 if sw == 2 else np.uint8).astype(np.float32)
        raw = raw / 32768.0 if sw == 2 else raw / 128.0 - 1
        if ch > 1:
            raw = raw.reshape(-1, ch).mean(axis=1)
        if sr != SR:
            raw = np.interp(np.linspace(0, len(raw), int(len(raw) * SR / sr), endpoint=False), np.arange(len(raw)), raw)
        t0 = time.time()
        print("EARS heard:", transcribe(wav_bytes(raw)), f"({time.time() - t0:.1f} s)")
    else:
        try:
            listen()
        except Exception as e:                                         # show the app why instead of dying silently
            write_status("error=%s: %s\n" % (type(e).__name__, e))
            raise

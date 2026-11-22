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
    return "" if JUNK.match(text) else text


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


def listen():
    import soundcard as sc
    spk = sc.default_speaker()
    mic = sc.get_microphone(id=str(spk.name), include_loopback=True)
    noise = 0.005
    speech, silent, seq = [], 0, 0
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
        listen()

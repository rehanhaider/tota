"""Tota helper process.

The app starts this with the mlx-audio Python and sends one JSON request per line on
stdin. Replies go out one JSON object per line on the original stdout. Anything the
libraries print is sent to stderr so it can't corrupt the replies.
"""
import json
import os
import re
import sys
import time
import traceback

os.environ.setdefault("HF_HUB_OFFLINE", "1")

_reply_fd = os.dup(1)
os.dup2(2, 1)
sys.stdout = sys.stderr
_reply = os.fdopen(_reply_fd, "w", buffering=1)

TTS_REPO = "maya-research/maya2-native"
STT_REPO = "mlx-community/whisper-large-v3-turbo-asr-fp16"
FRAME_RATE = 12.5  # Maya audio frames per second

_tts = None
_stt = None
_warmed = set()


def send(obj):
    _reply.write(json.dumps(obj) + "\n")
    _reply.flush()


def tts():
    global _tts
    if _tts is None:
        from mlx_audio.tts.utils import load
        _tts = load(TTS_REPO)
    return _tts


def stt():
    global _stt
    if _stt is None:
        from mlx_audio.stt.utils import load
        _stt = load(STT_REPO)
    return _stt


def split_text(text, max_chars):
    """Whole sentences, split at commas if a sentence is longer than max_chars."""
    text = " ".join(text.split())
    pieces = []
    for sent in re.split(r"(?<=[.!?])\s+", text):
        if len(sent) <= max_chars:
            pieces.append(sent)
            continue
        cur = ""
        for clause in re.split(r"(?<=[,;:])\s+", sent):
            if cur and len(cur) + len(clause) + 1 > max_chars:
                pieces.append(cur)
                cur = clause
            else:
                cur = f"{cur} {clause}".strip()
        pieces.append(cur)
    chunks, cur = [], ""
    for piece in pieces:
        if cur and len(cur) + len(piece) + 1 > max_chars:
            chunks.append(cur)
            cur = piece
        else:
            cur = f"{cur} {piece}".strip()
    if cur:
        chunks.append(cur)
    return chunks


def do_generate(rid, r):
    import mlx.core as mx
    import numpy as np
    from mlx_audio.audio_io import write

    model = tts()
    text = r["text"].strip()
    if not text:
        raise ValueError("There is no text to speak.")
    max_chars = int(r.get("max_chars", 150))
    chunks = split_text(text, max_chars) if max_chars > 0 else [" ".join(text.split())]
    seed = r.get("seed")
    kwargs = dict(
        lang_code=r.get("lang_code", "en"),
        ref_lang=r.get("lang_code", "en"),
        ref_audio=r["ref_audio"],
        ref_text=r["ref_text"],
        conditioning=r.get("conditioning", "icl"),
        temperature=float(r.get("temperature", 0.4)),
        top_k=int(r.get("top_k", 64)),
        top_p=float(r.get("top_p", 1.0)),
        depth_temperature=float(r.get("depth_temperature", 0.5)),
        depth_top_k=int(r.get("depth_top_k", 64)),
        presence_penalty=float(r.get("presence_penalty", 0.8)),
        presence_window=int(r.get("presence_window", 12)),
    )
    # The first generation with a voice runs one-time setup that uses random numbers,
    # so a fixed seed only repeats after it. A tiny throwaway run does that setup first.
    key = (r["ref_audio"], r["ref_text"], kwargs["conditioning"])
    if key not in _warmed:
        next(model.generate("Hi.", max_tokens=2, **kwargs))
        _warmed.add(key)
    if seed is not None:
        mx.random.seed(int(seed))
    gap = float(r.get("gap", 0.2))
    start = time.time()
    parts, sr, retries = [], None, 0
    for i, c in enumerate(chunks, 1):
        send({"id": rid, "type": "progress", "chunk": i, "total": len(chunks)})
        # Normal speech is about 0.1 s per character; a chunk that reaches this cap ran away.
        cap = int(FRAME_RATE * (len(c) * 0.13 + 2))
        for attempt in range(1, 4):
            res = next(model.generate(c, max_tokens=cap, **kwargs))
            sr = res.sample_rate
            audio = np.array(res.audio)
            if len(audio) / sr < cap / FRAME_RATE - 0.5:
                break
            retries += 1
        parts.append(audio)
        if i < len(chunks) and gap > 0:
            parts.append(np.zeros(int(sr * gap), dtype=audio.dtype))
    full = np.concatenate(parts)
    out = os.path.expanduser(r["out"])
    os.makedirs(os.path.dirname(out), exist_ok=True)
    write(out, full, sr)
    return {"path": out, "duration": len(full) / sr, "elapsed": time.time() - start,
            "chunks": len(chunks), "retries": retries}


def do_transcribe(rid, r):
    res = stt().generate(r["audio"], language=r.get("language", "en"))
    return {"text": res.text.strip()}


def do_trim(rid, r):
    from mlx_audio.audio_io import read, write
    audio, sr = read(r["audio"], dtype="float32", nchannels=1, sample_rate=24000)
    audio = audio.reshape(-1)
    a = max(0, int(float(r["start"]) * sr))
    b = min(len(audio), int(float(r["end"]) * sr))
    if b - a < sr:
        raise ValueError("The selection is shorter than 1 second.")
    out = os.path.expanduser(r["out"])
    os.makedirs(os.path.dirname(out), exist_ok=True)
    write(out, audio[a:b], sr)
    return {"path": out, "duration": (b - a) / sr}


HANDLERS = {"generate": do_generate, "transcribe": do_transcribe, "trim": do_trim}


def main():
    send({"type": "status", "status": "loading"})
    try:
        tts()
    except Exception as e:
        send({"type": "status", "status": "error", "message": f"Couldn't load the voice model: {e}"})
    else:
        send({"type": "status", "status": "ready"})
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        rid = None
        try:
            r = json.loads(line)
            rid = r.get("id")
            handler = HANDLERS.get(r.get("cmd"))
            if handler is None:
                raise ValueError(f"Unknown command: {r.get('cmd')}")
            result = handler(rid, r)
            send({"id": rid, "type": "result", **result})
        except Exception as e:
            traceback.print_exc()
            send({"id": rid, "type": "error", "message": str(e) or type(e).__name__})


if __name__ == "__main__":
    main()

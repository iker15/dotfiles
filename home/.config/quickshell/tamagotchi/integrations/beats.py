#!/usr/bin/env python3
# Ritmo de lo que suena: escucha la salida de audio (copia del sink por defecto, PipeWire) y
# emite una línea "beat <periodo_s>" en cada golpe, para que Mochi baile a compás.
#  - fuerza de ataque (flujo espectral en graves/medios) cada 23 ms
#  - tempo por autocorrelación de los últimos ~6 s (70-180 BPM)
#  - golpes: se engancha a los picos de ataque cerca de donde toca el siguiente; si no llega
#    ninguno, sigue la rejilla (pero solo si el tempo es claro)
# Solo lee audio mientras lo necesita Mochi (lo lanza él con música sonando).
import subprocess, sys, time
import numpy as np

RATE, HOP, WIN = 11025, 256, 1024
FPS = RATE / HOP                      # ~43 tramas/s
HIST = int(6 * FPS)


def main():
    import os
    src = os.environ.get("BEATS_FILE")   # (pruebas: PCM s16 mono 11025 Hz de un archivo)
    rec = subprocess.Popen(["cat", src], stdout=subprocess.PIPE) if src else subprocess.Popen(["pw-record", "-P", "{ stream.capture.sink=true node.name=mochi-beats }",
                            "--rate", str(RATE), "--channels", "1", "--format", "s16", "-"],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    buf = np.zeros(WIN, np.float32)
    win = np.hanning(WIN).astype(np.float32)
    prev = None
    env = np.zeros(HIST, np.float32)
    n = 0
    period = 0.0          # s
    conf = 0.0
    next_beat = 0.0
    last_tempo = 0.0
    t0 = time.monotonic()
    lo, hi = int(30 * WIN / RATE), int(4000 * WIN / RATE)
    while True:
        raw = rec.stdout.read(HOP * 2)
        if not raw or len(raw) < HOP * 2:
            break
        x = np.frombuffer(raw, np.int16).astype(np.float32) / 32768
        buf = np.concatenate([buf[HOP:], x])
        mag = np.log1p(40 * np.abs(np.fft.rfft(buf * win))[lo:hi])
        flux = 0.0 if prev is None else float(np.maximum(mag - prev, 0).sum())
        prev = mag
        env = np.roll(env, -1)
        env[-1] = flux
        n += 1
        now = n / FPS
        # silencio: nada que bailar
        if float(np.abs(x).max()) < 0.01:
            continue
        # tempo cada medio segundo
        if now - last_tempo > 0.5 and n > HIST // 2:
            last_tempo = now
            e = env - env.mean()
            ac = np.correlate(e, e, "full")[len(e) - 1:]
            lags = np.arange(len(ac))
            bpm_lag = (lags >= FPS * 60 / 180) & (lags <= FPS * 60 / 70)
            if ac[0] > 0:
                cand = np.where(bpm_lag)[0]
                # preferir tempos "de baile" (~100-130)
                w = np.exp(-0.5 * (np.log2((60 * FPS / cand) / 118)) ** 2 / 0.6 ** 2)
                best = cand[np.argmax(ac[cand] * w)]
                conf = float(ac[best] / ac[0])
                period = best / FPS
        if period <= 0:
            continue
        # golpes: pico local de ataque cerca del siguiente golpe previsto
        thr = env.mean() + 1.2 * env.std()
        is_peak = env[-2] > thr and env[-2] >= env[-3] and env[-2] >= env[-1]
        tpk = now - 1 / FPS
        if next_beat == 0 and is_peak:
            next_beat = tpk
        if next_beat:
            if is_peak and abs(tpk - next_beat) < 0.25 * period:
                emit(period)
                next_beat = tpk + period
            elif now > next_beat + 0.2 * period:
                if conf > 0.25:
                    emit(period)
                next_beat += period


def emit(period):
    print(f"beat {period:.3f}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass

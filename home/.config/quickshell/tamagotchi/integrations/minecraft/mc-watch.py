#!/usr/bin/env python3
# Sigue el log de Minecraft mientras juegas (Prism Launcher o ~/.minecraft) y cuenta a Mochi lo
# que pasa, una línea JSON por evento en stdout:
#   {"ev": "join"}                          entras en un mundo/servidor
#   {"ev": "quit"}                          cierras el juego
#   {"ev": "death", "text": …}              te mueres
#   {"ev": "advancement", "text": …}        consigues un logro
#   {"ev": "kill", "text": …}               matas a otro jugador
#   {"ev": "mention", "text": …, "from": …} alguien te nombra en el chat
# Los mensajes de muerte del log salen en inglés (los escribe el servidor), así que sirven igual.
import glob, json, os, re, sys, time

LOGS = [os.path.expanduser("~/.local/share/PrismLauncher/instances/*/minecraft/logs/latest.log"),
        os.path.expanduser("~/.local/share/PrismLauncher/instances/*/.minecraft/logs/latest.log"),
        os.path.expanduser("~/.minecraft/logs/latest.log")]
DEATH = re.compile(r"^(?:was |were |died|drowned|experienced|blew up|burned|went |walked into|hit the ground|fell|froze|starved|suffocated|tried to|withered|discovered|didn't want|left the confines|hit the ground)")
KILL = re.compile(r"^(\S+) was .* by (\S+?)(?: using .*)?$")
ADV = re.compile(r"^(\S+) has (?:made the advancement|completed the challenge|reached the goal) \[(.+)\]")
CHAT = re.compile(r"^(?:\[[^\]]*\] )*<([^>]+)> (.*)$")


def emit(**ev):
    print(json.dumps(ev), flush=True)


def newest():
    files = [f for pat in LOGS for f in glob.glob(pat)]
    return max(files, key=os.path.getmtime) if files else None


def follow(path, name):
    with open(path, errors="replace") as f:
        f.seek(0, os.SEEK_END)
        idle = 0
        while True:
            line = f.readline()
            if not line:
                time.sleep(0.5)
                idle += 0.5
                # el log se ha rotado (juego reiniciado) o hay otro más nuevo
                if idle > 5:
                    idle = 0
                    n = newest()
                    if n != path or os.path.getsize(path) < f.tell():
                        return name
                continue
            idle = 0
            name = handle(line.rstrip("\n"), name)


def handle(line, name):
    m = re.search(r"Setting user: (\S+)", line)
    if m:
        return m.group(1)
    if "Connecting to " in line or "Starting integrated minecraft server" in line:
        emit(ev="join")
        return name
    if re.search(r"\]: Stopping!$", line):
        emit(ev="quit")
        return name
    m = re.search(r"\[CHAT\] (.*)$", line) or re.search(r"\[Server thread/INFO\]: (.*)$", line)
    if not m or not name:
        return name
    msg = m.group(1).strip()
    # (en un mundo propio sale dos veces: del servidor y del chat; el chat basta)
    if "[Server thread" in line and "[CHAT]" not in line:
        return name
    a = ADV.match(msg)
    if a:
        if a.group(1) == name:
            emit(ev="advancement", text=a.group(2))
        return name
    if msg.startswith(name + " ") and DEATH.match(msg[len(name) + 1:]):
        emit(ev="death", text=msg)
        return name
    k = KILL.match(msg)
    if k and k.group(2) == name and k.group(1) != name:
        emit(ev="kill", text=msg)
        return name
    c = CHAT.match(msg)
    if c and c.group(1) != name:
        who, text = c.group(1), c.group(2)
        short = name.lower()[:4]
        if name.lower() in text.lower() or re.search(rf"\b{re.escape(short)}", text.lower()):
            emit(ev="mention", text=text, **{"from": who})
    return name


def main():
    name = None
    while True:
        p = newest()
        # solo si se está escribiendo ahora (jugando)
        if p and time.time() - os.path.getmtime(p) < 120:
            try:
                with open(p, errors="replace") as f:
                    for line in f:
                        m = re.search(r"Setting user: (\S+)", line)
                        if m:
                            name = m.group(1)
            except OSError:
                pass
            name = follow(p, name)
        else:
            time.sleep(10)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass

#!/usr/bin/env python3
"""Intro animada de hex-dev (autocontenida, paleta Dracula):
  1) bandada de murciélagos (nf-md-bat) cruza con parallax (profundidad)
  2) wordmark 'HexDev' en figlet 'ANSI Shadow': las caras del bloque (█) llevan
     degradé vertical (luz desde arriba) y las aristas (╗╝║═) van en violeta
     oscuro → 3D real; se dibuja izq→der y le pasa un barrido de brillo
  3) queda fijo con sigilo murciélago + tagline."""
import sys, time, math, shutil, random, subprocess

W, H = shutil.get_terminal_size((80, 24))
out = sys.stdout.write
def at(r, c, s): out(f"\033[{int(r)};{int(c)}H{s}")
def rgb(h): return f"\033[38;2;{int(h[0:2],16)};{int(h[2:4],16)};{int(h[4:6],16)}m"
RST = "\033[0m"
BAT = "\U000F0B5F"

FONTDIR = "/home/<user>/.local/share/figlet-fonts"
FACE = [rgb(h) for h in ("e6d4ff","d2b6fc","bd93f9","a87bef","9162d6","7a52bb")]  # caras: claro→oscuro
EDGE = rgb("3c2f63")     # aristas de sombra (violeta oscuro) → da el 3D
SHINE = rgb("ffffff")
PINK = rgb("ff79c6"); GREY = rgb("6272a4")
LAYERS = [ (rgb("584a7a"),2.2,1), (rgb("8a5fd0"),3.0,2), (rgb("bd93f9"),3.8,3), (rgb("ff79c6"),4.5,2) ]
BLOCK = "█"   # carácter de "cara" en ANSI Shadow

def figlet():
    try:
        o = subprocess.run(["figlet","-d",FONTDIR,"-f","ANSI Shadow","-w","200","HexDev"],
                           capture_output=True, text=True).stdout
    except Exception:
        o = "HexDev"
    lines = [ln.rstrip("\n") for ln in o.split("\n")]
    while lines and lines[-1].strip()=="" : lines.pop()
    while lines and lines[0].strip()=="" : lines.pop(0)
    return lines

def main():
    out("\033[?25l\033[2J")
    # ---------- 1) murciélagos ----------
    N = 22; bats = []
    for i in range(N):
        clr,spd,amp = random.choice(LAYERS)
        bats.append({"row":random.randint(2,max(3,H-2)), "col":-random.randint(1,max(2,W)),
                     "spd":spd*random.uniform(0.85,1.15), "amp":amp, "ph":random.uniform(0,6.283), "clr":clr})
    prev=[None]*N; frames=int(W/3.2)+8
    for f in range(frames):
        for i,b in enumerate(bats):
            c=b["col"]+b["spd"]*f; r=b["row"]+b["amp"]*math.sin(b["ph"]+f*0.45)
            if prev[i]: at(prev[i][0],prev[i][1]," ")
            if 1<=r<=H and 1<=c<=W:
                clr=b["clr"] if (f+i)%2 else FACE[0]
                at(r,c,clr+BAT+RST); prev[i]=(round(r),round(c))
            else: prev[i]=None
        sys.stdout.flush(); time.sleep(0.024)
    out("\033[2J")

    # ---------- 2) HexDev 3D + shimmer ----------
    lines=figlet(); height=len(lines); width=max((len(l) for l in lines),default=0)
    SR=max(2,H//2-height//2-1); SC=max(1,(W-width)//2)
    glyphs=[(r,c,ch) for r,l in enumerate(lines) for c,ch in enumerate(l) if ch!=" "]
    rowclr=lambda r: FACE[min(len(FACE)-1, r*len(FACE)//max(1,height))]
    def colorfor(r,ch): return rowclr(r) if ch==BLOCK else EDGE

    # dibujo izq→der (las aristas ya salen oscuras = 3D)
    step=0
    while step<=width:
        for r,c,ch in glyphs:
            if step-3<=c<=step: at(SR+r,SC+c,colorfor(r,ch)+ch+RST)
        sys.stdout.flush(); time.sleep(0.014); step+=4
    # barrido de brillo: solo ilumina las CARAS dentro de la banda
    band=8; x=-band
    while x<=width+band:
        for r,c,ch in glyphs:
            if ch==BLOCK and (x-band)<=c<=x: clr=SHINE
            else: clr=colorfor(r,ch)
            at(SR+r,SC+c,clr+ch+RST)
        sys.stdout.flush(); time.sleep(0.018); x+=4
    for r,c,ch in glyphs: at(SR+r,SC+c,colorfor(r,ch)+ch+RST)

    # ---------- 3) sigilo + tagline ----------
    at(SR+height+1, SC+2, f"{PINK}{BAT}{RST}  {GREY}in nocte, codex{RST}")
    out("\033[%d;1H\n" % H)

if __name__=="__main__":
    try: main()
    finally: out("\033[?25h"); sys.stdout.flush()

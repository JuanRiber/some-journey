"""O interior do vagao, a partir da ilustracao de marca.

    python tool/hero_interior.py        (de dentro de app_flutter/)

Le  assets/images/first-class-art.jpg   (a arte original, 1536x683)
Grava assets/images/first-class-interior.webp

Faz duas coisas, e so essas:

1. ABRE O VIDRO. A janela vira alfa zero, para a paisagem da cena (HeroScene)
   passar por tras do vagao. O contorno esta em GLASS, em pixels da arte: canto
   arredondado em cima, peitoril inclinado embaixo, e os dois recortes de quem
   esta na frente do vidro, o livro e o sapato.

2. TIRA AS BOLHAS PINTADAS. Na cena as bolhas sobem de verdade; as da pintura
   ficariam paradas no meio delas. Cada disco em BUBBLES e refeito puxando a
   cor ao longo do que esta por baixo: as dobras da cortina, que convergem
   para o laco; os frisos da moldura, que correm paralelos ao vidro; e a
   parede, na vertical. E um carimbo de clonagem que segue o desenho.

Precisa de Pillow e numpy (o venv do backend tem os dois). O resultado e
deterministico: rodar de novo sem mudar nada devolve o mesmo arquivo.
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

AQUI = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(AQUI, '..', 'assets', 'images', 'first-class-art.jpg')
OUT = os.path.join(AQUI, '..', 'assets', 'images', 'first-class-interior.webp')
W, H = 1536, 683


def top(x):
    """A travessa de cima do vidro: uma reta, medida na arte."""
    return 62 - 0.155 * (x - 660)


def bot(x):
    """O peitoril: a linha escura entre a paisagem e a madeira."""
    return 512 + 0.0925 * (x - 700)


GLASS = [
    # canto superior esquerdo (arco)
    (577.5, 150), (578, 135), (580, 118), (586, 102), (596, 88), (608, 78),
    (622, 70.5), (640, 65),
    # travessa de cima, ate sair pelo topo da arte
    (660, top(660)), (800, top(800)), (1000, top(1000)), (1060, -2),
    (1540, -2), (1540, bot(1540)),
    # peitoril, contornando o sapato
    (1339.5, bot(1339.5)), (1338, 548), (1333, 536), (1325, 529.5),
    (1314, 527), (1303, 530), (1293, 537.5), (1284, 549),
    (1277.5, bot(1277.5)),
    (660, bot(660)),
    # canto inferior esquerdo, contornando o livro
    (645, 505.5), (630, 498), (620, 488), (614, 478), (616, 466), (590, 462),
    (581, 448), (577.5, 430),
]


def mask(ss=4):
    """O vidro em branco, com a borda suavizada por superamostragem."""
    m = Image.new('L', (W * ss, H * ss), 0)
    ImageDraw.Draw(m).polygon([(x * ss, y * ss) for x, y in GLASS], fill=255)
    return m.resize((W, H), Image.LANCZOS)


rng = np.random.default_rng(7)
src = np.asarray(Image.open(SRC).convert('RGB')).astype(np.float64)
glass = np.asarray(mask()).astype(np.float64) / 255.0

# (cx, cy, r, campo)   campo: 'v' vertical · 'c' cortina (radial) · 'f' moldura
BUBBLES = [
  (401.5,254,23.5,'c'), (436.7,208,20,'c'), (466,153,21,'c'), (442,245,9,'c'),
  (491.7,210,19,'v'), (507,99,27,'v'), (536.7,166.7,28,'v'),
  (575.7,46.7,41,'f'), (625,2,21,'f'), (721.7,55,41,'f'),
]
MARGIN = 3.5
yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
union = np.zeros((H, W), bool)
for cx, cy, r, _ in BUBBLES:
    union |= (xx-cx)**2 + (yy-cy)**2 <= (r+MARGIN)**2
blocked = union | (glass > 0.5)

P = np.array(GLASS, float)
FX0, FX1, FY0, FY1 = 470, 800, 0, 150
gy, gx = np.mgrid[FY0:FY1, FX0:FX1].astype(np.float64)
bestd = np.full(gx.shape, 1e9); bqx = np.zeros(gx.shape); bqy = np.zeros(gx.shape)
for i in range(len(P)):
    a, b = P[i], P[(i+1) % len(P)]
    ab = b - a
    t = np.clip(((gx-a[0])*ab[0] + (gy-a[1])*ab[1]) / (ab @ ab), 0, 1)
    qx, qy = a[0]+t*ab[0], a[1]+t*ab[1]
    d = np.hypot(gx-qx, gy-qy)
    m = d < bestd
    bestd[m] = d[m]; bqx[m] = qx[m]; bqy[m] = qy[m]
bestd = np.maximum(bestd, 1e-6)
TX = -(gy-bqy)/bestd; TY = (gx-bqx)/bestd
def frame_tangent(x, y):
    ix = int(np.clip(round(x), FX0, FX1-1)) - FX0; iy = int(np.clip(round(y), FY0, FY1-1)) - FY0
    return (TX[iy, ix], TY[iy, ix])
V = (400.0, 340.0)
def direction(kind, x, y):
    if kind == 'v': return (0.0, 1.0)
    if kind == 'c':
        dx, dy = V[0]-x, V[1]-y
        n = np.hypot(dx, dy); return (dx/n, dy/n)
    return frame_tangent(x, y)

def sample(x, y):
    x0 = int(np.clip(np.floor(x), 0, W-2)); y0 = int(np.clip(np.floor(y), 0, H-2))
    fx, fy = np.clip(x-x0, 0, 1), np.clip(y-y0, 0, 1)
    return (src[y0,x0]*(1-fx)*(1-fy) + src[y0,x0+1]*fx*(1-fy)
            + src[y0+1,x0]*(1-fx)*fy + src[y0+1,x0+1]*fx*fy)

def walk(kind, x, y, sign):
    px, py = x, y
    last = None
    for step in range(1, 260):
        dx, dy = direction(kind, px, py)
        if last is not None and dx*last[0] + dy*last[1] < 0: dx, dy = -dx, -dy
        if last is None: dx, dy = dx*sign, dy*sign
        last = (dx, dy)
        px += dx; py += dy
        if not (0 <= px < W-1 and 0 <= py < H-1): return None
        ix, iy = int(round(px)), int(round(py))
        if glass[iy, ix] > 0.5: return None
        if not blocked[iy, ix]:
            # media de alguns passos alem da borda: tira o ruido de um pixel so
            acc = sample(px, py); n = 1
            qx, qy = px, py
            for _ in range(3):
                ddx, ddy = direction(kind, qx, qy)
                if ddx*last[0] + ddy*last[1] < 0: ddx, ddy = -ddx, -ddy
                qx += ddx; qy += ddy
                if not (0 <= qx < W-1 and 0 <= qy < H-1): break
                if blocked[int(round(qy)), int(round(qx))]: break
                acc = acc + sample(qx, qy); n += 1
            return step, acc / n
    return None

out = src.copy()
for cx, cy, r, kind in BUBBLES:
    R = r + MARGIN
    for y in range(max(0, int(cy-R)), min(H, int(cy+R)+1)):
        for x in range(max(0, int(cx-R)), min(W, int(cx+R)+1)):
            if (x-cx)**2 + (y-cy)**2 > R*R or glass[y, x] > 0.5: continue
            a = walk(kind, x, y, +1); b = walk(kind, x, y, -1)
            if a and b:
                wa, wb = b[0], a[0]
                c = (a[1]*wa + b[1]*wb) / (wa+wb)
            elif a or b: c = (a or b)[1]
            else: continue
            out[y, x] = c
# grao: a tinta nao e lisa
noise = rng.normal(0, 3.0, (H, W))
noise = np.asarray(Image.fromarray(np.clip(noise*8+128, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))).astype(float)
noise = (noise-128)/8
soft = np.asarray(Image.fromarray((union*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))).astype(float)/255
filled = out + noise[..., None]
res = src*(1-soft[..., None]) + filled*soft[..., None]
res = np.clip(res, 0, 255)

# vidro: alfa 0, e por baixo dele um castanho escuro (sem halo no filtro)
alpha = 1 - glass
dark = np.array([28, 18, 12], float)
rgb = res*alpha[..., None] + dark*(1-alpha[..., None])
rgba = np.dstack([rgb, alpha*255]).astype(np.uint8)
im = Image.fromarray(rgba, 'RGBA')
im.save(OUT, quality=86, method=6, alpha_quality=100)
print(os.path.relpath(OUT), os.path.getsize(OUT), 'bytes')

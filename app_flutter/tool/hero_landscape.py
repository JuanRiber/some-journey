"""A paisagem da janela, tirada da propria ilustracao de marca.

    python tool/hero_landscape.py        (de dentro de app_flutter/)

Le    assets/images/first-class-art.jpg       (a arte original, 1536x683)
Grava assets/images/first-class-landscape.webp (o atlas que a HeroScene rola)

A ilustracao tem UMA janela de paisagem, parada, e com o logo por cima do ceu.
Para a viagem passar atras do vidro ela precisa virar tiras sem fim, em planos
que andam a velocidades diferentes. Nada aqui e desenhado: todo pixel do atlas
saiu da pintura. O que o script faz e recortar, estender e costurar.

  serra    a cadeia inteira, recortada na linha do ceu, e estendida para os
           dois lados por espelho cisalhado: a encosta que a moldura cortou
           continua descendo ate sumir atras do vale.
  vale     colinas, rio e campos, ida e volta. O espelho sozinho desenha uma
           figura simetrica em cada emenda; por isso cada lado e esticado de um
           jeito, a volta leva um empeno suave, e o miolo de cada emenda e
           coberto por um pedaco da mesma paisagem que nao foi espelhado.
  prado    as flores, por costura de retalhos (image quilting): pedacos da
           faixa de baixo colados lado a lado pelo corte de menor diferenca.
  nuvens   recortadas do ceu limpo, pela distancia entre a cor do pixel e a cor
           que o ceu teria naquela altura.
  ladrilhos o grao da tinta do ceu e a rocha da serra, para o ceu e o corte do
           tunel nao serem lisos ao lado de uma pintura.

As linhas de corte (ceu/serra e serra/vale) saem de um caminho de menor custo
em volta de uma guia marcada a mao: a guia diz mais ou menos por onde, o
caminho acha o traco de nanquim.

Precisa de Pillow e numpy (o venv do backend tem os dois) e leva cerca de um
minuto. O resultado e deterministico. No fim imprime os retangulos do atlas,
que estao copiados em `lib/features/hero/scene_domain.dart` (HeroAtlas): mudou
alguma medida aqui, e la que ela tem de ser atualizada.
"""
import os

import numpy as np
from PIL import Image

AQUI = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(AQUI, '..', 'assets', 'images', 'first-class-art.jpg')
OUT = os.path.join(AQUI, '..', 'assets', 'images', 'first-class-landscape.webp')
W, H = 1536, 683

img = np.asarray(Image.open(SRC).convert('RGB')).astype(np.float64)
X0, X1 = 584, 1536                     # colunas uteis da paisagem
XS = np.arange(X0, X1)


# ----------------------------------------------------------------- utilitarios

def smoothstep(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def blur(a, r):
    """Gaussiano separavel (o do Pillow nao aceita ponto flutuante)."""
    n = int(np.ceil(r * 3))
    k = np.exp(-0.5 * (np.arange(-n, n + 1) / r) ** 2)
    k /= k.sum()
    pad = np.pad(a, ((0, 0), (n, n)), mode='edge')
    a = sum(k[i] * pad[:, i:i + a.shape[1]] for i in range(2 * n + 1))
    pad = np.pad(a, ((n, n), (0, 0)), mode='edge')
    return sum(k[i] * pad[i:i + a.shape[0], :] for i in range(2 * n + 1))


def medfilt(a, k):
    pad = np.pad(a, k // 2, mode='edge')
    return np.array([np.median(pad[i:i + k]) for i in range(len(a))])


def sample(src, xf, yf):
    """Bilinear em src (h, w, c); fora da imagem devolve zero (transparente)."""
    h, w = src.shape[:2]
    x0 = np.floor(xf).astype(int)
    y0 = np.floor(yf).astype(int)
    fx = (xf - x0)[..., None]
    fy = (yf - y0)[..., None]

    def at(yy, xx):
        ok = (xx >= 0) & (xx < w) & (yy >= 0) & (yy < h)
        return src[np.clip(yy, 0, h - 1), np.clip(xx, 0, w - 1)] * ok[..., None]

    return (at(y0, x0) * (1 - fx) * (1 - fy) + at(y0, x0 + 1) * fx * (1 - fy)
            + at(y0 + 1, x0) * (1 - fx) * fy + at(y0 + 1, x0 + 1) * fx * fy)


def premult(rgb, a):
    return np.dstack([rgb * a[..., None], a * 255.0])


def unpremult(pm):
    a = pm[..., 3:4] / 255.0
    rgb = np.where(a > 1e-4, pm[..., :3] / np.maximum(a, 1e-4), 0)
    return np.dstack([np.clip(rgb, 0, 255), pm[..., 3]])


def sill(x):
    """O peitoril: abaixo dele a arte e madeira, nao paisagem."""
    return 512 + 0.0925 * (x - 700)


# ------------------------------------------------------------ linhas de corte

SKY_GUIDE = [
    (578, 283), (600, 272), (623, 262), (640, 272), (660, 281), (675, 298),
    (694, 308), (720, 290), (740, 278), (771, 273), (790, 290), (810, 310),
    (831, 340), (850, 352), (868, 363), (880, 377), (900, 381), (930, 386),
    (970, 383), (990, 387), (1008, 380), (1030, 388), (1055, 394), (1087, 388),
    (1110, 398), (1150, 408), (1190, 410), (1210, 405), (1240, 395),
    (1260, 388), (1280, 381), (1300, 390), (1320, 392), (1333, 389),
    (1352, 384), (1375, 372), (1400, 358), (1427, 347), (1447, 333),
    (1468, 321), (1493, 333), (1500, 332), (1520, 322), (1536, 315),
]
MID_GUIDE = [
    (578, 378), (650, 382), (700, 395), (750, 403), (800, 403), (850, 405),
    (900, 420), (930, 435), (1000, 438), (1100, 442), (1150, 445), (1210, 447),
    (1220, 452), (1267, 442), (1300, 435), (1350, 422), (1400, 412),
    (1433, 407), (1467, 403), (1500, 397), (1536, 387),
]


def trace(points, cost, band, smooth):
    """O caminho de menor custo dentro de um corredor em volta da guia."""
    px, py = zip(*points)
    g = np.interp(XS, px, py)
    ys = np.arange(-band, band + 1)
    c = np.empty((len(XS), len(ys)))
    for i, x in enumerate(XS):
        yy = np.clip(np.round(g[i]).astype(int) + ys, 2, H - 3)
        c[i] = cost[yy, x] + 0.02 * np.abs(ys)        # puxa de leve para a guia
    d = c.copy()
    back = np.zeros(c.shape, int)
    for i in range(1, len(XS)):
        shift = int(round(g[i] - g[i - 1]))           # o corredor anda com a guia
        for j in range(len(ys)):
            best, arg = 1e18, j
            for dj in (-2, -1, 0, 1, 2):
                k = j + dj + shift
                if 0 <= k < len(ys):
                    v = d[i - 1, k] + smooth * abs(dj)
                    if v < best:
                        best, arg = v, k
            d[i, j] = c[i, j] + best
            back[i, j] = arg
    j = int(np.argmin(d[-1]))
    path = np.empty(len(XS))
    for i in range(len(XS) - 1, -1, -1):
        path[i] = np.round(g[i]) + ys[j]
        j = back[i, j]
    return path


def cut_lines():
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    # ceu -> serra: claro em cima, o traco escuro da crista embaixo
    drop = np.zeros_like(lum)
    drop[2:-2] = (lum[:-4] + lum[1:-3]) / 2 - (lum[2:-2] + lum[3:-1]) / 2
    sky = trace(SKY_GUIDE, -np.clip(drop, 0, 120) / 40.0, band=9, smooth=0.35)
    # serra -> vale: fica mais verde e mais escuro para baixo
    green = g - (r + b) / 2
    gd = np.zeros_like(lum)
    gd[3:-3] = ((green[4:-2] + green[5:-1] + green[6:]) - (green[:-6] + green[1:-5] + green[2:-4])) / 3
    ld = np.zeros_like(lum)
    ld[3:-3] = ((lum[:-6] + lum[1:-5] + lum[2:-4]) - (lum[4:-2] + lum[5:-1] + lum[6:])) / 3
    mid = trace(MID_GUIDE, -(np.clip(gd, 0, 40) / 14.0 + np.clip(ld, 0, 80) / 40.0), band=9, smooth=0.6)
    # O S de "ATLAS" encosta na crista e o caminho o contornava: ali a linha e reta.
    i0, i1 = 1427 - X0, 1450 - X0
    sky[i0:i1 + 1] = np.linspace(sky[i0], sky[i1], i1 - i0 + 1)
    # A faixa palida do fundo do vale fica com a serra: na frente de outra
    # montanha ela vira uma tira de neblina solta. A linha desce ate o pe dela
    # e volta a subir na ponta da mata, devagar dos dois lados — um degrau ali
    # vira um penhasco no meio do campo.
    floor = np.interp(XS, [1039, 1040, 1110, 1215, 1240, 1241], [0, 438, 456, 456, 448, 0])
    mid = np.maximum(medfilt(mid, 7), floor)
    return sky, mid


def without_lettering(sky):
    """Apaga os restos das letras do logo que encostam na serra."""
    clean = img.copy()
    r, g, b = clean[..., 0], clean[..., 1], clean[..., 2]
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    for xa, xb in ((826, 894), (1422, 1454)):
        for x in range(xa, xb):
            y0 = int(sky[x - X0])
            for y in range(y0 - 1, y0 + 13):
                if r[y, x] - b[y, x] > 30 and lum[y, x] < 125 and g[y, x] < r[y, x]:
                    clean[y, x] = clean[y + 13, x + 2]       # a encosta logo abaixo
    return clean


# ----------------------------------------------------------------------- serra

FAR_TOP, FAR_BOT = 244, 462            # linhas da arte que a tira cobre
FAR_X0 = 590
FAR_SRC_TOP = 40                       # o espelho cisalhado busca linhas bem acima
FAR_EXT_L, FAR_EXT_R, FAR_FADE = 270, 210, 40


def far_strip(clean, sky):
    yy = np.arange(FAR_SRC_TOP, FAR_BOT + 8)[:, None].astype(np.float64)
    a = np.clip((yy - sky[None, FAR_X0 - X0:] + 0.2) / 1.6, 0, 1)
    rgb = clean[FAR_SRC_TOP:FAR_BOT + 8, FAR_X0:X1].copy()
    rgb[440 - FAR_SRC_TOP:, :16] = rgb[440 - FAR_SRC_TOP:, 18:34][:, ::-1]   # canto do livro
    # na borda, a cor e a da serra (3 px abaixo), nao a do ceu que sobrou no pixel
    below = clean[FAR_SRC_TOP + 3:FAR_BOT + 11, FAR_X0:X1]
    rgb = np.where((a < 0.999)[..., None], below, rgb)
    pm = premult(rgb, a)
    w = X1 - FAR_X0
    total = FAR_EXT_L + w + FAR_EXT_R
    xo = np.arange(total, dtype=np.float64)[None, :]
    yo = np.arange(FAR_TOP, FAR_BOT, dtype=np.float64)[:, None]
    hh = yo.shape[0]
    xf = np.where((xo >= FAR_EXT_L) & (xo < FAR_EXT_L + w), xo - FAR_EXT_L, 0.0)
    dy = np.zeros_like(xo)
    # para a esquerda: espelho em torno da borda, esticado, e descendo
    dl = np.clip(FAR_EXT_L - xo, 0, None)
    xf = np.where(xo < FAR_EXT_L, dl * 0.80, xf)
    dy = np.where(xo < FAR_EXT_L, 0.62 * dl + 0.0009 * dl * dl, dy)
    # para a direita, o mesmo com outros numeros (senao os dois lados rimam)
    dr = np.clip(xo - (FAR_EXT_L + w - 1), 0, None)
    xf = np.where(xo >= FAR_EXT_L + w, (w - 1) - dr * 0.90, xf)
    dy = np.where(xo >= FAR_EXT_L + w, 0.42 * dr + 0.0012 * dr * dr, dy)
    # um empeno leve, so nas extensoes: o miolo e a pintura intocada
    rng = np.random.default_rng(41)
    wx = np.zeros((hh, total))
    wy = np.zeros((hh, total))
    for kx, ky, amp in ((9, 1.1, 5.0), (17, 1.9, 3.0), (27, 0.7, 2.0)):
        p = rng.uniform(0, 2 * np.pi, 4)
        wx += amp * np.sin(2 * np.pi * kx * xo / total + p[0]) * np.cos(2 * np.pi * ky * (yo - FAR_TOP) / hh + p[1])
        wy += amp * np.sin(2 * np.pi * kx * xo / total + p[2]) * np.cos(2 * np.pi * ky * (yo - FAR_TOP) / hh + p[3])
    wgt = np.maximum(smoothstep(dl / 60.0), smoothstep(dr / 60.0))
    xf = np.broadcast_to(xf, (hh, total)) + wx * wgt
    yf = np.broadcast_to(yo - dy - FAR_SRC_TOP, (hh, total)) + wy * wgt
    out = sample(pm, np.clip(xf, 0, w - 1.001), yf)
    # fecha o ciclo: o fim de uma extensao dissolve no comeco da outra, la embaixo
    period = total - FAR_FADE
    t = (np.arange(FAR_FADE) / (FAR_FADE - 1))[None, :, None]
    out[:, :FAR_FADE] = out[:, period:period + FAR_FADE] * (1 - t) + out[:, :FAR_FADE] * t
    return unpremult(out[:, :period])


# ------------------------------------------------------------------------ vale

MID_TOP, MID_BOT = 366, 514
MID_X0 = 640
MID_PERIOD = 2129
MID_EXTRA = 48                         # linhas a mais, so para os remendos


def mid_strip(clean, mid):
    cols = np.arange(MID_X0, X1)
    w = len(cols)
    h = MID_BOT - MID_TOP
    yy = np.arange(MID_TOP, MID_BOT + MID_EXTRA)[:, None].astype(np.float64)
    feather = np.interp(cols, [640, 1200, 1240, 1536], [3.2, 3.2, 2.6, 2.6])[None, :]
    a = smoothstep((yy - mid[None, MID_X0 - X0:] + feather * 0.25) / feather)
    rgb = clean[MID_TOP:MID_BOT + MID_EXTRA, MID_X0:X1].copy()
    # o que na arte e peitoril vira prado: espelha em torno da borda valida
    lim = (sill(cols) - 4.0)[None, :]
    mirror = np.clip(np.round(2 * lim - yy).astype(int) - MID_TOP, 0, rgb.shape[0] - 1)
    ci = np.broadcast_to(np.arange(w)[None, :], mirror.shape)
    rgb = np.where((yy > lim)[..., None], rgb[mirror, ci], rgb)
    pm = premult(rgb, a)

    # ida e volta; em cada trecho a escala cai de s0 a s1, e por isso os dois
    # lados de uma emenda tem larguras diferentes
    segs = [(1.32, 1.02), (1.36, 1.00)]
    lens = [w * (s1 - s0) / np.log(s1 / s0) for s0, s1 in segs]
    k = MID_PERIOD / sum(lens)
    lens = [ln * k for ln in lens]
    xo = np.arange(MID_PERIOD, dtype=np.float64)
    u = np.empty(MID_PERIOD)
    start = 0.0
    for i, ((s0, s1), ln) in enumerate(zip(segs, lens)):
        m = (xo >= start) & (xo < start + ln + 1e-9)
        tau = (xo[m] - start) / ln
        pos = ln / k * np.log((s0 + (s1 - s0) * tau) / s0) / (s1 - s0)      # 0..w
        u[m] = pos if i == 0 else (w - 1) - pos
        start += ln
    u = np.clip(u, 0, w - 1.001)
    seam = lens[0]

    # empeno suave e NAO simetrico: a volta inteira, e a ida so perto das emendas
    gx = xo[None, :]
    gy = np.arange(h, dtype=np.float64)[:, None]
    rng = np.random.default_rng(31)
    dx = np.zeros((h, MID_PERIOD))
    dy = np.zeros((h, MID_PERIOD))
    for kx, ky, amp in ((17, 1.3, 4.0), (29, 2.1, 2.6), (43, 0.8, 1.8), (11, 1.7, 3.2)):
        p = rng.uniform(0, 2 * np.pi, 4)
        dx += amp * np.sin(2 * np.pi * kx * gx / MID_PERIOD + p[0]) * np.cos(2 * np.pi * ky * gy / h + p[1])
        dy += 0.8 * amp * np.sin(2 * np.pi * kx * gx / MID_PERIOD + p[2]) * np.cos(2 * np.pi * ky * gy / h + p[3])
    dist = np.minimum(np.abs(gx - seam), np.minimum(gx, MID_PERIOD - gx))
    wgt = np.broadcast_to(np.where(gx > seam, 1.0, smoothstep(1 - dist / 110.0)), (h, MID_PERIOD))
    xw = np.mod(gx + dx * wgt, MID_PERIOD)
    i0 = np.floor(xw).astype(int)
    f = xw - i0
    ua, ub = u[i0], u[(i0 + 1) % MID_PERIOD]
    uu = np.where(np.abs(ub - ua) > 5, ua, ua * (1 - f) + ub * f)       # sem atravessar o salto do ciclo
    out = sample(pm, uu, np.clip(gy + dy * wgt, 0, h - 1.001))

    # Remendo: no miolo de cada emenda o espelho ainda desenha uma figura
    # simetrica (uma "cara" na copa das arvores). Por cima vai um pedaco da
    # MESMA paisagem, sem espelho e sem deformar. A silhueta continua a da tira.
    def patch(center, src_from, src_to, half, dy_patch=0.0):
        x0 = int(center - half)
        cols_o = np.arange(x0, x0 + 2 * half)
        t = (cols_o - x0) / (2 * half - 1)
        xs_src = src_from + t * (src_to - src_from) - MID_X0
        p = sample(pm, np.broadcast_to(xs_src[None, :], (h, 2 * half)),
                   np.broadcast_to(gy + dy_patch, (h, 2 * half)))
        idx = cols_o % MID_PERIOD
        base = out[:, idx]
        wp = (smoothstep(1 - np.abs(t * 2 - 1))[None, :] ** 0.7) * (p[..., 3] / 255.0) * (base[..., 3] / 255.0)
        pa = np.maximum(p[..., 3:4], 1e-3)
        ba = np.maximum(base[..., 3:4], 1e-3)
        rgb_ = (base[..., :3] / ba * 255.0) * (1 - wp[..., None]) + (p[..., :3] / pa * 255.0) * wp[..., None]
        out[:, idx, :3] = rgb_ * base[..., 3:4] / 255.0

    patch(seam, 1368, 1532, 96)                    # a mata, na emenda do meio
    patch(0.0, 690, 880, 110, dy_patch=14.0)       # a encosta, na emenda do ciclo
    return unpremult(out), u, seam


# ----------------------------------------------------------------------- prado

def quilt(src, period, block, overlap, seed):
    """Costura de retalhos na horizontal, com corte de menor erro, e ciclica."""
    rng = np.random.default_rng(seed)
    h, w, _ = src.shape
    step = block - overlap
    n = int(np.ceil(period / step))
    out = np.zeros((h, n * step + overlap, 3))
    offs = np.arange(0, w - block + 1)
    prev = int(rng.choice(offs))
    out[:, :block] = src[:, prev:prev + block]

    def seam(a, b):
        e = ((a - b) ** 2).sum(axis=2)
        d = e.copy()
        for y in range(1, h):
            left = np.r_[np.inf, d[y - 1, :-1]]
            right = np.r_[d[y - 1, 1:], np.inf]
            d[y] += np.minimum(np.minimum(left, d[y - 1]), right)
        path = np.empty(h, int)
        path[-1] = int(np.argmin(d[-1]))
        for y in range(h - 2, -1, -1):
            j = path[y + 1]
            lo, hi = max(0, j - 1), min(overlap, j + 2)
            path[y] = lo + int(np.argmin(d[y, lo:hi]))
        jj = np.arange(overlap)[None, :]
        return np.clip((jj - path[:, None] + 1.5) / 3.0, 0, 1)[..., None]

    for i in range(1, n):
        x = i * step
        tgt = out[:, x:x + overlap]
        cost = np.array([((src[:, c:c + overlap] - tgt) ** 2).sum() for c in offs])
        if i == n - 1:                               # o ultimo tambem casa com o comeco
            head = out[:, :overlap]
            cost = cost + np.array([((src[:, c + step:c + block] - head) ** 2).sum() for c in offs])
        cost[np.abs(offs - (prev + step)) < 6] = np.inf     # nada de copia corrida
        cost[np.abs(offs - prev) < 10] = np.inf
        ok = np.where(cost <= np.nanmin(cost[np.isfinite(cost)]) * 1.12)[0]
        prev = int(offs[rng.choice(ok)])
        blk = src[:, prev:prev + block]
        m = seam(tgt, blk[:, :overlap])
        out[:, x:x + overlap] = tgt * (1 - m) + blk[:, :overlap] * m
        out[:, x + overlap:x + block] = blk[:, overlap:]
    length = n * step
    m = seam(out[:, length:length + overlap], out[:, :overlap])
    out[:, :overlap] = out[:, length:length + overlap] * (1 - m) + out[:, :overlap] * m
    res = out[:, :length]
    xf = np.linspace(0, length, period, endpoint=False)          # poucos por cento de ajuste
    i0 = np.floor(xf).astype(int)
    f = (xf - i0)[None, :, None]
    return res[:, i0 % length] * (1 - f) + res[:, (i0 + 1) % length] * f


def wavy_top(h, period, base, seed, amp, soft):
    """A borda de tras do prado: ondulada e macia, e ciclica."""
    ph = np.random.default_rng(seed).uniform(0, 2 * np.pi, 2)
    x = np.arange(period) / period
    top = base + amp[0] * np.sin(2 * np.pi * 3 * x + ph[0]) + amp[1] * np.sin(2 * np.pi * 8 * x + ph[1])
    return smoothstep((np.arange(h)[:, None] - top[None, :]) / soft)


BACK_PERIOD, FRONT_PERIOD = 1774, 2129


def meadow_strips(clean):
    back = quilt(clean[490:544, 1345:1536], BACK_PERIOD, block=46, overlap=15, seed=5)     # flor miuda
    back = np.dstack([back, wavy_top(back.shape[0], BACK_PERIOD, 5.5, 6, (4.5, 2.5), 7.0) * 255])
    # o da frente: a mesma faixa, ampliada (flor maior = mais perto), e sem a
    # margarida nem o tufo vermelho, que repetidos viravam uma guirlanda
    src = Image.fromarray(clean[514:558, 1345:1495].astype(np.uint8)).resize((225, 66), Image.LANCZOS)
    front = quilt(np.asarray(src).astype(np.float64), FRONT_PERIOD, block=64, overlap=20, seed=7)
    front = np.dstack([front, wavy_top(front.shape[0], FRONT_PERIOD, 6.5, 8, (5.0, 3.0), 8.0) * 255])
    return back, front


# ---------------------------------------------------------------------- nuvens

SKY_TOP = np.array([106, 145, 156.])       # o azul do alto, medido na pintura
SKY_HOR = np.array([244, 223, 178.])       # o creme da barra
HORIZON = 392.0
CREAM = np.array([248, 234, 196.])
CLOUD_PERIOD, CLOUD_ROWS = 1400, 300


def cloud_strip(sky):
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
    t = np.clip(yy / HORIZON, 0, 1)[..., None]
    g = SKY_TOP * (1 - t) + SKY_HOR * t                     # o ceu que haveria ali
    d = CREAM - g
    den = (d ** 2).sum(-1)
    tt = ((img - g) * d).sum(-1) / np.maximum(den, 1.0)     # 0 = ceu, 1 = nuvem
    tt *= smoothstep((np.sqrt(den) - 22) / 30)              # perto do horizonte o ceu ja e creme
    alpha = smoothstep((tt - 0.22) / 0.50)
    skyline = np.full(W, 1e9)
    skyline[X0:X1] = sky

    def sprite(rects, feather=9.0, bottom=None):
        m = np.zeros((H, W))
        for x0, x1, y0, y1 in rects:
            m[y0:y1, x0:x1] = 1
        m[yy > skyline[None, :] - 2] = 0
        soft = smoothstep((blur(m, feather) - 0.5) / 0.5) * m
        # o corpo da nuvem: fecha os buracos que a sombra azulada abre no recorte
        body = smoothstep((blur(alpha * m, 5.0) - 0.22) / 0.34)
        a = np.maximum(alpha, body * 0.97) * soft
        if bottom is not None:
            a = a * smoothstep((bottom - yy) / 18.0)
        ys_, xs_ = np.where(a > 0.02)
        y0, y1, x0, x1 = ys_.min(), ys_.max() + 1, xs_.min(), xs_.max() + 1
        a = a[y0:y1, x0:x1]
        p = img[y0:y1, x0:x1]
        # na borda tira o azul misturado; no miolo a cor e a da pintura
        edge = (p - (1 - a[..., None]) * g[y0:y1, x0:x1]) / np.maximum(a[..., None], 0.25)
        wgt = smoothstep((a - 0.25) / 0.5)[..., None]
        return np.dstack([np.clip(edge * (1 - wgt) + p * wgt, 0, 255), a * 255])

    # so o ceu que o logo e as bolhas pintadas nao cobrem
    big = sprite([(1256, 1536, 14, 153), (1354, 1536, 153, 224)], feather=16.0)
    bank = sprite([(680, 862, 138, 270), (642, 680, 170, 270)], feather=11.0, bottom=258)
    wisp = sprite([(736, 842, 99, 151)], feather=5.0)

    strip = np.zeros((CLOUD_ROWS, CLOUD_PERIOD, 4))

    def put(s, x, y, scale=1.0, flip=False):
        im = Image.fromarray(s.astype(np.uint8), 'RGBA')
        if flip:
            im = im.transpose(Image.FLIP_LEFT_RIGHT)
        if scale != 1.0:
            im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
        a = np.asarray(im).astype(np.float64)
        h, w = a.shape[:2]
        for dx in (0, -CLOUD_PERIOD, CLOUD_PERIOD):         # a tira e ciclica
            x0 = x + dx
            sx0, sx1 = max(0, -x0), min(w, CLOUD_PERIOD - x0)
            if sx1 <= sx0:
                continue
            sy1 = min(h, CLOUD_ROWS - y)
            src = a[:sy1, sx0:sx1]
            dst = strip[y:y + sy1, x0 + sx0:x0 + sx1]
            sa = src[..., 3:4] / 255.0
            da = dst[..., 3:4] / 255.0
            oa = sa + da * (1 - sa)
            dst[..., :3] = (src[..., :3] * sa + dst[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-4)
            dst[..., 3:4] = oa * 255

    # a vista do campo e [183, 1141] da tira; a da serra vai ate 1341
    put(bank, 30, 150, 0.8)
    put(wisp, 250, 92, 1.25, flip=True)
    put(big, 520, 34)
    put(wisp, 905, 156, 0.9)
    put(bank, 1010, 112, 1.05, flip=True)
    put(wisp, 1262, 40, 1.5)
    return np.clip(strip, 0, 255)


# ------------------------------------------------------------------- ladrilhos

TILE_W, TILE_H = 384, 192


def canvas_tile():
    """So o grao fino da tinta (o que e maior vira estampa ao repetir),
    embaralhado em retalhos para o ladrilho nao ter eixo de espelho."""
    patch = img[8:56, 1062:1246].mean(axis=2)
    ratio = patch / blur(patch, 3.2)
    rng = np.random.default_rng(3)
    blk, ov = 32, 10
    step = blk - ov
    acc = np.zeros((TILE_H + blk, TILE_W + blk))
    wsum = np.zeros_like(acc)
    ramp = np.minimum(np.arange(blk) + 1, ov) / ov
    edge = np.minimum(ramp, ramp[::-1])
    win = np.minimum.outer(edge, edge)
    for y in range(0, TILE_H, step):
        for x in range(0, TILE_W, step):
            sy = rng.integers(0, ratio.shape[0] - blk + 1)
            sx = rng.integers(0, ratio.shape[1] - blk + 1)
            b = ratio[sy:sy + blk, sx:sx + blk]
            if rng.random() < 0.5:
                b = b[:, ::-1]
            if rng.random() < 0.5:
                b = b[::-1]
            acc[y:y + blk, x:x + blk] += b * win
            wsum[y:y + blk, x:x + blk] += win
    acc[:blk, :] += acc[TILE_H:TILE_H + blk, :]             # dobra as sobras: fecha nas duas direcoes
    wsum[:blk, :] += wsum[TILE_H:TILE_H + blk, :]
    acc[:, :blk] += acc[:, TILE_W:TILE_W + blk]
    wsum[:, :blk] += wsum[:, TILE_W:TILE_W + blk]
    tile = acc[:TILE_H, :TILE_W] / np.maximum(wsum[:TILE_H, :TILE_W], 1e-6)
    tile = np.clip(tile / np.percentile(tile, 99.7), 0, 1)
    tile = 1 - 0.7 * (1 - tile)                              # e multiplicado por cima do ceu: de leve
    return np.dstack([tile * 255] * 3 + [np.full_like(tile, 255.0)]), float(tile.mean())


ROCK_ROWS = 4


def rock_tile(clean):
    """A rocha da serra, para o corte do tunel.

    Ciclica so na horizontal, por costura de retalhos. Na vertical sao faixas
    diferentes empilhadas e fundidas: espelhar ali desenha losangos, e um
    losango que passa a cada volta e a primeira coisa que o olho acha.
    """
    ov = 12
    rows = [quilt(clean[312:372, 600:792], TILE_W, block=56, overlap=18, seed=13 + i) for i in range(ROCK_ROWS)]
    h = rows[0].shape[0]
    tile = rows[0]
    ramp = (np.arange(ov) / (ov - 1))[:, None, None]
    for r in rows[1:]:
        blend = tile[-ov:] * (1 - ramp) + r[:ov] * ramp
        tile = np.vstack([tile[:-ov], blend, r[ov:]])
    return np.dstack([tile, np.full(tile.shape[:2], 255.0)])


# ----------------------------------------------------------------------- atlas

PAD = 2


def pack(parts):
    """Empilha as pecas com uma margem em volta de cada uma.

    A margem repete a propria peca do outro lado (as tiras e os ladrilhos sao
    ciclicos na horizontal): sem ela, o filtro bilinear puxaria o vizinho do
    atlas para dentro da emenda, e apareceria um fio a cada volta.
    """
    def padded(a, wrap_y):
        a = np.concatenate([a[:, -PAD:], a, a[:, :PAD]], axis=1)
        top, bot = (a[-PAD:], a[:PAD]) if wrap_y else (a[:1].repeat(PAD, 0), a[-1:].repeat(PAD, 0))
        return np.concatenate([top, a, bot], axis=0)

    rects = {}
    width = max(x + a.shape[1] + 2 * PAD for _, a, x, _, _ in parts)
    height = max(y + a.shape[0] + 2 * PAD for _, a, _, y, _ in parts)
    atlas = np.zeros((height, width, 4))
    for name, a, x, y, wrap_y in parts:
        p = padded(a, wrap_y)
        atlas[y:y + p.shape[0], x:x + p.shape[1]] = p
        rects[name] = (x + PAD, y + PAD, a.shape[1], a.shape[0])
    return atlas, rects


if __name__ == '__main__':
    sky, mid = cut_lines()
    clean = without_lettering(sky)
    far = far_strip(clean, sky)
    valley, u_mid, seam = mid_strip(clean, mid)
    back, front = meadow_strips(clean)
    clouds = cloud_strip(sky)
    canvas, canvas_mean = canvas_tile()
    rock = rock_tile(clean)

    col = CLOUD_PERIOD + 2 * PAD + 6
    y_far = CLOUD_ROWS + 2 * PAD
    y_mid = y_far + far.shape[0] + 2 * PAD
    y_back = y_mid + valley.shape[0] + 2 * PAD
    y_front = y_back + back.shape[0] + 2 * PAD
    atlas, rects = pack([
        ('clouds', clouds, 0, 0, False),
        ('canvas', canvas, col, 0, True),
        ('rock', rock, col, TILE_H + 2 * PAD, False),
        ('far', far, 0, y_far, False),
        ('valley', valley, 0, y_mid, False),
        ('back', back, 0, y_back, False),
        ('front', front, 0, y_front, False),
    ])
    Image.fromarray(np.clip(atlas, 0, 255).astype(np.uint8), 'RGBA').save(
        OUT, quality=84, method=6, alpha_quality=92)
    print(os.path.relpath(OUT), atlas.shape[1], 'x', atlas.shape[0], os.path.getsize(OUT), 'bytes')
    print('retangulos (x, y, largura, altura):')
    for name, r in rects.items():
        print(f'  {name:7s} {r}')
    print('grao do ceu, media:', round(canvas_mean, 4))
    # onde cai, na tira do vale, um ponto da arte (para as luzes da vila)
    w = X1 - MID_X0
    for label, sx in (('vila', 1002),):
        first = int(np.argmin(np.abs(u_mid[:int(seam)] - (sx - MID_X0))))
        second = int(seam) + int(np.argmin(np.abs(u_mid[int(seam):] - (sx - MID_X0))))
        print(f'{label}: x da arte {sx} -> x da tira {first} e {second}')

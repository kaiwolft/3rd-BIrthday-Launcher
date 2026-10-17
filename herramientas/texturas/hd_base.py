#!/usr/bin/env python3
"""Genera las texturas base HD (x4) del launcher a partir de los volcados de PPSSPP.

  fuente_a.png  <- 0998048021b90c72aff9c741 (fuente principal, glifo blanco con alfa)
  fuente_b.png  <- 099804806e408c26aff9c741 (misma fuente, paleta con contorno negro)
  hud.png       <- 08ce4da0c05252b9fadd3775 (atlas del HUD: botones grandes, L/R)
  aviso.png     <- 08ce20e028333f3153a656a7 (aviso de guardado al inicio, icono de la cruz en 208,72 12x12)
  fuente2_a/b   <- 09c5d38021b903728fef25a6 / 09c5d3806e4083268fef25a6 (fuente del HUD)
  fuente3_a/b   <- 09c63c0021b90272f396c2af / 09c63c006e408226f396c2af (fuente pequeña)

Escalado: Scale2x dos veces (respeta el pixel-art) + suavizado y curva de contraste,
para que el texto quede nítido en alta resolución y sin escalones.
Uso: python3 hd_base.py <carpeta_originales> <carpeta_salida>
"""
import sys, os
import numpy as np
from PIL import Image
from scipy import ndimage

K = 4


def scale2x(a):
    """AdvMAME2x sobre una matriz 2D de enteros (cada valor = un color)."""
    p = np.pad(a, 1, mode='edge')
    B, D, E, F, H = p[:-2, 1:-1], p[1:-1, :-2], p[1:-1, 1:-1], p[1:-1, 2:], p[2:, 1:-1]
    c = (B != H) & (D != F)
    e0 = np.where(c & (D == B), D, E)
    e1 = np.where(c & (B == F), F, E)
    e2 = np.where(c & (D == H), D, E)
    e3 = np.where(c & (H == F), F, E)
    out = np.empty((a.shape[0] * 2, a.shape[1] * 2), a.dtype)
    out[0::2, 0::2], out[0::2, 1::2], out[1::2, 0::2], out[1::2, 1::2] = e0, e1, e2, e3
    return out


def scale4x_keys(keys):
    return scale2x(scale2x(keys))


def smooth(x, s=0.85):
    return ndimage.gaussian_filter(x, s)


def curve(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def font(orig, a_name, b_name, outdir, rows=None, kanji=False):
    va = np.array(Image.open(os.path.join(orig, a_name + '.png')).convert('RGBA')).astype(np.int32)
    if b_name and os.path.exists(os.path.join(orig, b_name + '.png')):
        vb = np.array(Image.open(os.path.join(orig, b_name + '.png')).convert('RGBA')).astype(np.int32)
    else:   # sin volcado de la paleta con contorno: contorno = glifo dilatado 1 px
        vb = np.zeros_like(va); vb[..., 3] = ndimage.maximum_filter(va[..., 3], size=3)
    if rows:   # solo la parte con glifos (con [hashranges] el juego reemplaza solo esas filas)
        va, vb = va[:rows], vb[:rows]
    G = va[..., 3]                                  # intensidad del glifo (0..255, 8 niveles)
    O = np.where(G == 0, vb[..., 3], 255)           # contorno (bajo el glifo es opaco)
    if kanji:   # kanji (trazos muy juntos): bloques x4 + suavizado leve, para que no se empasten
        G4 = curve(smooth(np.kron(G, np.ones((K, K))) / 255.0, 0.8), 0.40, 0.60)
        O4 = np.maximum(curve(smooth(np.kron(O, np.ones((K, K))) / 255.0, 0.8), 0.35, 0.60), G4)
    else:
        keys = G * 256 + O
        k4 = scale4x_keys(keys)
        G4 = (k4 // 256) / 255.0
        O4 = (k4 % 256) / 255.0
        G4 = curve(smooth(G4, 1.2), 0.18, 0.60)
        O4 = np.maximum(curve(smooth(O4, 1.2), 0.15, 0.60), G4)
    h, w = G4.shape
    a = np.zeros((h, w, 4), np.uint8)
    a[..., :3] = 255
    a[..., 3] = np.round(G4 * 255)
    b = np.zeros((h, w, 4), np.uint8)
    al = G4 + O4 * (1 - G4)
    b[..., 3] = np.round(al * 255)
    gray = np.where(al > 0, G4 / np.maximum(al, 1e-6), 0)
    b[..., :3] = np.round(gray * 255)[..., None]
    return Image.fromarray(a), Image.fromarray(b)


def hud(orig, name, rows_ok=288):
    im = np.array(Image.open(os.path.join(orig, name + '.png')).convert('RGBA'))
    h, w = im.shape[:2]
    keys = (im[..., 0].astype(np.int64) << 24) | (im[..., 1].astype(np.int64) << 16) | (im[..., 2].astype(np.int64) << 8) | im[..., 3]
    k4 = scale4x_keys(keys)
    out = np.stack([(k4 >> 24) & 255, (k4 >> 16) & 255, (k4 >> 8) & 255, k4 & 255], -1).astype(np.float64)
    # suavizado en espacio premultiplicado (solo en la parte útil del atlas)
    top = rows_ok * K
    al = out[:top, :, 3:4] / 255.0
    pm = out[:top, :, :3] * al
    pm = np.stack([smooth(pm[..., i], 0.8) for i in range(3)], -1)
    al2 = smooth(al[..., 0], 0.8)
    # devuelve algo de nitidez al alfa (bordes limpios sin perder degradados)
    al3 = np.clip(al2 + 0.9 * (al2 - smooth(al2, 1.6)), 0, 1)
    rgb = np.where(al2[..., None] > 1e-4, pm / np.maximum(al2[..., None], 1e-4), 0)
    out[:top, :, :3] = np.clip(rgb, 0, 255)
    out[:top, :, 3] = al3 * 255
    return Image.fromarray(np.round(out).astype(np.uint8))


def aviso(orig, name):
    """Pantalla de aviso de guardado (imagen opaca con texto): x4 con curva sobre la luminancia."""
    a = np.array(Image.open(os.path.join(orig, name + '.png')).convert('RGB')).astype(np.int64)
    k = scale4x_keys((a[..., 0] << 16) | (a[..., 1] << 8) | a[..., 2])
    out = np.stack([(k >> 16) & 255, (k >> 8) & 255, k & 255], -1) / 255.0
    sm = np.stack([smooth(out[..., i], 1.1) for i in range(3)], -1)
    Ls = sm.max(2)
    Lc = curve(Ls, 0.12, 0.75) * Ls
    ratio = np.where(Ls > 1e-3, np.minimum(Lc / np.maximum(Ls, 1e-3), 3), 0)
    return Image.fromarray((np.clip(sm * ratio[..., None], 0, 1) * 255).round().astype(np.uint8)).convert('RGBA')


SETS = {
    # versión española (ULES01513 traducida)
    'es': dict(fuente=('0998048021b90c72aff9c741', '099804806e408c26aff9c741'), hud='08ce4da0c05252b9fadd3775',
               aviso='08ce20e028333f3153a656a7',
               fuente2=('09c5d38021b903728fef25a6', '09c5d3806e4083268fef25a6'),
               fuente3=('09c63c0021b90272f396c2af', '09c63c006e408226f396c2af')),
    # versión japonesa (ULJM05798): la fuente está repartida en 3 páginas; los iconos están en la 3.ª (09961a80, solo 96 filas)
    'jp': dict(fuente=('09961a8021b903728e8b6a2c', None), fuente_rows=96, hud=None, aviso='08ce16e085af7cf3d075151e',
               fuente2=('09921a8021b90d7215d5285d', '09921a806e408d2615d5285d'),
               fuente3=('09c65a0021b9017240e70253', '09c65a006e40812640e70253'),
               fuente4=('09941a8021b90d7211a6a376', None), kanji=True),
    # versión americana (ULUS10567)
    'us': dict(fuente=('09973c8021b90c722128ceb2', '09973c806e408c262128ceb2'), hud='08ce4da0f75bf2e1358b383d',
               aviso='08ce20e0482166f676a926dd',
               fuente2=('09c6238021b9017217ea854f', '09c623806e40812617ea854f'),
               fuente3=('09c64c0021b9017240e68a53', '09c64c006e40812640e68a53')),
}

if __name__ == '__main__':
    # uso: hd_base.py <carpeta_originales> <carpeta_salida> [es|us|jp]
    orig, outdir = sys.argv[1], sys.argv[2]
    S = SETS[sys.argv[3] if len(sys.argv) > 3 else 'es']
    os.makedirs(outdir, exist_ok=True)
    a, b = font(orig, S['fuente'][0], S['fuente'][1], outdir, S.get('fuente_rows'), S.get('kanji', False))
    a.save(os.path.join(outdir, 'fuente_a.png'), optimize=True)
    b.save(os.path.join(outdir, 'fuente_b.png'), optimize=True)
    if S.get('hud'):
        hud(orig, S['hud']).save(os.path.join(outdir, 'hud.png'), optimize=True)
    aviso(orig, S['aviso']).save(os.path.join(outdir, 'aviso.png'), optimize=True)
    for name in ('fuente2', 'fuente3', 'fuente4'):
        if name not in S:
            continue
        a, b = font(orig, S[name][0], S[name][1], outdir, None, S.get('kanji', False))
        a.save(os.path.join(outdir, name + '_a.png'), optimize=True)
        b.save(os.path.join(outdir, name + '_b.png'), optimize=True)
    print('ok')

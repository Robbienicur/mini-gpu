import math

W = 18
F = 10
MAXIMO = (1 << (W - 1)) - 1
MINIMO = -(1 << (W - 1))

def a_fijo(x):
    v = math.floor(x * (1 << F) + 0.5)
    return max(MINIMO, min(MAXIMO, v))

def a_real(v):
    return v / (1 << F)

def satura(v, bits=W):
    hi = (1 << (bits - 1)) - 1
    lo = -(1 << (bits - 1))
    return max(lo, min(hi, v)), (v > hi or v < lo)

def redondea(v, s):
    if s <= 0:
        return v << (-s)
    return (v + (1 << (s - 1))) >> s

def suma_resta(A, B, resta=False):
    C, sat = [], False
    for a, b in zip(A, B):
        r, s = satura(a - b if resta else a + b)
        C.append(r)
        sat = sat or s
    return C, sat

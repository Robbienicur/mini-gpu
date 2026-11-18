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

def multiplica(A, B):
    C, sat = [0] * 16, False
    for i in range(4):
        for j in range(4):
            acc = sum(A[4 * i + k] * B[4 * k + j] for k in range(4))
            r, s = satura(redondea(acc, F))
            C[4 * i + j] = r
            sat = sat or s
    return C, sat

TABLA = [math.floor((1 / (0.5 + (i + 0.5) / 128)) * 2**17 + 0.5) for i in range(64)]

def reciproco(m):
    x = TABLA[(m >> 11) & 63]
    for _ in range(2):
        e = (1 << 19) - ((m * x) >> 17)
        x = (x * e) >> 18
    return x

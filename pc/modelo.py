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

def det3(m):
    d0 = m[1][1] * m[2][2] - m[1][2] * m[2][1]
    d1 = m[1][0] * m[2][2] - m[1][2] * m[2][0]
    d2 = m[1][0] * m[2][1] - m[1][1] * m[2][0]
    return m[0][0] * d0 - m[0][1] * d1 + m[0][2] * d2

def inversa(A):
    M = [A[4 * r:4 * r + 4] for r in range(4)]
    cof = [0] * 16
    for i in range(4):
        for j in range(4):
            menor = [[M[r][c] for c in range(4) if c != j] for r in range(4) if r != i]
            d = det3(menor)
            cof[4 * i + j] = -d if (i + j) % 2 else d
    D = sum(M[0][c] * cof[c] for c in range(4))
    if D == 0:
        return [0] * 16, 0, True, False
    Dabs, k = abs(D), 0
    while not (Dabs >> 73) & 1:
        Dabs <<= 1
        k += 1
    x = reciproco(Dabs >> 56)
    sh = 71 - k
    X, ovf = [0] * 16, False
    for n in range(16):
        r, c = n // 4, n % 4
        P = cof[4 * c + r] * x
        if D < 0:
            P = -P
        v, s = satura(redondea(P, sh))
        X[n] = v
        ovf = ovf or s
    det_q, _ = satura(redondea(D, 30), 32)
    return X, det_q, False, ovf

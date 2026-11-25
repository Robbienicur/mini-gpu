import sys
import time

import numpy as np
import serial

from modelo import a_fijo, a_real

BAUD = 9600
NG = 64
OPERACIONES = {1: "A + B", 2: "A - B", 3: "A * B", 4: "inversa de A", 5: "calor en placa"}

def tres_bytes(v):
    v &= 0xFFFFFF
    return bytes([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF])

def leer_con_signo(bs):
    v = int.from_bytes(bs, "little")
    bits = 8 * len(bs)
    return v - (1 << bits) if v >> (bits - 1) else v

def a_4x4(M, op):
    n = M.shape[0]
    G = np.eye(4) if op == 4 else np.zeros((4, 4))
    G[:n, :n] = M
    return G

def pedir_matriz(nombre, n):
    print(f"Matriz {nombre} ({n}x{n}), un renglon por linea con espacios (o Enter para una al azar):")
    renglones = []
    for i in range(n):
        linea = input(f"  renglon {i + 1}: ").strip()
        if linea == "":
            M = np.round(np.random.uniform(-4, 4, (n, n)), 2)
            print(M)
            return M
        renglones.append([float(x) for x in linea.split()])
    return np.array(renglones)

def manda(puerto, op, A, B):
    puerto.reset_input_buffer()
    datos = bytes([op]) + b"".join(tres_bytes(a_fijo(x)) for x in A.ravel())
    if op != 4:
        datos += b"".join(tres_bytes(a_fijo(x)) for x in B.ravel())
    puerto.write(datos)

    r = puerto.read(57)
    if len(r) < 57:
        print(f"No llego la respuesta completa ({len(r)} de 57 bytes)")
        return None
    C = np.array([a_real(leer_con_signo(r[3 * k:3 * k + 3])) for k in range(16)]).reshape(4, 4)
    det = leer_con_signo(r[48:52]) / 1024
    banderas = r[52]
    ciclos = int.from_bytes(r[53:57], "little")
    return C, det, banderas, ciclos

def placa_exacta(t):
    n = NG
    T1 = 2 * np.eye(n) - np.eye(n, k=1) - np.eye(n, k=-1)
    A = np.kron(np.eye(n), T1) + np.kron(T1, np.eye(n))
    b = np.zeros((n, n))
    b[0, :] += t[0]
    b[n - 1, :] += t[1]
    b[:, 0] += t[2]
    b[:, n - 1] += t[3]
    return np.linalg.solve(A, b.ravel()).reshape(n, n)


def calor(puerto):
    linea = input("Temperaturas de los bordes: arriba abajo izquierda derecha (0 a 255): ")
    t = [max(0, min(255, int(round(float(v))))) for v in linea.split()][:4]
    puerto.reset_input_buffer()
    puerto.write(bytes([5] + t))
    total = NG * NG + 7
    puerto.timeout = 30
    r = puerto.read(total)
    puerto.timeout = 3
    if len(r) < total:
        print(f"No llego la respuesta completa ({len(r)} de {total} bytes)")
        return
    P = np.array(list(r[:NG * NG]), float).reshape(NG, NG)
    vueltas = r[NG * NG] | r[NG * NG + 1] << 8
    estado = r[NG * NG + 2]
    ciclos = int.from_bytes(r[NG * NG + 3:NG * NG + 7], "little")
    exacto = placa_exacta(t)
    print(f"Ecuaciones resueltas: {NG * NG}")
    print(f"Vueltas de gradiente conjugado: {vueltas}")
    print("Convergio" if estado & 1 else "La FPGA dice: no convergio")
    print(f"Error maximo contra numpy = {np.abs(P - exacto).max():.3f} grados")
    print(f"Ciclos de la FPGA = {ciclos}  ({ciclos * 80e-9:.3f} s a 12.5 MHz)")
    try:
        import matplotlib.pyplot as plt
        fig, ax = plt.subplots(1, 2, figsize=(10, 4))
        for a, M, nombre in ((ax[0], P, "FPGA (gradiente conjugado)"), (ax[1], exacto, "numpy (exacto)")):
            im = a.imshow(M, cmap="hot")
            a.set_title(nombre)
            fig.colorbar(im, ax=a)
        plt.show()
    except ImportError:
        print("(instala matplotlib para ver el mapa)")


def main():
    nombre_puerto = sys.argv[1] if len(sys.argv) > 1 else "COM4"
    puerto = serial.Serial(nombre_puerto, BAUD, timeout=3)
    time.sleep(2)
    print("Mini-GPU lista")

    while True:
        print()
        for k, v in OPERACIONES.items():
            print(f"  {k}) {v}")
        op = int(input("Operacion (0 para salir): ") or 0)
        if op not in OPERACIONES:
            break
        if op == 5:
            calor(puerto)
            continue
        n = int(input("Tamano (2, 3 o 4): ") or 4)

        A = pedir_matriz("A", n)
        B = pedir_matriz("B", n) if op != 4 else np.zeros((n, n))

        res = manda(puerto, op, a_4x4(A, op), a_4x4(B, op))
        if res is None:
            continue
        C, det, banderas, ciclos = res
        C = C[:n, :n]

        if op == 1:
            exacto = A + B
        elif op == 2:
            exacto = A - B
        elif op == 3:
            exacto = A @ B
        else:
            exacto = np.linalg.inv(A) if abs(np.linalg.det(A)) > 1e-12 else None

        print("\nResultado de la FPGA:")
        print(np.round(C, 4))
        if op == 4:
            print(f"det = {det:.4f}")
        if banderas & 1:
            print("La FPGA dice: la matriz no tiene inversa (det = 0)")
        if banderas & 2:
            print("La FPGA dice: algun numero no cupo y se saturo")
        if exacto is not None and not (banderas & 1):
            mae = np.mean(np.abs(C - exacto))
            print("Resultado exacto (numpy):")
            print(np.round(exacto, 4))
            print(f"Error absoluto medio (MAE) = {mae:.6f}")
        print(f"Ciclos de la FPGA = {ciclos}  ({ciclos * 80 / 1000:.2f} us a 12.5 MHz)")

if __name__ == "__main__":
    main()

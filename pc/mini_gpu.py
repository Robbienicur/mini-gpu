import sys
import time

import numpy as np
import serial

from modelo import a_fijo, a_real

BAUD = 9600
OPERACIONES = {1: "A + B", 2: "A - B", 3: "A * B", 4: "inversa de A"}

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

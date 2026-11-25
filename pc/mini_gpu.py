import sys
import time

import numpy as np
import serial

BAUD = 115200
F = 20


def a_bytes(M):
    v = np.clip(np.round(M * 2**F), -2**31, 2**31 - 1).astype("<i4")
    return v.tobytes()


def manda(puerto, op, A, B=None):
    n = A.shape[0]
    datos = bytes([op, n]) + a_bytes(A)
    if op == 1:
        datos += a_bytes(B)
    total = 4 * n * n + 10
    puerto.reset_input_buffer()
    t = time.time()
    puerto.write(datos)
    r = puerto.read(total)
    t = time.time() - t
    if len(r) < total:
        print(f"No llego la respuesta completa ({len(r)} de {total} bytes)")
        return None
    k = 4 * n * n
    C = np.frombuffer(r[:k], "<i4").reshape(n, n) / 2**F
    banderas = r[k]
    dm = int.from_bytes(r[k + 1:k + 4], "little")
    de = int.from_bytes(r[k + 4:k + 6], "little", signed=True)
    det = (-1) ** (banderas >> 2 & 1) * dm * 2.0**de
    ciclos = int.from_bytes(r[k + 6:k + 10], "little")
    return C, banderas, det, ciclos, t


def al_azar(n):
    return np.round(np.random.uniform(-4, 4, (n, n)), 2)


def pedir_matriz(nombre, n):
    print(f"Matriz {nombre} ({n}x{n}), un renglon por linea (o Enter para una al azar):")
    renglones = []
    for i in range(n):
        linea = input(f"  renglon {i + 1}: ").strip()
        if linea == "":
            return al_azar(n)
        renglones.append([float(x) for x in linea.split()])
    return np.array(renglones)


def prueba_tamanos(puerto):
    for n in [2, 4, 8, 16, 32, 64, 128]:
        A, B = al_azar(n), al_azar(n)
        rm = manda(puerto, 1, A, B)
        ri = manda(puerto, 2, A)
        if rm is None or ri is None:
            return
        C, _, _, cm, tm = rm
        X, _, _, ci, ti = ri
        em = np.abs(C - A @ B).max()
        ei = np.abs(X - np.linalg.inv(A)).max()
        print(f"n = {n:3d}   mult: {cm:7d} ciclos ({cm * 80e-6:.3f} ms) err {em:.1e}   "
              f"inversa: {ci:7d} ciclos ({ci * 80e-6:.3f} ms) err {ei:.1e}   UART {tm + ti:.1f} s")


def main():
    nombre_puerto = sys.argv[1] if len(sys.argv) > 1 else "COM4"
    puerto = serial.Serial(nombre_puerto, BAUD, timeout=60)
    time.sleep(2)
    print("Mini-GPU lista")

    while True:
        print("\n  1) A * B   2) inversa de A   3) prueba de tamanos   0) salir")
        op = int(input("Operacion: ") or 0)
        if op not in (1, 2, 3):
            break
        if op == 3:
            prueba_tamanos(puerto)
            continue
        n = int(input("Tamano n (1 a 128): ") or 4)
        if not 1 <= n <= 128:
            continue
        A = pedir_matriz("A", n)
        B = pedir_matriz("B", n) if op == 1 else None
        if A.shape != (n, n) or (B is not None and B.shape != (n, n)):
            print("Las matrices deben ser de n x n")
            continue

        res = manda(puerto, op, A, B)
        if res is None:
            continue
        C, banderas, det, ciclos, t = res
        exacto = A @ B if op == 1 else (np.linalg.inv(A) if 1 / np.linalg.cond(A, 1) > 1e-12 else None)

        if n <= 8:
            print("\nResultado de la FPGA:")
            print(np.round(C, 4))
        if op == 2:
            print(f"det FPGA = {det:.6g}   det numpy = {np.linalg.det(A):.6g}")
        if banderas & 1:
            print("La FPGA dice: la matriz no tiene inversa (det = 0)")
        elif exacto is not None:
            if n <= 8:
                print("Resultado exacto (numpy):")
                print(np.round(exacto, 4))
            print(f"Error absoluto medio (MAE) = {np.mean(np.abs(C - exacto)):.2e}")
            print(f"Error maximo = {np.abs(C - exacto).max():.2e}")
        if banderas & 2:
            print("La FPGA dice: algun numero no cupo y se saturo")
        print(f"Ciclos de la FPGA = {ciclos}  ({ciclos * 80e-6:.3f} ms a 12.5 MHz)")
        print(f"Tiempo total con la UART = {t:.2f} s")


if __name__ == "__main__":
    main()

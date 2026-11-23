clear
clc

PORT = "COM4";
BAUD = 9600;

s = serialport(PORT, BAUD);
pause(2);
flush(s);
disp("Mini-GPU lista");

while true
    disp(" ");
    disp("1) A + B   2) A - B   3) A * B   4) inversa de A   0) salir");
    op = input('Operacion: ');
    if op < 1 || op > 4
        break;
    end
    n = input('Tamano (2, 3 o 4): ');

    A = input('Matriz A (por ejemplo [4 7; 2 6]): ');
    if op ~= 4
        B = input('Matriz B: ');
    else
        B = zeros(n);
    end

    if op == 4
        A4 = eye(4);
    else
        A4 = zeros(4);
    end
    B4 = zeros(4);
    A4(1:n, 1:n) = A;
    B4(1:n, 1:n) = B;

    datos = uint8(op);
    na = round(A4' * 1024);
    numeros = na(:);
    if op ~= 4
        nb = round(B4' * 1024);
        numeros = [numeros; nb(:)];
    end
    numeros = mod(numeros, 2^24);
    for k = 1:length(numeros)
        v = numeros(k);
        datos = [datos, uint8(mod(v, 256)), uint8(mod(floor(v / 256), 256)), uint8(floor(v / 65536))];
    end
    flush(s);
    write(s, datos, "uint8");

    tic;
    while s.NumBytesAvailable < 57
        if toc > 3.0
            break;
        end
    end
    if s.NumBytesAvailable < 57
        disp('No se recibio respuesta completa');
        continue;
    end
    r = double(read(s, 57, "uint8"));

    C = zeros(4);
    for k = 0:15
        v = r(3*k + 1) + 256 * r(3*k + 2) + 65536 * r(3*k + 3);
        if v >= 2^23
            v = v - 2^24;
        end
        C(floor(k / 4) + 1, mod(k, 4) + 1) = v / 1024;
    end
    d = r(49) + 256 * r(50) + 65536 * r(51) + 16777216 * r(52);
    if d >= 2^31
        d = d - 2^32;
    end
    banderas = r(53);
    ciclos = r(54) + 256 * r(55) + 65536 * r(56) + 16777216 * r(57);
    C = C(1:n, 1:n);

    switch op
        case 1
            exacto = A + B;
        case 2
            exacto = A - B;
        case 3
            exacto = A * B;
        case 4
            exacto = inv(A);
    end

    disp('Resultado de la FPGA:');
    disp(C);
    if op == 4
        disp(['det = ', num2str(d / 1024)]);
    end
    if bitand(banderas, 1)
        disp('La FPGA dice: la matriz no tiene inversa (det = 0)');
    else
        disp('Resultado exacto (MATLAB):');
        disp(exacto);
        disp(['Error absoluto medio (MAE) = ', num2str(mean(abs(C(:) - exacto(:))))]);
    end
    if bitand(banderas, 2)
        disp('La FPGA dice: algun numero no cupo y se saturo');
    end
    disp(['Ciclos de la FPGA = ', num2str(ciclos), '  (', num2str(ciclos * 0.02), ' us a 50 MHz)']);
end

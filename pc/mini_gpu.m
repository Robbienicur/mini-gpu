clear
clc

PORT = "COM4";
BAUD = 115200;

s = serialport(PORT, BAUD);
s.Timeout = 60;
pause(2);
flush(s);
disp("Mini-GPU lista");

while true
    disp(" ");
    disp("1) A * B   2) inversa de A   3) prueba de tamanos   0) salir");
    op = input('Operacion: ');
    if isempty(op) || op < 1 || op > 3
        break;
    end

    if op == 3
        tam = [2 4 8 16 32 64 128];
        res = zeros(length(tam), 6);
        for k = 1:length(tam)
            n = tam(k);
            A = round(8 * rand(n) - 4, 2);
            B = round(8 * rand(n) - 4, 2);
            [C, ~, ~, cm, tm] = mini_gpu_manda(s, 1, A, B);
            [X, ~, ~, ci, ti] = mini_gpu_manda(s, 2, A, []);
            if isempty(C) || isempty(X)
                disp('No se recibio respuesta completa');
                break;
            end
            res(k, :) = [n, cm, max(abs(C(:) - reshape(A * B, [], 1))), ci, max(abs(X(:) - reshape(inv(A), [], 1))), tm + ti];
            fprintf('n = %3d   mult: %7d ciclos (%.3f ms) err %.1e   inversa: %7d ciclos (%.3f ms) err %.1e   UART %.1f s\n', ...
                n, cm, cm * 80e-6, res(k, 3), ci, ci * 80e-6, res(k, 5), res(k, 6));
        end
        figure;
        loglog(res(:, 1), res(:, 2), 'o-', res(:, 1), res(:, 4), 's-');
        grid on; xlabel('n'); ylabel('ciclos de la FPGA');
        legend('multiplicacion', 'inversa', 'Location', 'northwest');
        title('Ciclos contra tamano (12.5 MHz)');
        continue;
    end

    n = input('Tamano n (1 a 128): ');
    if isempty(n) || n < 1 || n > 128 || n ~= round(n)
        continue;
    end
    A = input('Matriz A (Enter = al azar): ');
    if isempty(A)
        A = round(8 * rand(n) - 4, 2);
    end
    B = [];
    if op == 1
        B = input('Matriz B (Enter = al azar): ');
        if isempty(B)
            B = round(8 * rand(n) - 4, 2);
        end
    end
    if ~isequal(size(A), [n n]) || (op == 1 && ~isequal(size(B), [n n]))
        disp('Las matrices deben ser de n x n');
        continue;
    end

    [C, banderas, det_fpga, ciclos, t] = mini_gpu_manda(s, op, A, B);
    if isempty(C)
        disp('No se recibio respuesta completa');
        continue;
    end

    if op == 1
        exacto = A * B;
    elseif rcond(A) > 1e-12
        exacto = inv(A);
    else
        exacto = [];
    end

    if n <= 8
        disp('Resultado de la FPGA:');
        disp(C);
    end
    if op == 2
        disp(['det FPGA = ', num2str(det_fpga, 8), '   det MATLAB = ', num2str(det(A), 8)]);
    end
    if bitand(banderas, 1)
        disp('La FPGA dice: la matriz no tiene inversa (det = 0)');
    elseif ~isempty(exacto)
        if n <= 8
            disp('Resultado exacto (MATLAB):');
            disp(exacto);
        end
        disp(['Error absoluto medio (MAE) = ', num2str(mean(abs(C(:) - exacto(:))))]);
        disp(['Error maximo = ', num2str(max(abs(C(:) - exacto(:))))]);
    end
    if bitand(banderas, 2)
        disp('La FPGA dice: algun numero no cupo y se saturo');
    end
    disp(['Ciclos de la FPGA = ', num2str(ciclos), '  (', num2str(ciclos * 80e-6), ' ms a 12.5 MHz)']);
    disp(['Tiempo total con la UART = ', num2str(t), ' s']);
end

function [C, banderas, d, ciclos, t] = mini_gpu_manda(s, op, A, B)
    n = size(A, 1);
    numeros = round(A' * 2^20);
    numeros = numeros(:);
    if op == 1
        nb = round(B' * 2^20);
        numeros = [numeros; nb(:)];
    end
    numeros = min(max(numeros, -2^31), 2^31 - 1);
    datos = [uint8(op), uint8(n), typecast(int32(numeros'), 'uint8')];

    total = 4 * n * n + 10;
    flush(s);
    tic;
    write(s, datos, "uint8");
    r = read(s, total, "uint8");
    t = toc;
    C = []; banderas = 0; d = 0; ciclos = 0;
    if numel(r) < total
        return;
    end
    r = uint8(r);
    k = 4 * n * n;
    C = reshape(double(typecast(r(1:k), 'int32')) / 2^20, n, n)';
    banderas = double(r(k + 1));
    dm = double(r(k + 2)) + 256 * double(r(k + 3)) + 65536 * double(r(k + 4));
    de = double(typecast(r(k + 5:k + 6), 'int16'));
    d = (-1)^bitand(bitshift(banderas, -2), 1) * dm * 2^de;
    ciclos = double(typecast(r(k + 7:k + 10), 'uint32'));
end

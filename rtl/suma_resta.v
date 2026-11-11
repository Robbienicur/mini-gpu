module suma_resta (
    input  wire [287:0] A,
    input  wire [287:0] B,
    input  wire         resta,
    output reg  [287:0] C,
    output reg          sat
);

    integer k;
    reg signed [17:0] a, b;
    reg signed [18:0] r;

    always @(*) begin
        sat = 1'b0;
        C   = 288'd0;
        for (k = 0; k < 16; k = k + 1) begin
            a = A[18*k +: 18];
            b = B[18*k +: 18];
            if (resta)
                r = a - b;
            else
                r = a + b;

            if (r > 19'sd131071) begin
                C[18*k +: 18] = 18'h1FFFF;
                sat = 1'b1;
            end else if (r < -19'sd131072) begin
                C[18*k +: 18] = 18'h20000;
                sat = 1'b1;
            end else begin
                C[18*k +: 18] = r[17:0];
            end
        end
    end

endmodule

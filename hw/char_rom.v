module char_rom (
    input wire clk,
    input wire [10:0] addr,   // {chr[6:0], row[3:0]} == chr*16 + row
    output reg [7:0] dout
);
    reg [7:0] rom [0:2047];   // 128 possible char codes x 16 row-slots each

    initial begin
        $readmemh("charset.hex", rom);
    end

    always @(posedge clk) begin
        dout <= rom[addr];
    end
endmodule
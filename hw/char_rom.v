module char_rom (
    input wire clk,
    input wire [10:0] addr,
    output reg [7:0] dout
);
    reg [7:0] rom [0:2047];
    string file_path;

    initial begin
        if (!$value$plusargs("char_rom=%s", file_path)) begin
            file_path = "charset.hex";
        end
        $readmemh(file_path, rom);
    end

    always @(posedge clk) begin
        dout <= rom[addr];
    end
endmodule
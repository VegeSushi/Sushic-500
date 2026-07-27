module sys_rom (
    input wire clk,
    input wire [13:0] addr, 
    output reg [7:0] dout
);
    reg [7:0] rom [0:12287];
    string file_path;
    
    initial begin
        if (!$value$plusargs("bios_rom=%s", file_path)) begin
            file_path = "bios.hex";
        end
        $readmemh(file_path, rom);
    end
    
    always @(posedge clk) dout <= rom[addr];
endmodule
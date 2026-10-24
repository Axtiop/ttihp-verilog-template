module CONTROL_HSPIO (
    // Clock and reset
    input  logic clk,
    input  logic rst_ni,

    // Write interface
    input  logic        wr_mem_i,
    input  logic        wr_byte_en_i,
    input  logic [7:0]  wr_addr_i,
    input  logic [7:0]  wr_data_i,

    // Transfer Enable
    input logic transfer_data,
    input logic [7:0] hspio_add_start,
    input logic [7:0] hspio_add_end,

    // Input interfaces
    input logic clk_in1,
    input logic clk_in2,

    // Output interfaces
    input logic clk_out1_en,
    input logic clk_out2_en,
    input logic clk_out1_pol,
    input logic clk_out2_pol,

    output logic clk_out1,
    output logic clk_out2,

    // GPIOs
    input logic [3:0] gpio_i,
    output logic [3:0] gpio_o
);

    logic data_ready;
    logic [7:0] data_addr;
    logic data_read;
    logic [63:0] data_in;

 // IHP RAM MACRO of sixe 256x16.
   SRAM_HSPIO u_SRAM_HSPIO(
    // Clock and reset
    .clk      (clk),
    .rst_ni   (rst_ni),

    // Write interface
    .wr_mem_i   (wr_mem_i),
    .wr_byte_en_i (wr_byte_en_i),
    .wr_addr_i  (wr_addr_i),
    .wr_data_i  (wr_data_i),

    // Read interface
    .data_ready_o  (data_ready),
    .data_read_i   (data_read),
    .data_addr_i   (data_addr),
    .data_out_o    (data_in)
);

   HSPIO u_HSPIO (
    .rst_ni       (rst_ni),

    // Registers
    .transfer_data (transfer_data),
    .hspio_add_start (hspio_add_start),
    .hspio_add_end (hspio_add_end),
    .data_in       (data_in),
    .data_addr     (data_addr),
    .data_read_o   (data_read),
    .data_ready_i  (data_ready),

    // I/O
    .clk_in1       (clk_in1),
    .clk_in2       (clk_in2),

    .clk_out1_en    (clk_out1_en),
    .clk_out1_pol   (clk_out1_pol),
    .clk_out1       (clk_out1),
    .clk_out2_pol   (clk_out2_pol),
    .clk_out2_en    (clk_out2_en),
    .clk_out2       (clk_out2),

    .gpio_i       (gpio_i),
    .gpio_o       (gpio_o)
);

endmodule
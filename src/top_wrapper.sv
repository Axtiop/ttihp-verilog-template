/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // Registers for the outputs
    reg [7:0] out_reg;
    reg [7:0] uio_out_reg;
    reg [7:0] uio_oe_reg;

    // Asynchronous active-low reset and clock-driven shifting
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_reg     <= 8'b01101110;
            uio_out_reg <= 8'b01101110;
            uio_oe_reg  <= 8'b01101110;
        end
        else begin
            out_reg     <= {out_reg[6:0], out_reg[7]};
            uio_out_reg <= {uio_out_reg[6:0], uio_out_reg[7]};
            uio_oe_reg  <= {uio_oe_reg[6:0], uio_oe_reg[7]};
        end
    end

    // Connect registers to output pins
    assign uo_out  = out_reg;
    assign uio_out = uio_out_reg;
    assign uio_oe  = uio_oe_reg;

    // Unused inputs
    wire _unused = &{ena, ui_in, uio_in, 1'b0};

endmodule
    /*
  logic rx;
  assign rx = ui_in[7];

  logic tx;
  //assign uo_out[7] = tx; // TODO: place this is for a test
  assign uo_out[7] = 0; // TODO: place this is for a test
  assign uo_out[6] = 0;

  logic clk_in1;
  assign clk_in1 = ui_in[6];

  logic [1:0] error_modes_i;
  //assign error_modes_i = ui_in[5:4];
  assign error_modes_i = 2'b00;

  logic dump_debug_s; // TODO: place this is for a test
  assign uo_out[5] = 0;

    top top (
        .clk   (clk),
        .rst_ni(rst_n),
        .rx (rx),
        .tx (tx),
        .gpio_i (uio_in),
        .gpio_oe (uio_oe),
        .gpio_o (uio_out),
        .clk_in1 (clk_in1),
        .error_modes_i (error_modes_i),
        .hspio_gpio_o (uo_out[4:0]),
        .debug_o (dump_debug_s)
    );

endmodule
        */

/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // All output pins must be assigned. If not used, assign to 0.

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, 1'b0};

  logic rx;
  assign rx = ui_in[7];

  logic tx;
  assign uo_out[7] = tx;
  assign uo_out[6] = 0;
  assign uo_out[5] = 0;

  logic clk_in1;
  assign clk_in1 = ui_in[6];

  logic [1:0] error_modes_i;
  assign error_modes_i = ui_in[5:4];

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
        .hspio_gpio_o (uo_out[4:0])
    );

endmodule

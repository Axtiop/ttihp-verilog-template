module error_injection (
  input  logic       clk,
  input  logic       rst_ni,

  input  logic       en_error_injection_i,
  // Mode 00 masks: out = ((in & and_mask_i) | or_mask_i) ^ xor_mask_i
  input  logic [7:0] and_mask_i,
  input  logic [7:0] or_mask_i,
  input  logic [7:0] xor_mask_i,

  input  logic [7:0] mask_i,          // bit-select for modes 01..11 (1 = affected)
  input  logic [7:0] rpc_trigger_i,   // RPC value that triggers injection
  input  logic [7:0] current_rpc_i,   // current RPC
  input  logic [7:0] level_i,         // forced value (mode 01), corruption probability /256 (mode 11)
  input  logic [3:0] jitter_count_i,  // delay in cycles (mode 10), burst length-1 (mode 11)

  input  logic [1:0] modes_i,
  input  logic [7:0] gpio_o_in,
  output logic [7:0] gpio_o_out
);

  localparam logic [1:0] MODE_MASK    = 2'b00;
  localparam logic [1:0] MODE_PULSE   = 2'b01;
  localparam logic [1:0] MODE_JITTER  = 2'b10;
  localparam logic [1:0] MODE_CORRUPT = 2'b11;

  // ---------------------------------------------------------------
  // RPC compare (combinational) + edge detect
  // ---------------------------------------------------------------
  logic rpc_match, rpc_match_q, rpc_match_edge;

  assign rpc_match      = (current_rpc_i == rpc_trigger_i);
  assign rpc_match_edge = rpc_match & ~rpc_match_q;

  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) rpc_match_q <= 1'b0;
    else         rpc_match_q <= rpc_match;
  end

  // ---------------------------------------------------------------
  // Jitter: per-bit delay line, 16 taps (tap 0 = no delay)
  // ---------------------------------------------------------------
  logic [7:0] hist [0:15];
  logic [7:0] delayed;

  always_ff @(posedge clk or negedge rst_ni) begin
      if (!rst_ni) begin
          for (int i = 0; i < 16; i++)
              hist[i] <= '0;
      end else begin
          hist[0] <= gpio_o_in;

          for (int i = 1; i < 16; i++)
              hist[i] <= hist[i-1];
      end
  end

  always_comb begin
      delayed = hist[jitter_count_i];
  end

  // ---------------------------------------------------------------
  // Random / burst corruption
  // ---------------------------------------------------------------
  logic [15:0] lfsr;
  logic [4:0]  burst_cnt;
  logic        random_hit, burst_active, corrupt_hit;

  // x^16 + x^15 + x^13 + x^4 + 1 (maximal length)
  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) lfsr <= 16'hACE1;   // must never be all-zero
    else         lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[14] ^ lfsr[12] ^ lfsr[3]};
  end

  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni)                burst_cnt <= '0;
    else if (rpc_match_edge)    burst_cnt <= {1'b0, jitter_count_i} + 5'd1;
    else if (burst_cnt != 5'd0) burst_cnt <= burst_cnt - 5'd1;
  end

  assign burst_active = (burst_cnt != 5'd0);
  assign random_hit   = (lfsr[7:0] < level_i);   // P = level_i / 256
  assign corrupt_hit  = random_hit | burst_active;

  // ---------------------------------------------------------------
  // Output mux
  // ---------------------------------------------------------------
  always_comb begin
    if (!en_error_injection_i) begin
      // Bypass error injection: transfer input directly to output
      gpio_o_out = gpio_o_in;
    end else begin
      unique case (modes_i)
        // AND / OR / XOR masking on the I/Os
        MODE_MASK:
          gpio_o_out = ((gpio_o_in & and_mask_i) | or_mask_i) ^ xor_mask_i;

        // Force masked bits to level_i, only while RPC matches the trigger
        MODE_PULSE:
          gpio_o_out = rpc_match ? ((gpio_o_in & ~mask_i) | (level_i & mask_i))
                                : gpio_o_in;

        // Masked bits are delayed by jitter_count_i cycles
        MODE_JITTER:
          gpio_o_out = (gpio_o_in & ~mask_i) | (delayed & mask_i);

        // Masked bits flipped randomly, or for a burst after an RPC match
        MODE_CORRUPT:
          gpio_o_out = gpio_o_in ^ (mask_i & {8{corrupt_hit}});

        default:
          gpio_o_out = gpio_o_in;
      endcase
    end
  end

endmodule


// TODO: make sure that by default, if nothing is done in the SW, no matter what we put in the modes there is nothing weird happening on the pins.

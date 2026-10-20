module HSPIO (
    // Reset
    input  logic rst_ni,

    // Registers
    input  logic        transfer_data,
    input  logic [63:0] data_in,
    output logic [7:0]  data_addr,
    output logic        data_read_o,
    input  logic        data_ready_i,

    // I/O
    input  logic clk_in1,
    input  logic clk_in2,

    input logic clk_out1_en,
    input logic clk_out1_pol,
    output logic clk_out1,
    input logic clk_out2_pol,
    input logic clk_out2_en,
    output logic clk_out2,

    input  wire  [3:0] gpio_i,
    output logic [3:0] gpio_o
);

    // --------------------------------------------------
    // Internal registers
    // --------------------------------------------------

    // GPIO output bit counter: 0 to 15
    logic [5:0] bit_counter;

    // GPIO input synchronizers
    logic [3:0] gpio_i_sync1;
    logic [3:0] gpio_i_sync2;

    // GPIO input shift registers
    logic [15:0] gpio_i_shift [3:0];

    // Transfer request synchronizers
    logic transfer_data_sync1;
    logic transfer_data_sync;

    // Data input synchronizers
    logic [63:0] data_in_sync1;
    logic [63:0] data_in_sync;

    // Data ready synchronizers
    logic data_ready_sync1;
    logic data_ready_sync;

    // --------------------------------------------------
    // CDC synchronizers
    // clk_in2 is the destination clock for these signals.
    // --------------------------------------------------

    always_ff @(posedge clk_in2 or negedge rst_ni) begin
        if (!rst_ni) begin
            transfer_data_sync1 <= 1'b0;
            transfer_data_sync  <= 1'b0;

            data_in_sync1       <= 64'd0;
            data_in_sync        <= 64'd0;

            data_ready_sync1    <= 1'b0;
            data_ready_sync     <= 1'b0;
        end else begin
            // Double synchronizer for transfer_data
            transfer_data_sync1 <= transfer_data;
            transfer_data_sync  <= transfer_data_sync1;

            // Double synchronizer for data_in
            data_in_sync1 <= data_in;
            data_in_sync  <= data_in_sync1;

            // Double synchronizer for data_ready_i
            data_ready_sync1 <= data_ready_i;
            data_ready_sync  <= data_ready_sync1;
        end
    end

    // --------------------------------------------------
    // GPIO output serialization
    // --------------------------------------------------

    always_ff @(posedge clk_in2 or negedge rst_ni) begin
        if (!rst_ni) begin
            bit_counter <= 6'd0;
            data_addr   <= 8'd0;
            gpio_o      <= 4'd0;
            data_read_o <= 1'b0;
        end else begin

            if (transfer_data_sync) begin

                // Send one bit per GPIO output on each rising edge.
                gpio_o[0] <= data_in_sync[bit_counter];
                gpio_o[1] <= data_in_sync[16 + bit_counter];
                gpio_o[2] <= data_in_sync[32 + bit_counter];
                gpio_o[3] <= data_in_sync[48 + bit_counter];

                // Count from 0 to 15.
                if (bit_counter == 6'd15) begin
                    bit_counter <= 6'd0;
                    data_addr   <= data_addr + 1'b1;
                    data_read_o <= 1'b1;
                // Make sure the pulse is long enough !
                end else if (bit_counter > 6'd3) begin 
                    bit_counter <= bit_counter + 1'b1;
                    data_read_o <= 1'b0;
                end else begin
                    bit_counter <= bit_counter + 1'b1;
                end

            end
        end
    end

    // --------------------------------------------------
    // GPIO input synchronization
    // --------------------------------------------------

    always_ff @(posedge clk_in1 or negedge rst_ni) begin
        if (!rst_ni) begin
            gpio_i_sync1 <= 4'd0;
            gpio_i_sync2 <= 4'd0;
        end else begin
            gpio_i_sync1 <= gpio_i;
            gpio_i_sync2 <= gpio_i_sync1;
        end
    end

    // --------------------------------------------------
    // GPIO input shift registers
    // --------------------------------------------------

    always_ff @(posedge clk_in1 or negedge rst_ni) begin
        if (!rst_ni) begin
            gpio_i_shift[0] <= 16'd0;
            gpio_i_shift[1] <= 16'd0;
            gpio_i_shift[2] <= 16'd0;
            gpio_i_shift[3] <= 16'd0;
        end else if (transfer_data) begin

            gpio_i_shift[0] <= {gpio_i_shift[0][14:0], gpio_i_sync2[0]};
            gpio_i_shift[1] <= {gpio_i_shift[1][14:0], gpio_i_sync2[1]};
            gpio_i_shift[2] <= {gpio_i_shift[2][14:0], gpio_i_sync2[2]};
            gpio_i_shift[3] <= {gpio_i_shift[3][14:0], gpio_i_sync2[3]};

        end
    end

    // --------------------------------------------------
    // Clock output control
    // --------------------------------------------------

    always_comb begin
        clk_out1 = clk_out1_en ? clk_in1 : clk_out1_pol;
        clk_out2 = clk_out2_en ? clk_in2 : clk_out2_pol;
    end

endmodule
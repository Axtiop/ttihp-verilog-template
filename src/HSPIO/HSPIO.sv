module HSPIO (
    // Reset
    input  logic rst_ni,

    // Registers
    input  logic        transfer_data,
    input  logic [7:0]  hspio_add_start,
    input  logic [7:0]  hspio_add_end,
    input  logic [63:0] data_in1,
    input  logic [63:0] data_in2,
    output logic [7:0]  data_addr,
    output logic        data_read_o,
    input  logic        data_ready_i,
    output logic        sram_buffer_sel_o,

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
    logic [63:0] data_in_sync1_r;
    logic [63:0] data_in_sync2;
    logic [63:0] data_in_sync2_r;
    logic active_buffer_sel;
    // Data ready synchronizers
    logic data_ready_sync1;
    logic data_ready_sync;

    // Addr start synchronizers
    logic [7:0] hspio_add_start_sync1;
    logic [7:0] hspio_add_start_sync;

    // --------------------------------------------------
    // CDC synchronizers
    // clk_in2 is the destination clock for these signals.
    // --------------------------------------------------

    always_ff @(posedge clk_in2 or negedge rst_ni) begin
        if (!rst_ni) begin
            transfer_data_sync1 <= 1'b0;
            transfer_data_sync  <= 1'b0;

            data_in_sync1       <= 64'd0;
            data_in_sync1_r     <= 64'd0;

            data_in_sync2       <= 64'd0;
            data_in_sync2_r     <= 64'd0;

            data_ready_sync1    <= 1'b0;
            data_ready_sync     <= 1'b0;

            hspio_add_start_sync1 <= 8'h00;
            hspio_add_start_sync  <= 8'h00;

        end else begin
            // Double synchronizer for transfer_data
            transfer_data_sync1 <= transfer_data;
            transfer_data_sync  <= transfer_data_sync1;

            // Double synchronizer for data_in
            data_in_sync1    <= data_in1;
            data_in_sync1_r  <= data_in_sync1;

            data_in_sync2    <= data_in2;
            data_in_sync2_r  <= data_in_sync2;

            // Double synchronizer for data_ready_i
            data_ready_sync1 <= data_ready_i;
            data_ready_sync  <= data_ready_sync1;

            hspio_add_start_sync1 <= hspio_add_start;
            hspio_add_start_sync  <= hspio_add_start_sync1;
        end
    end

    // --------------------------------------------------
    // GPIO output serialization
    // --------------------------------------------------
    // TODO There is problem here, 

    logic [2:0] startup_counter;
    logic       transfer_started;
    logic       transfer_stopped;

    always_ff @(posedge clk_in2 or negedge rst_ni) begin
        if (!rst_ni) begin
            bit_counter       <= 6'd0;
            data_addr         <= 8'd0;
            gpio_o            <= 4'd0;
            data_read_o       <= 1'b0;

            active_buffer_sel <= 1'b0;
            sram_buffer_sel_o <= 1'b0;

            startup_counter   <= 3'd0;
            transfer_started  <= 1'b0;
            transfer_stopped  <= 1'b0;

        end else begin

            if (transfer_data_sync) begin

                // -------------------------------------------------
                // Startup phase: wait for bit_counter == 15.
                // Set the starting address and issue a 4-cycle
                // SRAM read pulse before starting data transfer.
                // -------------------------------------------------
                if (!transfer_started) begin
                    active_buffer_sel <= 1'b0;
                    sram_buffer_sel_o <= 1'b0;
                    data_addr <= hspio_add_start_sync;

                    if (bit_counter == 6'd5) begin

                        bit_counter <= 6'd0;

                        // Hold data_read_o high for 4 clock cycles.
                        if (startup_counter < 3'd1) begin
                            data_read_o     <= 1'b1;
                            startup_counter <= startup_counter + 1'b1;
                        end else begin
                            data_read_o      <= 1'b0;
                            transfer_started <= 1'b1;
                            startup_counter  <= 3'd0;
                        end

                    end else begin
                        bit_counter <= bit_counter + 1'b1;
                        data_read_o <= 1'b0;
                    end

                end else begin

                    // -------------------------------------------------
                    // Normal transfer logic (existing implementation).
                    // -------------------------------------------------

                    // Select the buffer currently being transmitted.
                    if (active_buffer_sel == 1'b0) begin
                        gpio_o[0] <= data_in_sync1_r[bit_counter];
                        gpio_o[1] <= data_in_sync1_r[16 + bit_counter];
                        gpio_o[2] <= data_in_sync1_r[32 + bit_counter];
                        gpio_o[3] <= data_in_sync1_r[48 + bit_counter];
                    end else begin
                        gpio_o[0] <= data_in_sync2_r[bit_counter];
                        gpio_o[1] <= data_in_sync2_r[16 + bit_counter];
                        gpio_o[2] <= data_in_sync2_r[32 + bit_counter];
                        gpio_o[3] <= data_in_sync2_r[48 + bit_counter];
                    end

                    // Count from 0 to 15.
                    if (bit_counter == 6'd15) begin

                        
                        // Switch buffers after transmitting all 16 bits.
                        if ((hspio_add_end == 8'h00) ||
                            (data_addr < hspio_add_end)) begin

                            active_buffer_sel <= ~active_buffer_sel;

                        end                     // Address wrapping if end address is 0x00.

                        if (8'h00 == hspio_add_end &&
                            data_addr == hspio_add_end) begin

                            data_addr <= hspio_add_start_sync;

                        end

                        // Stop at the configured end address.
                        else if (data_addr >= hspio_add_end) begin
                            transfer_stopped <= 1'b1;
                        end else begin
                            bit_counter <= 6'd0;
                        end

                    // IMPORTANT: Keep this condition!
                    end else if (bit_counter == 6'd0) begin
                        data_addr   <= data_addr + 8'd4;
                        bit_counter <= bit_counter + 1'b1;
                    end else if (bit_counter < 6'd4) begin

                        bit_counter <= bit_counter + 1'b1;
                        data_read_o <= 1'b1;
                        sram_buffer_sel_o <= ~active_buffer_sel;
                    
                    end else begin
                        data_read_o <= 1'b0;
                        bit_counter <= bit_counter + 1'b1;

                    end

                end

            end else begin

                // Reset the startup sequence when transfer is disabled.
                data_addr        <= hspio_add_start_sync;
                bit_counter      <= 6'd0;
                data_read_o      <= 1'b0;
                startup_counter  <= 3'd0;
                transfer_started <= 1'b0;
                transfer_stopped <= 1'b0;
            end

            if (transfer_stopped == 1'b1) begin 
                gpio_o[0] <= 1'b1;
                gpio_o[1] <= 1'b1;
                gpio_o[2] <= 1'b1;
                gpio_o[3] <= 1'b1;
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
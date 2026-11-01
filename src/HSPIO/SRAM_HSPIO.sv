module SRAM_HSPIO (
    // Clock and reset
    input  logic        clk,
    input  logic        rst_ni,

    // Write interface
    input  logic        wr_mem_i,
    input  logic        wr_byte_en_i, // TODO: The wr_data_i is not 16bits here but 7 bits because we load 8bits by 8 bits into the write, so you need to add a small buffer.
    input  logic [7:0]  wr_addr_i,
    input  logic [7:0]  wr_data_i,

    // Read interface
    output logic        data_ready_o,
    input  logic        data_read_i,
    input  logic [7:0]  data_addr_i,
    output logic [63:0] data_out1_o,
    output logic [63:0] data_out2_o,
    input  logic        sram_buffer_sel_o

);

logic [7:0] write_buffer;

always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
        write_buffer <= 8'h00;
    end else begin
        if (wr_mem_i && !wr_byte_en_i) begin
            write_buffer <= wr_data_i;
        end
    end
end


    // ------------------------------------------------------------
    // Synchronizers for signals originating in another clock domain
    // ------------------------------------------------------------

    (* ASYNC_REG = "TRUE" *) logic data_read_meta;
    (* ASYNC_REG = "TRUE" *) logic data_read_sync;

    (* ASYNC_REG = "TRUE" *) logic [7:0] data_addr_meta;
    (* ASYNC_REG = "TRUE" *) logic [7:0] data_addr_sync;
    logic target_buffer_sel;
    logic active_buffer_sel_meta;
    logic        read_request;
    logic data_read_sync_d;

    always_ff @(posedge clk or negedge rst_ni) begin
        if (!rst_ni) begin
            data_read_meta   <= 1'b0;
            data_read_sync   <= 1'b0;
            data_read_sync_d <= 1'b0;

            data_addr_meta   <= 8'h00;
            data_addr_sync   <= 8'h00;
            target_buffer_sel <= 1'b0;
            active_buffer_sel_meta <= 1'b0;
        end else begin
            data_read_meta   <= data_read_i;
            data_read_sync   <= data_read_meta;
            data_read_sync_d <= data_read_sync;

            data_addr_meta   <= data_addr_i;
            data_addr_sync   <= data_addr_meta;

            active_buffer_sel_meta <= sram_buffer_sel_o;
            target_buffer_sel <= active_buffer_sel_meta;
        end
    end
    assign read_request = data_read_sync & ~data_read_sync_d;
    // ------------------------------------------------------------
    // SRAM signals
    // ------------------------------------------------------------

    logic        sram_ren;
    logic        sram_wen;
    logic [7:0]  sram_addr;
    logic [15:0] sram_din;
    logic [15:0] sram_dout;
    logic [15:0] sram_bm;

    assign sram_bm = 16'hFFFF;

    // ------------------------------------------------------------
    // Read controller
    // ------------------------------------------------------------

    typedef enum logic [2:0] {
        IDLE,
        READ_0,
        READ_1,
        READ_2,
        READ_3,
        READ_LAST,
        DONE
    } state_t;

    state_t state;

    logic [7:0]  read_base_addr;
    logic [63:0] read_buffer;

    // ------------------------------------------------------------
    // SRAM controller and data assembly
    // ------------------------------------------------------------

    always_comb begin
        sram_ren  = 1'b0;
        sram_wen  = 1'b0;
        sram_addr = 8'h00;
        sram_din  = 16'h0000;

        // Writes have priority over reads.
        if (wr_mem_i && wr_byte_en_i) begin
            sram_wen  = 1'b1;
            sram_addr = wr_addr_i;
            sram_din  = {wr_data_i, write_buffer};
        end else begin
            case (state)

                READ_0: begin
                    sram_ren  = 1'b1;
                    sram_addr = read_base_addr;
                end

                READ_1: begin
                    sram_ren  = 1'b1;
                    sram_addr = read_base_addr + 8'd1;
                end

                READ_2: begin
                    sram_ren  = 1'b1;
                    sram_addr = read_base_addr + 8'd2;
                end

                READ_3: begin
                    sram_ren  = 1'b1;
                    sram_addr = read_base_addr + 8'd3;
                end

                default: begin
                    sram_ren = 1'b0;
                end

            endcase
        end
    end

    // ------------------------------------------------------------
    // State machine
    // ------------------------------------------------------------

    always_ff @(posedge clk or negedge rst_ni) begin
        if (!rst_ni) begin
            state             <= IDLE;
            read_base_addr    <= 8'h00;
            read_buffer       <= 64'h0;
            data_out1_o       <= 64'h0;
            data_out2_o       <= 64'h0;
            data_ready_o      <= 1'b0;
            

        end else begin
            data_ready_o <= 1'b0;

            // Writes have priority over reads.
            if (wr_mem_i) begin
                state <= state;
            end else begin

                case (state)

                    IDLE: begin
                        if (read_request) begin
                            // Capture the base address for this block.
                            read_base_addr <= data_addr_sync;
                            state <= READ_0;
                        end
                    end

                    // SRAM read word 0: base + 0.
                    READ_0: begin
                        state <= READ_1;
                    end

                    // Capture word 0; request word 1.
                    READ_1: begin
                        read_buffer[15:0] <= sram_dout;
                        state <= READ_2;
                    end

                    // Capture word 1; request word 2.
                    READ_2: begin
                        read_buffer[31:16] <= sram_dout;
                        state <= READ_3;
                    end

                    // Capture word 2; request word 3.
                    READ_3: begin
                        read_buffer[47:32] <= sram_dout;
                        state <= READ_LAST;
                    end

                    // Capture word 3 and publish the completed buffer.
                    READ_LAST: begin

                        if (target_buffer_sel == 1'b0) begin
                            data_out1_o <= {
                                sram_dout,
                                read_buffer[47:0]
                            };
                        end else begin
                            data_out2_o <= {
                                sram_dout,
                                read_buffer[47:0]
                            };
                        end

                        data_ready_o <= 1'b1;
                        state <= DONE;
                    end

                    DONE: begin
                        // Wait for the next request.
                        if (!data_read_sync) begin
                            state <= IDLE;
                        end
                    end

                    default: begin
                        state <= IDLE;
                    end

                endcase
            end
        end
    end

    // ------------------------------------------------------------
    // IHP SRAM macro: 256 x 16 bits
    // ------------------------------------------------------------

    RM_IHPSG13_1P_256x16_c2_bm_bist HSPIO_sram (
        .A_CLK       (clk),
        .A_MEN       (sram_ren | sram_wen),
        .A_WEN       (sram_wen),
        .A_REN       (sram_ren),
        .A_ADDR      (sram_addr),
        .A_DIN       (sram_din),
        .A_DLY       (1'b1),
        .A_DOUT      (sram_dout),
        .A_BM        (sram_bm),

        .A_BIST_CLK  (1'b0),
        .A_BIST_EN   (1'b0),
        .A_BIST_MEN  (1'b0),
        .A_BIST_WEN  (1'b0),
        .A_BIST_REN  (1'b0),
        .A_BIST_ADDR (8'h00),
        .A_BIST_DIN  (16'h0000),
        .A_BIST_BM   (16'h0000)
    );

endmodule
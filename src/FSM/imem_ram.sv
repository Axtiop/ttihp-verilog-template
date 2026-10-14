module imem_ram #(
    parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 16,
    parameter int DEPTH      = 256
) (
    input  logic                  clk,
    input  logic                  rst_ni,

    // Boot/write interface
    input  logic                  wr_en,
    input  logic                  wr_byte_en,  // 0 = LSB, 1 = MSB
    input  logic [ADDR_WIDTH-1:0] wr_addr,
    input  logic [7:0]            wr_data,

    // Read interface
    input  logic                  rd_en,
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [DATA_WIDTH-1:0] rd_data
);

    // ---------------------------------------------------------
    // Byte assembly
    // ---------------------------------------------------------

    logic [7:0]  byte_buf;
    logic [15:0] word_buf;

    logic        word_ready;
    logic [ADDR_WIDTH-1:0] word_addr;

    always_ff @(posedge clk or negedge rst_ni) begin
        if (!rst_ni) begin
            byte_buf   <= '0;
            word_buf   <= '0;
            word_ready <= 1'b0;
            word_addr  <= '0;
        end
        else begin
            word_ready <= 1'b0;

            if (wr_en) begin
                if (!wr_byte_en) begin
                    // First byte: LSB
                    byte_buf <= wr_data;
                end
                else begin
                    // Second byte: MSB
                    // Assemble a complete 16-bit word
                    word_buf   <= {wr_data, byte_buf};
                    word_addr  <= wr_addr;
                    word_ready <= 1'b1;
                end
            end
        end
    end


    // ---------------------------------------------------------
    // Memory implementation
    //
    // Default:
    //   Inferred RAM for FPGA and simulation
    //
    // TARGET_ASIC:
    //   IHP SRAM macro
    // ---------------------------------------------------------

`ifndef INFERRED_RAM

    // ---------------------------------------------------------
    // ASIC: IHP SRAM macro
    //
    // The macro is a 256 x 16, single-port SRAM.
    // ---------------------------------------------------------

    logic        sram_ren;
    logic        sram_wen;
    logic [7:0]  sram_addr;
    logic [15:0] sram_din;
    logic [15:0] sram_dout;
    logic [15:0] sram_bm;

    // Write has priority over read.
    // A single-port SRAM cannot perform both operations
    // simultaneously.

    always_comb begin
        sram_ren  = 1'b0;
        sram_wen  = 1'b0;
        sram_addr = '0;
        sram_din  = word_buf;
        sram_bm   = '1;

        if (word_ready) begin
            // Write a complete 16-bit word
            sram_wen  = 1'b1;
            sram_addr = word_addr;
        end
        else if (rd_en) begin
            // Read a 16-bit word
            sram_ren  = 1'b1;
            sram_addr = rd_addr;
        end
    end

    RM_IHPSG13_1P_256x16_c2_bm_bist i_sram (
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
        .A_BIST_ADDR (8'h0),
        .A_BIST_DIN  (16'h0),
        .A_BIST_BM   (16'h0)
    );

    // The SRAM macro provides synchronous read data.
    assign rd_data = sram_dout;


`else

    // ---------------------------------------------------------
    // FPGA / simulation: inferred RAM
    // ---------------------------------------------------------

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        // Write has priority over read, matching the ASIC
        // single-port SRAM behavior.
        if (word_ready) begin
            mem[word_addr] <= word_buf;
        end
        else if (rd_en) begin
            rd_data <= mem[rd_addr];
        end
    end

`endif

endmodule
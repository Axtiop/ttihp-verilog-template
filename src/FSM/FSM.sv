import isr_config_pkg::*;

module FSM #(
    parameter int unsigned NumGPIOS = 8,
    parameter int unsigned IMEM_DEPTH = 256
) (
    // Clock and reset
    input  logic clk,
    input  logic rst_ni,

    // I/O
    inout  wire [NumGPIOS-1:0] gpio_io,

    // Data
    input logic [7:0]  data_out,
    input logic        data_valid,

    // Boot status
    input logic        boot_finished,

    // Number of received words, saturating at 512
    input logic [8:0]  word_count,
    input logic        imem_load
);

    // Stop everything while boot is not finished
    logic boot_reset_n;
    assign boot_reset_n = rst_ni & boot_finished;  

    // resynchronised I/Os to avoid metastability
    logic [NumGPIOS-1:0] gpio_io_2r;


    // =========================================================================
    // Types / constants
    // =========================================================================

    localparam int unsigned ADDR_WIDTH = 8;
    localparam int unsigned DATA_WIDTH = 16;

    // -------------------------------------------------------------------------
    // Opcodes
    //
    // [15:14]
    //
    // 00 = JMP
    // 01 = WAIT
    // 10 = MOV
    // -------------------------------------------------------------------------

    localparam logic [1:0] OP_JMP  = 2'b00;
    localparam logic [1:0] OP_WAIT = 2'b01;
    localparam logic [1:0] OP_MOV  = 2'b10;
    localparam logic [1:0] OP_NOP  = 2'b11;


    // =========================================================================
    // Registers
    // =========================================================================

    logic [7:0] pc;

    // OSR
    logic [15:0] osr0;
    logic [15:0] osr1;
    logic [15:0] osr2;
    logic [15:0] osr3;
    logic [15:0] osr4;
    logic [15:0] osr5;
    logic [15:0] osr6;
    logic [15:0] osr7;
    logic [7:0] update_osr;

    // ISR
    logic [15:0] isr0;
    logic [15:0] isr1;
    logic [15:0] isr2;
    logic [15:0] isr3;
    logic [15:0] isr4;
    logic [15:0] isr5;
    logic [15:0] isr6;
    logic [15:0] isr7;
    logic [7:0] isr_full; // TODO: link that to something.    

    // Other registers
    logic [15:0] conf0;
    logic [15:0] conf1;
    logic [15:0] rgp;

    // 8 ISR configurations, indexed by ISR ID [6:4]
    isr_config_t isr_configs [8];

    // =========================================================================
    // Instruction memory
    // =========================================================================
logic [127:0] dmem [0:31];

logic [15:0] instruction;

logic        imem_wr_en;
logic        imem_wr_byte_en;
logic [7:0]  imem_wr_addr;
logic [7:0]  imem_wr_data;

logic        imem_rd_en;
logic [7:0]  imem_rd_addr;

logic [15:0] imem_rdata;


// ------------------------------------------------------------
// IMEM write interface
// ------------------------------------------------------------

assign imem_wr_en      = !boot_finished && data_valid && imem_load;
assign imem_wr_byte_en = word_count[0];
assign imem_wr_addr    = word_count[8:1];
assign imem_wr_data    = data_out;


// ------------------------------------------------------------
// IMEM read interface
// ------------------------------------------------------------

assign imem_rd_en   = boot_finished;
assign imem_rd_addr = pc;

assign instruction = imem_rdata;


// ------------------------------------------------------------
// IMEM
// ------------------------------------------------------------

imem_ram #(
    .ADDR_WIDTH(8),
    .DATA_WIDTH(16),
    .DEPTH(256)
) u_imem (
    .clk        (clk),
    .rst_ni     (rst_ni),

    // Write
    .wr_en      (imem_wr_en),
    .wr_byte_en (imem_wr_byte_en),
    .wr_addr    (imem_wr_addr),
    .wr_data    (imem_wr_data),

    // Read
    .rd_en      (imem_rd_en),
    .rd_addr    (imem_rd_addr),
    .rd_data    (imem_rdata)
);


// ------------------------------------------------------------
// DMEM
// ------------------------------------------------------------

always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
        for (int j = 0; j < 32; j++) begin
            dmem[j] <= '0;
        end
    end
    else if (!boot_finished && data_valid) begin

        if (!imem_load) begin
            dmem[word_count[8:4]]
                [word_count[3:0]*8 +: 8] <= data_out;
        end

    end
end


    // =========================================================================
    // Instruction decode
    // =========================================================================

    logic [1:0] opcode;
    logic wait_active;
    logic jump_active;
    assign opcode = jump_active ? OP_NOP :
                    wait_active ? OP_WAIT :
                    instruction[15:14];


    // -------------------------------------------------------------------------
    // JMP fields
    //
    // 15:14 = opcode
    // 13:12 = RES
    // 11:8  = COND
    // 7:0   = Address
    // -------------------------------------------------------------------------

    logic [2:0]  jmp_cond;
    logic [7:0]  jmp_address;

    assign jmp_cond    = instruction[10:8];
    assign jmp_address = instruction[7:0];


    // -------------------------------------------------------------------------
    // WAIT fields
    //
    // 15:14 = opcode
    // 13:11 = RES
    // 10    = Pol
    // 9:8   = src
    // 7:0   = Imm
    // -------------------------------------------------------------------------

    logic       wait_pol;
    logic [1:0] wait_src;
    logic [7:0] wait_imm;
    logic       wait_pol_r;
    logic [1:0] wait_src_r;
    logic [7:0] wait_imm_r;
    logic [7:0] wait_count;

    assign wait_pol = wait_active ? wait_pol_r : instruction[10];
    assign wait_src = wait_active ? wait_src_r : instruction[9:8];
    assign wait_imm = wait_active ? wait_imm_r : instruction[7:0];



    // -------------------------------------------------------------------------
    // MOV fields
    //
    // 15:14 = opcode
    // 13    = Imm
    // 12:10 = Op
    // 9:7   = Dest
    // 6:0   = src/Imm
    // -------------------------------------------------------------------------

    logic       mov_op;
    logic [4:0] mov_dest;
    logic [4:0] mov_slice;
    logic [2:0] mov_word;
    logic [7:0] isr_shift_on_mov;

    assign mov_op      = instruction[13];
    assign mov_dest    = instruction[12:8];
    assign mov_slice   = instruction[4:0];
    assign mov_word  = mov_op ? 3'b000 : instruction[7:5];
    



    // =========================================================================
    // MOV source data
    // =========================================================================
    //
    // The source is an IMEM address.
    //
    // Since the address field is currently only 7 bits, this accesses:
    //
    //     IMEM[0x00 ... 0x7F]
    //
    // The remaining IMEM addresses can be used by other mechanisms if desired.
    //
    // =========================================================================

    logic [15:0] mov_data0;
    logic [15:0] mov_data1;
    logic [15:0] mov_data2;
    logic [15:0] mov_data3;
    logic [15:0] mov_data4;
    logic [15:0] mov_data5;
    logic [15:0] mov_data6;
    logic [15:0] mov_data7;


    assign mov_data0 = dmem[mov_slice][mov_word*16 +:16];
    assign mov_data1 = dmem[mov_slice][31:16];
    assign mov_data2 = dmem[mov_slice][47:32];
    assign mov_data3 = dmem[mov_slice][63:48];
    assign mov_data4 = dmem[mov_slice][79:64];
    assign mov_data5 = dmem[mov_slice][95:80];
    assign mov_data6 = dmem[mov_slice][111:96];
    assign mov_data7 = dmem[mov_slice][127:112];


    // =========================================================================
    // Register destination encoding
    // =========================================================================

    localparam logic [4:0] DEST_OSR0  = 5'd0;
    localparam logic [4:0] DEST_OSR1  = 5'd1;
    localparam logic [4:0] DEST_OSR2  = 5'd2;
    localparam logic [4:0] DEST_OSR3  = 5'd3;
    localparam logic [4:0] DEST_OSR4  = 5'd4;
    localparam logic [4:0] DEST_OSR5  = 5'd5;
    localparam logic [4:0] DEST_OSR6  = 5'd6;
    localparam logic [4:0] DEST_OSR7  = 5'd7;

    localparam logic [4:0] DEST_ISR0  = 5'd8;
    localparam logic [4:0] DEST_ISR1  = 5'd9;
    localparam logic [4:0] DEST_ISR2  = 5'd10;
    localparam logic [4:0] DEST_ISR3  = 5'd11;
    localparam logic [4:0] DEST_ISR4  = 5'd12;
    localparam logic [4:0] DEST_ISR5  = 5'd13;
    localparam logic [4:0] DEST_ISR6  = 5'd14;
    localparam logic [4:0] DEST_ISR7  = 5'd15;
    
    localparam logic [4:0] DEST_CONF0 = 5'd16;
    localparam logic [4:0] DEST_CONF1 = 5'd17;
    localparam logic [4:0] DEST_CONF_ISRx = 5'd18;
    localparam logic [4:0] DEST_RGP   = 5'd19;


    // =========================================================================
    // Sequential CPU
    // =========================================================================

    always_ff @(posedge clk or negedge boot_reset_n) begin

        if (!boot_reset_n) begin

            pc         <= 8'h00;
            wait_active <= 1'b0;
            jump_active <= 1'b0;
            update_osr <= 8'h00;

            osr0   <= 16'h0000;
            osr1   <= 16'h0000;
            osr2   <= 16'h0000;
            osr3   <= 16'h0000;
            osr4   <= 16'h0000;
            osr5   <= 16'h0000;
            osr6   <= 16'h0000;
            osr7   <= 16'h0000;

            conf0       <= 16'h00ff;
            conf1       <= 16'h0000;
            for (int i = 0; i < 8; i++) begin
                isr_configs[i] <= '0;
            end
            rgp         <= 16'h0000;
            wait_count  <= 8'h00;
            isr_shift_on_mov <= 8'h00;

        end
        else begin

            // Default: next instruction
            pc <= pc + 8'd1;
            update_osr <= 8'h00;
            isr_shift_on_mov <= 8'h00;
            jump_active <= 1'b0;
            if (wait_active) begin
                wait_pol_r <= wait_pol_r;
                wait_src_r <= wait_src_r;
                wait_imm_r <= wait_imm_r;
            end 
            else begin
                wait_pol_r <= wait_pol;
                wait_src_r <= wait_src;
                wait_imm_r <= wait_imm;
            end


            case (opcode)

                // =============================================================
                // JMP
                // =============================================================

                OP_JMP: begin

                    case (jmp_cond)

                        // -------------------------------------------------------------
                        // 000: Unconditional jump
                        // -------------------------------------------------------------

                        3'b000: begin
                            pc <= jmp_address;
                            jump_active <= 1'b1;
                        end


                        // -------------------------------------------------------------
                        // 001: RGP0--
                        //
                        // Jump if RGP != 0.
                        // Check is performed BEFORE decrement.
                        //
                        // RGP == 0:
                        //     no jump
                        //     RGP remains 0
                        //
                        // RGP != 0:
                        //     decrement RGP
                        //     jump
                        // -------------------------------------------------------------

                        3'b001: begin
                            if (rgp != 16'h0000) begin
                                rgp <= rgp - 16'd1;
                                pc  <= jmp_address;
                                jump_active <= 1'b1;
                            end
                        end

                        // -------------------------------------------------------------
                        // Reserved conditions
                        // -------------------------------------------------------------

                        default: begin
                            // No jump.
                        end

                    endcase

                end


                // =============================================================
                // WAIT
                // =============================================================

                OP_WAIT: begin

                    case (wait_src)

                        
                        2'b00: begin

                            wait_active <= 1'b1;
                            // Wait/count mode
                            if (wait_count < wait_imm) begin
                                wait_count <= wait_count + 8'd1;
                                pc         <= pc;
                                wait_active <= 1'b1;
                            end
                            else begin
                                wait_count <= 8'h00;
                                wait_active <= 1'b0;
                                // pc already incremented above
                            end
                        end

                        2'b01: begin
                            // GPIO wait
                            //
                            // wait_imm = GPIO mask
                            // wait_pol = expected GPIO level
                            //
                            // For every bit where wait_imm == 1:
                            //     if GPIO == wait_pol
                            //         condition is satisfied -> leave WAIT
                            //
                            // If none of the selected GPIOs match:
                            //     stay on the WAIT instruction.

                            if (|(wait_imm & gpio_io_2r) && !wait_pol) begin
                                // At least one selected GPIO is 1.
                                // wait_pol == 0, so this isn't a match.
                                wait_active <= 1'b1;
                                pc <= pc;
                            end
                            else if (|((~wait_imm) & gpio_io_2r) && wait_pol) begin
                                // This isn't the desired masked comparison.
                                wait_active <= 1'b1;
                                pc <= pc;
                            end
                            else begin
                                wait_active <= 1'b0;
                            end

                        end

                        default: begin
                            // Other WAIT sources not implemented yet.
                            pc <= pc;
                        end

                    endcase

                end


                // =============================================================
                // MOV
                // =============================================================


                OP_MOV: begin

                    // ---------------------------------------------------------------------
                    // Special MOV operation:
                    //
                    // conf1[7:0] is an update mask.
                    //
                    //   conf1[0] = 1 -> OSR0 <= IMEM[mov_address + 0]
                    //   conf1[1] = 1 -> OSR1 <= IMEM[mov_address + 1]
                    //   ...
                    //   conf1[7] = 1 -> OSR7 <= IMEM[mov_address + 7]
                    //
                    // This behavior is selected when mov_op == 1.
                    // ---------------------------------------------------------------------

                    if (mov_op == 1'b1) begin

                        if (conf1[0])
                            osr0 <= mov_data0;

                        if (conf1[1])
                            osr1 <= mov_data1;

                        if (conf1[2])
                            osr2 <= mov_data2;

                        if (conf1[3])
                            osr3 <= mov_data3;

                        if (conf1[4])
                            osr4 <= mov_data4;

                        if (conf1[5])
                            osr5 <= mov_data5;

                        if (conf1[6])
                            osr6 <= mov_data6;

                        if (conf1[7])
                            osr7 <= mov_data7;

                        update_osr <= conf1[7:0];

                    end

                    // ---------------------------------------------------------------------
                    // Normal MOV operation.
                    // ---------------------------------------------------------------------
                    else begin

                        case (mov_dest)

                            DEST_OSR0: begin
                                osr0 <= mov_data0;
                                update_osr[0] <= 1'b1;
                            end

                            DEST_OSR1: begin
                                osr1 <= mov_data0;
                                update_osr[1] <= 1'b1;
                            end

                            DEST_OSR2: begin
                                osr2 <= mov_data0;
                                update_osr[2] <= 1'b1;
                            end

                            DEST_OSR3: begin
                                osr3 <= mov_data0;
                                update_osr[3] <= 1'b1;
                            end

                            DEST_OSR4: begin
                                osr4 <= mov_data0;
                                update_osr[4] <= 1'b1;
                            end

                            DEST_OSR5: begin
                                osr5 <= mov_data0;
                                update_osr[5] <= 1'b1;
                            end

                            DEST_OSR6: begin
                                osr6 <= mov_data0;
                                update_osr[6] <= 1'b1;
                            end

                            DEST_OSR7: begin
                                osr7 <= mov_data0;
                                update_osr[7] <= 1'b1;
                            end

                            DEST_CONF0: begin
                                conf0 <= mov_data0;
                            end

                            DEST_CONF1: begin
                                conf1 <= mov_data0;
                            end

                            DEST_CONF_ISRx: begin
                                isr_configs[mov_data0[9:7]] = isr_config_t'(mov_data0[6:0]);
                                isr_shift_on_mov[mov_data0[9:7]] <= 1'b1;

                            end 

                            DEST_RGP: begin
                                rgp <= mov_data0;
                            end

                            default: begin
                                // Reserved destination.
                            end

                        endcase

                    end

                end


                default: begin
                    // Reserved opcode.
                end

            endcase

        end

    end

    
    PIO uPIO (
        // Clock and reset
        .clk    (clk),
        .rst_ni (boot_reset_n),

        // Registers
        .update_osr (update_osr),
        .osr0        (osr0),
        .osr1        (osr1),
        .osr2        (osr2),
        .osr3        (osr3),
        .osr4        (osr4),
        .osr5        (osr5),
        .osr6        (osr6),
        .osr7        (osr7),

        .isr0        (isr0),
        .isr1        (isr1),
        .isr2        (isr2),
        .isr3        (isr3),
        .isr4        (isr4),
        .isr5        (isr5),
        .isr6        (isr6),
        .isr7        (isr7),

        .conf0      (conf0),
        .conf1      (conf1),
        .isr_configs (isr_configs),
        .isr_shift_on_mov (isr_shift_on_mov),

        // I/O
        .gpio_io    (gpio_io),
        .gpio_io_2r (gpio_io_2r),

        // ISR status
        .isr_full   (isr_full)
    );


endmodule
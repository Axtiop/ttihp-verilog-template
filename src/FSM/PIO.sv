

module PIO #(
    parameter int NumGPIOS = 8
) (
    // Clock and reset
    input  logic clk,
    input  logic rst_ni,

    // Registers
    input  logic [7:0] update_osr,
    input  logic [15:0] osr0,
    input  logic [15:0] osr1,
    input  logic [15:0] osr2,
    input  logic [15:0] osr3,
    input  logic [15:0] osr4,
    input  logic [15:0] osr5,
    input  logic [15:0] osr6,
    input  logic [15:0] osr7,

    output logic [15:0] isr0,
    output logic [15:0] isr1,
    output logic [15:0] isr2,
    output logic [15:0] isr3,
    output logic [15:0] isr4,
    output logic [15:0] isr5,
    output logic [15:0] isr6,
    output logic [15:0] isr7,

    input  logic [15:0] conf0,
    input  logic [15:0] conf1,
    input  logic [55:0] isr_configs,
    input logic [7:0] isr_shift_on_mov,

    // I/O
    inout  wire [NumGPIOS-1:0] gpio_io,
    output logic [NumGPIOS-1:0] gpio_io_2r,

    // ISR status
    output logic [7:0] isr_full
);

    localparam logic [1:0] SHIFT_NONE  = 2'b00;
    localparam logic [1:0] SHIFT_CLOCK = 2'b01;
    localparam logic [1:0] SHIFT_EVENT = 2'b10;
    localparam logic [1:0] SHIFT_MOV   = 2'b11;

    localparam logic [1:0] EVENT_RISING  = 2'b00;
    localparam logic [1:0] EVENT_FALLING = 2'b01;
    localparam logic [1:0] EVENT_HIGH    = 2'b10;
    localparam logic [1:0] EVENT_LOW     = 2'b11;


    logic [6:0] isr_configs_flat [0:7];

    always_comb begin
        for (int j = 0; j < 8; j++) begin
            isr_configs_flat[j] = isr_configs[j*7 +:7];
        end
    end

    logic [7:0] gpio_io_r;

    logic [7:0] gpio_out;
    logic [7:0] gpio_out_r;
    logic [7:0] gpio_out_2r;
    logic [7:0] gpio_oe;

    assign gpio_oe = ~conf0[7:0];

    // GPIO output
    genvar k;
    generate
        for (k = 0; k < 8; k++) begin
            assign gpio_io[k] =
                gpio_oe[k] ? gpio_out_2r[k] : 1'bz;
        end
    endgenerate

    // 2-flop synchronizer for GPIO
    always_ff @(posedge clk) begin
        gpio_out_r <= gpio_out;
        gpio_out_2r <= gpio_out_r;

        gpio_io_r  <= gpio_io;
        gpio_io_2r <= gpio_io_r;
    end

    // ------------------------------------------------------------
    // Internal registers
    // ------------------------------------------------------------

    // Working copy of OSR.
    // This is the register that actually gets shifted.
    logic [15:0] osr0_shadow;
    logic [15:0] osr1_shadow;
    logic [15:0] osr2_shadow;
    logic [15:0] osr3_shadow;
    logic [15:0] osr4_shadow;
    logic [15:0] osr5_shadow;
    logic [15:0] osr6_shadow;
    logic [15:0] osr7_shadow;

    // Number of valid bits currently stored in ISR.
    logic [4:0] isr_count;

    logic [7:0] gpio_io_d;
    logic [15:0] isr [8];

    assign isr0 = isr[0];
    assign isr1 = isr[1];
    assign isr2 = isr[2];
    assign isr3 = isr[3];
    assign isr4 = isr[4];
    assign isr5 = isr[5];
    assign isr6 = isr[6];
    assign isr7 = isr[7];
    // ------------------------------------------------------------
    // GPIO output mux
    // ------------------------------------------------------------

    always_comb begin
        gpio_out[0] = osr0_shadow[0];
        gpio_out[1] = osr1_shadow[0];
        gpio_out[2] = osr2_shadow[0];
        gpio_out[3] = osr3_shadow[0];
        gpio_out[4] = osr4_shadow[0];
        gpio_out[5] = osr5_shadow[0];
        gpio_out[6] = osr6_shadow[0];
        gpio_out[7] = osr7_shadow[0];
    end


    // ------------------------------------------------------------
    // Sequential logic output
    // ------------------------------------------------------------

    always_ff @(posedge clk or negedge rst_ni) begin

        if (!rst_ni) begin

            // Synchronize our copies with the externally visible OSR.
            osr0_shadow <= 16'h0000;
            osr1_shadow <= 16'h0000;
            osr2_shadow <= 16'h0000;
            osr3_shadow <= 16'h0000;
            osr4_shadow <= 16'h0000;
            osr5_shadow <= 16'h0000;
            osr6_shadow <= 16'h0000;
            osr7_shadow <= 16'h0000;

        end
        else begin

            // ----------------------------------------------------
            // Detect an OSR update
            // ----------------------------------------------------
            //
            // If software/hardware has changed OSR since the
            // previous clock, reload the shadow.
            //
            if (update_osr[0])
                osr0_shadow <= osr0;
            else
                osr0_shadow <= {osr0_shadow[0], osr0_shadow[15:1]};

            if (update_osr[1])
                osr1_shadow <= osr1;
            else 
                osr1_shadow <= {osr1_shadow[0], osr1_shadow[15:1]};

            if (update_osr[2])
                osr2_shadow <= osr2;
            else
                osr2_shadow <= {osr2_shadow[0], osr2_shadow[15:1]};

            if (update_osr[3])
                osr3_shadow <= osr3;
            else 
                osr3_shadow <= {osr3_shadow[0], osr3_shadow[15:1]};

            if (update_osr[4])
                osr4_shadow <= osr4;
            else
                osr4_shadow <= {osr4_shadow[0], osr4_shadow[15:1]};

            if (update_osr[5])
                osr5_shadow <= osr5;
            else
                osr5_shadow <= {osr5_shadow[0], osr5_shadow[15:1]};

            if (update_osr[6])
                osr6_shadow <= osr6;
            else
                osr6_shadow <= {osr6_shadow[0], osr6_shadow[15:1]};

            if (update_osr[7])
                osr7_shadow <= osr7;
            else
                osr7_shadow <= {osr7_shadow[0], osr7_shadow[15:1]};

        end

    end



    // ------------------------------------------------------------
    // Sequential logic input
    // ------------------------------------------------------------
always_ff @(posedge clk or negedge rst_ni) begin

    if (!rst_ni) begin

        // Reset ISR shift registers
        for (int i = 0; i < 8; i++) begin
            isr[i] <= 16'h0000;
        end

        // Previous GPIO state, used for edge detection
        gpio_io_d <= 8'h00;

        isr_count <= 5'd0;
        isr_full  <= 8'h00;

    end
    else begin

        // Store current GPIO state for use during the next clock
        gpio_io_d <= gpio_io_2r;

        // Process all ISR registers
        for (int i = 0; i < 8; i++) begin


            case (isr_configs_flat[i][1:0])

                // ------------------------------------------------
                // No shift
                // ------------------------------------------------
                SHIFT_NONE: begin
                    // Nothing to do
                end


                // ------------------------------------------------
                // Shift on every clock
                // ------------------------------------------------
                SHIFT_CLOCK: begin

                    isr[i] <= {
                        isr[i][14:0],
                        gpio_io_d[isr_configs_flat[i][6:4]]
                    };

                end

                // ------------------------------------------------
                // Shift on event
                // ------------------------------------------------
                SHIFT_EVENT: begin

                    case (isr_configs_flat[i][3:2])

                        // ----------------------------------------
                        // Rising edge
                        // ----------------------------------------
                        EVENT_RISING: begin

                            if (gpio_io_2r[isr_configs_flat[i][6:4]] &&
                                !gpio_io_d[isr_configs_flat[i][6:4]]) begin

                                isr[i] <= {
                                    isr[i][14:0],
                                    gpio_io_d[i]
                                };

                            end

                        end


                        // ----------------------------------------
                        // Falling edge
                        // ----------------------------------------
                        EVENT_FALLING: begin

                            if (!gpio_io_2r[isr_configs_flat[i][6:4]] &&
                                gpio_io_d[isr_configs_flat[i][6:4]]) begin

                                isr[i] <= {
                                    isr[i][14:0],
                                    gpio_io_d[i]
                                };

                            end

                        end


                        // ----------------------------------------
                        // Level high
                        // ----------------------------------------
                        EVENT_HIGH: begin

                            if (gpio_io_2r[isr_configs_flat[i][6:4]]) begin

                                isr[i] <= {
                                    isr[i][14:0],
                                    gpio_io_d[i]
                                };

                            end

                        end


                        // ----------------------------------------
                        // Level low
                        // ----------------------------------------
                        EVENT_LOW: begin

                            if (!gpio_io_2r[isr_configs_flat[i][6:4]]) begin

                                isr[i] <= {
                                    isr[i][14:0],
                                    gpio_io_d[i]
                                };

                            end

                        end


                        default: begin
                            // Reserved event type
                        end

                    endcase

                end

                SHIFT_MOV: begin
                    // TODO
                    if (isr_shift_on_mov[i]) begin
                        isr[i] <= {
                            isr[i][14:0],
                            gpio_io_d[i]
                        };
                    end 

                end

                default: begin
                    // Reserved shift mode
                end

            endcase

        end

    end

end


endmodule
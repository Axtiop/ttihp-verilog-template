# project.sdc: replaces LibreLane's default base.sdc

# Helper: read a flow variable if it exists, else use a fallback
proc cfg {name default} {
    if {[info exists ::env($name)]} { return $::env($name) }
    return $default
}

# Return the ports of 'ports' whose names are not in 'excluded_names'
proc ports_without {ports excluded_names} {
    set result {}
    foreach p $ports {
        if {[lsearch -exact $excluded_names [get_property $p name]] < 0} {
            lappend result $p
        }
    }
    return $result
}

set period [cfg CLOCK_PERIOD 20.0]

# Placeholders: replace them with the values from the installed base.sdc.
# I'm not certain these env names match your LibreLane version, so the
# fallbacks apply if they don't.
set io_pct       0.2
set uncertainty  0.25
set transition   0.15
set derate       0.05
set cap_load_pf  0.033

# ---- Clocks ----
create_clock [get_ports clk]        -name main_clk -period $period
create_clock [get_ports {ui_in[6]}] -name aux_clk  -period $period

set_clock_uncertainty $uncertainty [get_clocks {main_clk aux_clk}]
set_clock_transition  $transition  [get_clocks {main_clk aux_clk}]

# Asynchronous domains: no timing on paths between them.
# The CDC itself must be verified by lint or simulation, not by STA.
set_clock_groups -asynchronous -group {main_clk} -group {aux_clk}

# ---- Port lists ----
set clk_ports  [get_ports {clk ui_in[6]}]
set data_in  [ports_without [all_inputs] {clk ui_in[6]}]

set aux_out  [get_ports {uo_out[0] uo_out[1] uo_out[2] uo_out[3] uo_out[4]}]
set aux_out_names {uo_out[0] uo_out[1] uo_out[2] uo_out[3] uo_out[4]}
set main_out [ports_without [all_outputs] $aux_out_names]

# ---- I/O timing ----
set io_delay [expr {$period * $io_pct}]

# All data inputs belong to the main clock (rx, error_modes_i, uio_in, rst_n)
set_input_delay  $io_delay -clock main_clk $data_in

# uo_out[4:0] come from aux_clk flops, the rest from main_clk flops
set_output_delay $io_delay -clock aux_clk  $aux_out
set_output_delay $io_delay -clock main_clk $main_out

# ---- Electrical environment (as in the default SDC) ----
set_driving_cell -lib_cell [cfg SYNTH_DRIVING_CELL sg13g2_buf_1] \
                 -pin      [cfg SYNTH_DRIVING_CELL_PIN X] $data_in
set_load $cap_load_pf [all_outputs]
set_max_fanout [cfg MAX_FANOUT_CONSTRAINT 10] [current_design]

set_timing_derate -early [expr {1 - $derate}]
set_timing_derate -late  [expr {1 + $derate}]

# ---- Per-I/O overrides go here, e.g. ----
# set_input_delay 5.0 -clock main_clk [get_ports {ui_in[7]}]
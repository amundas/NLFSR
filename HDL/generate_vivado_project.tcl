# Run with "vivado -mode batch -source generate_project.tcl"
# This file creates a vivado project that can be used to build the FPGA implementation 
file mkdir ./vivado
set outputdir ./vivado

create_project -force nlfsr_finder_NEW ./vivado -part xc7k325tffg900-2

add_files -fileset constrs_1 ./genesys2_constraints.xdc 
add_files { ./top/genesys_top_wrapper.v \
            ./top/nlfsr_top.v \
            ./top/mmcm_wrapper.v \
            ./top/build_settings.vh \
            ./distributor/distributor.v \
            ./nlfsr_tester/nlfsr_tester.v \
            ./fifo/fifo.v \
            ./uart/receiver.v \
            ./uart/sender.v \
            ./uart/uart_tx.v \
            ./uart/uart_rx.v}

set_property top genesys_top_wrapper [current_fileset]
update_compile_order -fileset sources_1

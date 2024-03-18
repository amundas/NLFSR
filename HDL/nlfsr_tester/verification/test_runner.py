from cocotb.runner import get_runner
import subprocess
import warnings

# Kind of hacky way to create waveform file without having to use $dumpvars etc it in the source files
# Based on the cocotb way to do it with makefiles (the "new" pytest-based approach does not have working support for this yet as of version 1.8.1)
def get_dumpsource(top_level):
    return ('module cocotb_iverilog_dump();\n'
            'initial begin\n'
            f'$dumpfile("./{top_level}.fst"); $dumpvars(0, {top_level});\n'
            'end\n'
            'endmodule')

# The runner function. Pytest calls functions starting with "test"
# Run using "pytest -s --tb=no <options>"
def test_runner(request):
    top_level = "nlfsr_tester"      # Name of HDL top module
    test_module = f"{top_level}_tb" # Name of the cocotb testbench
    proj_path = ".."
    files = ["nlfsr_tester.v"]
    verilog_sources = [f"{proj_path}/{f}" for f in files]
    build_dir = "sim_build"

    ############# Handle command line options #############
    if request.config.getoption("--clean"):
        subprocess.run(['rm', '-rf', f'./{build_dir}'])

    build_args = []
    sim = request.config.getoption("--sim")
    if sim == "icarus":
        build_args = ["-s", top_level]

    width = request.config.getoption("--width")
    num_nlin = request.config.getoption("--num-nlin")
    num_nlin_idx = request.config.getoption("--num-nlin-idx")

    parameters = {
        "SHIFTREG_WIDTH": width,
        "NUM_NLIN": num_nlin,
        "NUM_NLIN_IDX": num_nlin_idx,
    }
    # Waves needs some work, the "waves" option in runner.test() is not functional for icarus
    plusargs = []
    waves = request.config.getoption("--waves")
    if waves and sim == "icarus":
        plusargs.append("-fst")
        dump_file = f"./{build_dir}/cocotb_iverilog_dump.v"
        with open(dump_file, "w") as f:
            f.write(get_dumpsource(top_level))
        verilog_sources.append(dump_file)
        build_args.extend(["-s", "cocotb_iverilog_dump"])

    # Select which tests to run based on command line options. 
    # If none specified, don't run any tests
    if request.config.getoption("--full") or request.config.getoption("--only"):
        coco_tests = [] # Empty means all tests
        if request.config.getoption("--only"):
            coco_tests = [request.config.getoption("--only")]

        # Run the selected cocotb tests
        runner = get_runner(sim)
        runner.build(
            verilog_sources=verilog_sources,
            hdl_toplevel=top_level,
            parameters=parameters,
            build_dir=build_dir,
            build_args=build_args,
            always=True,
        )
        runner.test(hdl_toplevel=top_level, test_module=test_module, testcase=coco_tests, plusargs=plusargs, build_dir=build_dir, waves=waves)
    else:
        warnings.warn(UserWarning("No cocotb tests selected. Use --full or --only to run tests"))
    if request.config.getoption("--open-waves"):
        subprocess.Popen(['gtkwave', f'./{build_dir}/{top_level}.fst'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    
    if request.config.getoption("--synth"):
        # "xcup" is UltraScale+ family
        res = subprocess.run(['yosys', '-p', f'synth_xilinx -family xcup -top {top_level}', f'{" ".join(verilog_sources)}'], capture_output=True)
        output = res.stdout.decode('utf-8')
        # output contains lots of text, and then This line "2.26. Printing statistics.". We print everything after that line
        output = output[output.find("Printing statistics.") + len("Printing statistics."):]
        print("\n\n************ Synthesis Resource Report ************")
        print(output)

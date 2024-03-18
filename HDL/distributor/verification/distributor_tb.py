import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge, First
import random
import galois
import math
import numpy as np
import sys
# Get various helper functions from the python directory
sys.path.append('../../../../software/')
import nlfsr_utils

def get_random(n, num_nlin, num_nlin_idx) -> int:
    clog2 = math.ceil(math.log(n-1, 2))
    rand_setting = random.getrandbits(n-1)
    for i in range(num_nlin*num_nlin_idx):
        idx = random.randint(0, n-2)
        rand_setting |= idx << (n-1 + clog2*i)
    return rand_setting

def get_known_good(n, num_nlin, num_nlin_idx) -> int:
    # First, get a primitive polynomial and use it as the linear part of the feedback
    pol = galois.primitive_poly(2, n, terms="min", method='random').coefficients(order='asc')
    # pol is a list of ones and zeros, we convert it to an int discarding the first and last element
    lin = int("".join([str(x) for x in pol[1:n]]), 2)
    # Now, get a "fake" non-linear part that does nothing
    clog2 = math.ceil(math.log(n-1, 2))
    nlin_part = 0
    for i in range(num_nlin):
        # pick a random index, and add a monomial like "x_k * x_k * x_k ..." as a "fake" non-linear term 
        idx = random.randint(0, n-2)
        for j in range(num_nlin_idx):
            nlin_part |= idx << (clog2*(num_nlin_idx*i + j))
        # flip idx'th bit in lin
        lin ^= 1 << idx
    cand = lin
    cand |= nlin_part << (n-1)
    return cand

def is_max_period(cand, n, num_nlin, num_nlin_idx) -> bool:
    lst = nlfsr_utils.format_fpga2list(cand, n, num_nlin, num_nlin_idx)
    lin, nlins = nlfsr_utils.format_list2vec(lst)
    period = nlfsr_utils.test_period(n, lin, nlins)
    return period == ((1 << n) - 1)

# This function is meant to run "unwatched". It will fill success_list with the outputs of the DUT
async def get_outputs(dut, success_list):
    await RisingEdge(dut.clk)
    while True:
        await RisingEdge(dut.clk)
        if (dut.success.value == 1):
            dut.setting_rd_en.value = 1
            success_list.append(dut.setting_out.value.integer)
            await RisingEdge(dut.clk)
            dut.setting_rd_en.value = 0

# Basic test, useful for small tests and waveform debugging
@cocotb.test()
async def basic_test(dut):
    n, num_nlin, num_nlin_idx = dut.SHIFTREG_WIDTH.value, dut.NUM_NLIN.value, dut.NUM_NLIN_IDX.value
    cocotb.start_soon(Clock(dut.clk, 1, units="ns").start())
    
    # Assign DUT inputs
    dut.start.value = 0
    dut.setting_in.value = 0
    dut.setting_rd_en.value = 0

    # Test a known good (n)lfsr
    known_good = get_known_good(n, num_nlin, num_nlin_idx)
    dut.setting_in.value = known_good
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0     
    dut.setting_in.value = get_random(n, num_nlin, num_nlin_idx)
    await RisingEdge(dut.clk)
    await FallingEdge(dut.running)
    assert (dut.success.value == 1)
    dut.setting_rd_en.value = 1
    await RisingEdge(dut.clk)
    dut.setting_rd_en.value = 0
    await ClockCycles(dut.clk, 5)

# Several random inputs, one known good input
@cocotb.test()
async def needle_in_haystack(dut):
    n, num_nlin, num_nlin_idx = dut.SHIFTREG_WIDTH.value, dut.NUM_NLIN.value, dut.NUM_NLIN_IDX.value
    success_list = []
    cocotb.start_soon(Clock(dut.clk, 1, units="ns").start())
    cocotb.start_soon(get_outputs(dut, success_list))

    # Assign DUT inputs
    dut.start.value = 0
    dut.setting_in.value = 0
    dut.setting_rd_en.value = 0

    haystack_size = 100
    needle_idx = random.randint(0, haystack_size-1)
    haystack = [get_random(n, num_nlin, num_nlin_idx) for _ in range(haystack_size)]
    haystack[needle_idx] = get_known_good(n, num_nlin, num_nlin_idx)
    num_written = 0
    while num_written < haystack_size:
        while dut.idle.value == 0:
            await RisingEdge(dut.clk)
        dut.setting_in.value = haystack[num_written]
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        await RisingEdge(dut.clk)
        num_written += 1
    await FallingEdge(dut.running)
    await RisingEdge(dut.clk)
    # Now check the results
    # It's not uncommon to randomly generate a max period LFSR for small N, so we can have "accidental needles"
    expected_results = [setting for setting in haystack if is_max_period(setting, n, num_nlin, num_nlin_idx)]
    assert len(success_list) == len(expected_results)
    expected_results.sort()
    success_list.sort()
    assert np.array_equal(expected_results, success_list)

# Several known good inputs in a row
@cocotb.test()
async def needles_only(dut):
    n, num_nlin, num_nlin_idx = dut.SHIFTREG_WIDTH.value, dut.NUM_NLIN.value, dut.NUM_NLIN_IDX.value
    success_list = []
    cocotb.start_soon(Clock(dut.clk, 1, units="ns").start())
    cocotb.start_soon(get_outputs(dut, success_list))
    
    # Assign DUT inputs
    dut.start.value = 0
    dut.setting_in.value = 0
    dut.setting_rd_en.value = 0
    await RisingEdge(dut.clk)

    haystack_size = 100
    haystack = [get_known_good(n, num_nlin, num_nlin_idx) for _ in range(haystack_size)]
    num_written = 0
    while num_written < haystack_size:
        while dut.idle.value == 0:
            await RisingEdge(dut.clk)
            
        dut.setting_in.value = haystack[num_written]
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        await RisingEdge(dut.clk)
        num_written += 1

    await FallingEdge(dut.running)
    
    # Now check the results
    haystack.sort()
    success_list.sort()
    print(len(success_list), len(haystack))
    for i in range(len(success_list)):
        if success_list[i] != haystack[i]:
            print(i, success_list[i], haystack[i])
    assert np.array_equal(haystack, success_list)
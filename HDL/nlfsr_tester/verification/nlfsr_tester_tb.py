import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, First
import random
import galois
import math
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

# Basic test, useful for small tests and waveform debugging
@cocotb.test()
async def basic_test(dut):
    cocotb.start_soon(Clock(dut.clk, 1, units="ns").start())

    n, num_nlin, num_nlin_idx = dut.SHIFTREG_WIDTH.value, dut.NUM_NLIN.value, dut.NUM_NLIN_IDX.value
    # Assign DUT inputs
    dut.start.value = 0
    dut.setting_rd_en.value = 0
    dut.setting_in.value = 0
    await ClockCycles(dut.clk, 5)

    # Test a known good (n)lfsr
    known_good = get_known_good(n, num_nlin, num_nlin_idx)
    dut.setting_in.value = known_good
    dut.start.value = 1
    await RisingEdge(dut.clk)
    dut.start.value = 0
    await RisingEdge(dut.clk)
    assert (dut.idle.value == 0)
    await First(RisingEdge(dut.success), RisingEdge(dut.idle))
    assert (dut.success.value == 1)
    dut.setting_rd_en.value = 1
    await RisingEdge(dut.clk)
    dut.setting_rd_en.value = 0
    await ClockCycles(dut.clk, 5)


# Test with several random inputs, and one known good input
@cocotb.test()
async def needle_in_haystack(dut):
    cocotb.start_soon(Clock(dut.clk, 1, units="ns").start())
    n, num_nlin, num_nlin_idx = dut.SHIFTREG_WIDTH.value, dut.NUM_NLIN.value, dut.NUM_NLIN_IDX.value
    # Assign DUT inputs
    dut.start.value = 0
    dut.setting_rd_en.value = 0
    dut.setting_in.value = 0
    await RisingEdge(dut.clk)

    haystack_size = 50
    needle_idx = random.randint(0, haystack_size-1)
    for i in range(haystack_size):
        setting_in = get_known_good(n, num_nlin, num_nlin_idx) if i == needle_idx else get_random(n, num_nlin, num_nlin_idx)
        dut.setting_in.value = setting_in
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        await RisingEdge(dut.clk)
        assert (dut.idle.value == 0)
        await First(RisingEdge(dut.success), RisingEdge(dut.idle))
        expected_result = is_max_period(setting_in, n, num_nlin, num_nlin_idx)
        assert (dut.success.value == expected_result)
        assert (dut.setting_out.value.integer == setting_in)
        if dut.success.value == 1:
            dut.setting_rd_en.value = 1
            await RisingEdge(dut.clk)
            dut.setting_rd_en.value = 0

    await ClockCycles(dut.clk, 5)

# Tests with just known good inputs
@cocotb.test()
async def needles_only(dut):
    cocotb.start_soon(Clock(dut.clk, 1, units="ns").start())
    n, num_nlin, num_nlin_idx = dut.SHIFTREG_WIDTH.value, dut.NUM_NLIN.value, dut.NUM_NLIN_IDX.value

    # Assign DUT inputs
    dut.start.value = 0
    dut.setting_rd_en.value = 0
    dut.setting_in.value = 0
    await RisingEdge(dut.clk)

    haystack_size = 20 
    for i in range(haystack_size):
        setting_in = get_known_good(n, num_nlin, num_nlin_idx) # There's only needles in this "haystack"
        dut.setting_in.value = setting_in
        dut.start.value = 1
        await RisingEdge(dut.clk)
        dut.start.value = 0
        await RisingEdge(dut.clk)
        assert (dut.idle.value == 0)
        await First(RisingEdge(dut.success), RisingEdge(dut.idle))
        assert (dut.success.value == 1)
        assert (dut.setting_out.value.integer == setting_in)
        if dut.success.value == 1:
            dut.setting_rd_en.value = 1
            await RisingEdge(dut.clk)
            dut.setting_rd_en.value = 0

    await ClockCycles(dut.clk, 5)

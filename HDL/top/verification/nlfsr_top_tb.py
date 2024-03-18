import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from cocotbext.uart import UartSource, UartSink 
import random
import galois
import math
import sys
sys.path.append('../../../../software/')
import nlfsr_utils

CMD_RESET = 1
CMD_READ_SETTING = 2
CMD_READ_CYCLE_COUNT = 3
CMD_READ_NUM_FOUND = 4
CMD_READ_STATUS = 5
CMD_READ_NUM_STARTED = 6

STATUS_IN_PROG_EMPTY = 0b1
STATUS_IN_EMPTY = 0b10
STATUS_RUNNING = 0b100
STATUS_OUT_EMPTY = 0b1000
STATUS_MASK = 0b1111

async def write_uart_cmd(uart_source, cmd_code, uart_data_len):
    CMD_FLAG = 1 << (uart_data_len*8 - 1)
    cmd = CMD_FLAG | cmd_code
    cmd_bytes = cmd.to_bytes(uart_data_len, byteorder='big')
    await uart_source.write(cmd_bytes)


async def read_uart_blocking(uart_sink, uart_data_len, clk_signal, timeout_cycles):
    while uart_sink.count() < uart_data_len:
        await RisingEdge(clk_signal)
        timeout_cycles -= 1
        if timeout_cycles == 0:
            assert False, "Timeout while waiting for UART data"
    data = await uart_sink.read(uart_data_len)
    return int.from_bytes(data, byteorder='big')

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
        # pick a random index
        idx = 0#random.randint(0, N-2)
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


async def reset_dut(reset_signal, clk_signal):
    reset_signal.value = 1
    await ClockCycles(clk_signal, 3)
    reset_signal.value = 0
    await ClockCycles(clk_signal, 5)


# Basic test, useful for small tests and waveform debugging
@cocotb.test()
async def basic_test(dut):
    freq_slow = 200e6
    freq_fast = 400e6
    cocotb.start_soon(Clock(dut.clk_slow, 1e9/freq_slow, units="ns").start())
    cocotb.start_soon(Clock(dut.clk_fast, 1e9/freq_fast, units="ns").start())

    # We want a low number of clock cycles per bit used by the uart module for faster simulation
    baud_rate = freq_slow / dut.UART_CPB.value
    uart_source = UartSource(dut.uart_rx_in, baud=baud_rate, bits=8)
    uart_sink = UartSink(dut.uart_tx_out, baud=baud_rate, bits=8)

    n, num_nlin, num_nlin_idx = dut.SHIFTREG_WIDTH.value, dut.NUM_NLIN.value, dut.NUM_NLIN_IDX.value    
    setting_width = (n - 1 + (num_nlin * num_nlin_idx) * math.ceil(math.log(n-1, 2)))
    uart_data_len = (setting_width+8)//8

    uart_timeout = dut.UART_CPB.value * 9 * uart_data_len *5

    await reset_dut(dut.reset, dut.clk_slow)

    cand = get_known_good(n, num_nlin, num_nlin_idx)

    # First write a valid candidate through uart
    await uart_source.write(cand.to_bytes(uart_data_len, byteorder='big'))
    # Now poll the DUT for it's status
    while True:
        # Write 
        await write_uart_cmd(uart_source, CMD_READ_STATUS, uart_data_len)
        status = await read_uart_blocking(uart_sink, uart_data_len, dut.clk_slow, uart_timeout)
        done = (status & STATUS_IN_EMPTY) and (status & STATUS_IN_PROG_EMPTY) and not (status & STATUS_RUNNING)
        if done: # Fifo in is empty and we are not running
            assert (status & STATUS_OUT_EMPTY) == 0, "Fifo out is empty, but we sent in a valid candidate"
            break
    # Now read out the candidate
    await write_uart_cmd(uart_source, CMD_READ_SETTING, uart_data_len)
    cand_out = await read_uart_blocking(uart_sink, uart_data_len, dut.clk_slow, uart_timeout)
    assert cand_out == cand, "Candidate out does not match candidate in"


@cocotb.test()
async def needle_in_haystack(dut):
    freq_slow = 200e6
    freq_fast = 250e6
    cocotb.start_soon(Clock(dut.clk_slow, 1e9/freq_slow, units="ns").start())
    cocotb.start_soon(Clock(dut.clk_fast, 1e9/freq_fast, units="ns").start())

    # We want a low number of clock cycles per bit used by the uart module for faster simulation
    baud_rate = freq_slow / dut.UART_CPB.value
    uart_source = UartSource(dut.uart_rx_in, baud=baud_rate, bits=8)
    uart_sink = UartSink(dut.uart_tx_out, baud=baud_rate, bits=8)

    n, num_nlin, num_nlin_idx = dut.SHIFTREG_WIDTH.value, dut.NUM_NLIN.value, dut.NUM_NLIN_IDX.value    
    setting_width = (n - 1 + (num_nlin * num_nlin_idx) * math.ceil(math.log(n-1, 2)))
    uart_data_len = (setting_width+8)//8
    uart_timeout = 10000

    await reset_dut(dut.reset, dut.clk_slow)

    # Test that clock cycles are increasing
    await write_uart_cmd(uart_source, CMD_READ_CYCLE_COUNT, uart_data_len)
    cycle_count = await read_uart_blocking(uart_sink, uart_data_len, dut.clk_slow, uart_timeout)
    await write_uart_cmd(uart_source, CMD_READ_CYCLE_COUNT, uart_data_len)
    cycle_count2 = await read_uart_blocking(uart_sink, uart_data_len, dut.clk_slow, uart_timeout)
    assert cycle_count2 > cycle_count, "Cycle count did not increase"

    # Check that num_found and num_started are zero
    await write_uart_cmd(uart_source, CMD_READ_NUM_FOUND, uart_data_len)
    num_found = await read_uart_blocking(uart_sink, uart_data_len, dut.clk_slow, uart_timeout)
    await write_uart_cmd(uart_source, CMD_READ_NUM_STARTED, uart_data_len)
    num_started = await read_uart_blocking(uart_sink, uart_data_len, dut.clk_slow, uart_timeout)
    assert num_found == 0, "num_found is not zero"
    assert num_started == 0, "num_started is not zero"

    # Prepare candidates we want to get tested
    size_haystack = 20
    haystack = [get_random(n, num_nlin, num_nlin_idx) for _ in range(size_haystack)]
    needle_idx = random.randint(0, size_haystack-1)
    haystack[needle_idx] = get_known_good(n, num_nlin, num_nlin_idx)
    haystack = [get_known_good(n, num_nlin, num_nlin_idx) for _ in range(size_haystack)] # TODO TEMP

    success_list = []
    fifo_depth = 16
    fifo_prog_empty = 1
    num_written = 0
    while True:
        await write_uart_cmd(uart_source, CMD_READ_STATUS, uart_data_len)
        status = await read_uart_blocking(uart_sink, uart_data_len, dut.clk_slow, uart_timeout)
        # Check if any successfull candidates have been found, and read them out
        while not (status & STATUS_OUT_EMPTY):
            await write_uart_cmd(uart_source, CMD_READ_SETTING, uart_data_len)
            cand_out = await read_uart_blocking(uart_sink, uart_data_len, dut.clk_slow, uart_timeout)
            success_list.append(cand_out)
            # Read status again
            await write_uart_cmd(uart_source, CMD_READ_STATUS, uart_data_len)
            status = await read_uart_blocking(uart_sink, uart_data_len, dut.clk_slow, uart_timeout)
        # Check if we are done
        if not (status & STATUS_RUNNING) and (status & STATUS_OUT_EMPTY) and num_written == size_haystack:
            break
        # Check prog_empty flag, and write if it is raised
        if num_written < size_haystack and (status & STATUS_IN_PROG_EMPTY):
            for i in range(fifo_depth-fifo_prog_empty):
                if num_written >= size_haystack:
                    break
                await uart_source.write(haystack[num_written].to_bytes(uart_data_len, byteorder='big'))
                num_written += 1

        await RisingEdge(dut.clk_slow)

    expected_outputs = [cand for cand in haystack if is_max_period(cand, n, num_nlin, num_nlin_idx)]
    dut._log.info(f"Expected outputs: {expected_outputs}")
    dut._log.info(f"Found these candidates: {success_list}")

    assert len(expected_outputs) == len(success_list), "Not all expected outputs were found"
    for cand in expected_outputs:
        assert cand in success_list, "Expected output not found"
    
    # Check that num_found and num_started have the correct values
    await write_uart_cmd(uart_source, CMD_READ_NUM_FOUND, uart_data_len)
    num_found = await read_uart_blocking(uart_sink, uart_data_len, dut.clk_slow, uart_timeout)
    await write_uart_cmd(uart_source, CMD_READ_NUM_STARTED, uart_data_len)
    num_started = await read_uart_blocking(uart_sink, uart_data_len, dut.clk_slow, uart_timeout)
    assert num_found == len(expected_outputs), "num_found is not correct"
    assert num_started == size_haystack, "num_started is not correct"

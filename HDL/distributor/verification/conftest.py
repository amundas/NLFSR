import pytest

def pytest_addoption(parser):
    parser.addoption(
        "--width", action="store", default="10", help="Sets parameter WIDTH (defaults to 6)"
    )
    parser.addoption(
        "--num-nlin", action="store", default="1", help="Sets parameter NUM_NLIN (defaults to 1)"
    )
    parser.addoption(
        "--num-nlin-idx", action="store", default="2", help="Sets parameter NUM_NLIN_IDX (defaults to 2)"
    )
    parser.addoption(
        "--full", action="store_true", default=False, help="Run all tests"
    )
    parser.addoption(
        "--only", action="store", default=None, help="Run specified test only"
    )
    parser.addoption(
        "--sim", action="store", default="icarus", help="Select simulator (defaults to icarus)"
    )
    parser.addoption(
        "--waves", action="store_true", default=False, help="Generate .fst file for GTKWave"
    )
    parser.addoption(
        "--open-waves", action="store_true", default=False, help="Open GTKWave with the default .fst file"
    )
    parser.addoption(
        "--synth", action="store_true", default=False, help="Run synthesis with yosys"
    )
    parser.addoption(
        "--clean", action="store_true", default=False, help="Clean build directory before doing anything else"
    ) 
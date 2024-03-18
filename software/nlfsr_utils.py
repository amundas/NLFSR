
# Order a feedback function on the list format lexicographically
def order_lex(l: list) -> list:
    # first sort each sublist of the list
    lex_list = [sorted(x) for x in l]
    # Now sort the list based on length of the sublists. If equal length, sort based on the elements
    lex_list.sort(key=lambda x: (len(x), *x[::-1])) # Splat operator to unpack list
    return lex_list

def get_reciprocal(N: int, lst: list) -> list:
    lst_rec = []
    for i in range(len(lst)):
        lst_rec.append([])
        for j in range(len(lst[i])):
            e = lst[i][j]
            if (e != 0):
                e = N-e
            lst_rec[i].append(e)
    return order_lex(lst_rec)

# This function will return the lexicographically smallest NLFSR
def get_smallest_lex(N: int, lst: list) -> list:
    lst = order_lex(lst) 
    lst_rev = get_reciprocal(N, lst)
    # starting from the highest element, compare each element and return the one with the smallest max element
    for i in range(len(lst)):
        a, b = lst[len(lst)-1-i], lst_rev[len(lst)-1-i]
        if a[::-1] < b[::-1]:
            return lst
        elif a[::-1] > b[::-1]:
            return lst_rev
    # If we get here, the lists are equal
    return lst

# Convert from the list format to a LaTeX string
def format_list2tex(l: list) -> str:
    lex_list = order_lex(l)
    tex = ""
    # First get the linear terms
    for i in range(len(lex_list)):
        term = lex_list[i]
        if (len(term) == 1):
            if len(tex) > 0:
                tex += " + "
            tex += f"x_{{{term[0]}}}"

    # Now do the nonlinear terms.
    for i in range(len(lex_list)):
        term = lex_list[i]
        if (len(term) > 1):
            if len(tex) > 0:
                tex += " + "
            for j in range(len(term)):
                tex += f"x_{{{term[j]}}}"
                if j < len(term)-1:
                    tex += " \\cdot "
    return tex

# The "vector format" is useful for relatively fast software implementations of nlfsrs
def format_list2vec(lst_fmt: list) -> tuple[int, list]:
    lin = 0
    nlins = []
    for term in lst_fmt:
        if (len(term) == 1):
            lin ^= 1 << term[0]
        else:
            tmp = 0
            for b in term:
                tmp |= 1 << b
            nlins.append(tmp)
    return lin, nlins

# Convert from the fpga format to list format
def format_fpga2list(fpga_format: int, N: int, num_nlin: int, num_nlin_idx: int) -> list:
    lst_fmt = []
    fpga_format = (fpga_format << 1) | 1 # Add in "x_0" which is implicit in the FPGA format
    # The first N bits are linear coefficients
    for i in range(N):
        if (fpga_format >> i) & 1:
            lst_fmt.append([i])

    clog2 = (N-1).bit_length()
    clog2_mask = (1 << clog2) - 1
    
    for i in range(num_nlin):
        nl = []
        for j in range(num_nlin_idx):
            nlin = (fpga_format >> (N+clog2*(i*num_nlin_idx+j))) & clog2_mask
            nl.append(nlin + 1)
        lst_fmt.append(nl)
    lst_fmt = order_lex(lst_fmt)
    return lst_fmt

def format_vec2list(N: int, lin: int, nlins: list) -> list:
    list = []
    for i in range(N):
        if (lin >> i) & 1:
            list.append([i])
    for nl in nlins:
        tmp = []
        for i in range(N):
            if (nl >> i) & 1:
                tmp.append(i)
        list.append(tmp)
    return list

def format_list2fpga(N: int, lst_fmt: list) -> int:
    lin = 0
    nlins = []
    for term in lst_fmt:
        if (len(term) == 1):
            lin ^= 1 << term[0]
        if len(term) > 1:
            nlins.append(term)
    num_nlin_idxs = len(nlins[0])
    fpga_form = lin >> 1
    # Now add all the nonlinear terms
    clog2 = (N-1).bit_length() 
    for i in range(len(nlins)):
        for j in range(num_nlin_idxs):
            fpga_form |= (nlins[i][j]-1) << (N -1 + clog2 * (i*num_nlin_idxs+j))

    return fpga_form

# This function can be used to test the period of an NLFSR on the "vector" format
def test_period(N: int, lin: int, nlins: list) -> int:
    assert (N < 25), "This is rather slow for N > 24, use a compiled language instead"
    MASK = (1<<N)-1
    INIT = 1
    state = INIT
    p = 0
    for _ in range(MASK):
        fb = parity(state & lin)
        for nl in nlins:
            fb ^= (nl & state) == nl
        state |= fb << N
        state = state >> 1
        p +=1
        if (state == INIT):
            return p
    return 0

# Return the parity of an integer (up to 64 bits)
# Source: https://graphics.stanford.edu/~seander/bithacks.html
def parity(v: int) -> int:
    v ^= v >> 32
    v ^= v >> 16
    v ^= v >> 8
    v ^= v >> 4
    v &= 0xf
    return (0x6996 >> v) & 1

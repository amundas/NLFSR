import sys
import json
sys.path.append('../software/')
import nlfsr_utils # "nlfsr_utils.py" contains various useful functions for interacting with the dataset.

dataset = json.load(open("nlfsr_dataset.json"))

total_count = 0
for n in dataset:
    for form in dataset[n]:
        total_count += len(dataset[n][form]["functions"])

print(f"The dataset contains a total of {total_count} maximum period NLFSRs\n")

print("Here are some for n=32:")
n = "32"
form = "9,1"
functions =[]
for f in dataset[n][form]["functions"]:
    tex_string = nlfsr_utils.format_list2tex(f)
    print(tex_string)
print()

print("Testing the period of a few NLFSRs for n=16")
n = "16"
form = "3,0,1"
for f in dataset[n][form]["functions"]:
    lin, nlins = nlfsr_utils.format_list2vec(f)
    period = nlfsr_utils.test_period(int(n), lin, nlins)
    print(f"Period of {nlfsr_utils.format_list2tex(f)}: {period}")

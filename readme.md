# Maximum Period NLFSRs
This repository contains a dataset of maximum period nonlinear feedback shift registers (NLFSRs) as well as the source code of the FPGA accelerator that has been used to build it. 

## Dataset
The dataset is in JSON format and available at `dataset/nlfsr_dataset.json`. The dataset is indexed by the bit-width of the shift registers, and the form of the feedback function for the NLFSRs. For the form, we use a shorthand notation representing the number of terms in ascending order. For example "7,0,1" means 7 linear terms and one cubic term. For each combination of shift register width and form, the dataset contains a list of feedback functions that correspond to maximum period NLFSRs. The format we use to represent a feedback function is a list of terms. Each term is in turn represented as a list of the bit indexes that are multiplied together to form the term. For example `[[0], [1], [4], [3, 7]]` represents the feedback function *x_0 + x_1 + x_4 + x_3 \cdot x_7*.


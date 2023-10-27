#!/usr/bin/env python3
# RPC 291122
# Aim take family file and convert to passed
import pandas as pd
import os
import argparse
from pathlib import Path

# local test
# os.chdir("/Users/ryancardenas/Documents/exomiser-pipeline-nf/bin")
# input_dat = pd.read_csv("familytest.tsv", sep="\t")

#build arg parser here
parser = argparse.ArgumentParser(description='Create PED file from family file - Exomiser')
parser.add_argument('--input_family', nargs=1, required=True, help='Enter the path for the familt TSV file')
args = parser.parse_args()


#bamfile set
input = str(args.input_family[0])
input_dat = pd.read_csv(input, sep="\t", skipinitialspace = True)


def PED_function(run_ID, proband_ID, vcf_path, vcf_index, proband_sex, mother_ID, father_ID):
    # Extract
    output_name = (f"{proband_ID}.ped")
    print(f"creating {proband_ID}.ped")

    text_file = open(f"{output_name}", "w")

    # extract filename without extention or path
    file_base = Path(f"{vcf_path}").stem
    file_base = Path(f"{file_base}").stem

    if proband_sex == 'M' or proband_sex == 'Male':
        proband_sex2 = "1"
    elif proband_sex == 'F' or proband_sex == 'Female':
        proband_sex2 = "2"
    else:
        proband_sex2 = proband_sex

    template = f"""#FamilyID\tIndividualID\tPaternalID\tMaternalID\tSex\tPhenotype
{run_ID}\t{proband_ID}\t{father_ID}\t{mother_ID}\t{proband_sex2}\t2
{run_ID}\t{mother_ID}\t0\t0\t2\t1
{run_ID}\t{father_ID}\t0\t0\t1\t1
    """
    print(template)
    #save PED using bash
    n = text_file.write(template)
    text_file.close()
    print(f"finished {proband_ID}.ped")

for index, row in input_dat.iterrows():

    # define variables
    run_id1 = row["run_id"]
    proband_id1 = row["proband_id"]
    hpo1 = row["hpo"]
    mother_id1 = row["mother_id"]
    father_id1 = row["father_id"]
    vcf_path1 = row["vcf_path"]
    vcf_index_path1 = row["vcf_index_path"]
    proband_sex1 = row["proband_sex"]

    PED_function(run_id1,proband_id1, vcf_path1, vcf_index_path1, proband_sex1, mother_id1, father_id1)

    # create HPO file here.
    os.system(f"rm -fr {proband_id1}-HPO.txt" )
    os.system(f"echo '{hpo1}' > {proband_id1}-HPO.txt")

# Exomiser

## Pipeline documentation

Table of contents

- [Pipeline documentation](#pipeline-documentation)
  - [Pipeline description](#pipeline-description)
    - [Pipeline overview](#pipeline-overview)
    - [Input](#input)
      - [--\<name_of_main_input\>](#--name_of_main_input)
    - [Processes](#processes)
    - [Output](#output)
  - [Options](#options)
    - [General Options](#general-options)
    - [Resource Allocation](#resource-allocation)
  - [Usage](#usage)
    - [Running with Docker or Singularity](#running-with-docker-or-singularity)
    - [Running on CloudOS](#running-on-cloudos)
  - [Testing](#testing)
    - [Profiles](#profiles)
    - [Stress Testing](#stress-testing)

## Pipeline description

### Pipeline overview

- Name: exomiser-pipeline-nf
- Tools: exomiser
- Version: 12.1.0

It is a fully containerised nextflow pipeline that runs exomisers on either a single sample VCF file or a trio VCF file.

The Exomiser is a tool to perform genome-wide prioritisation of genomic variants including non-coding and regulatory variants using patient phenotypes as a means of differentiating candidate genes.

To perform an analysis, Exomiser requires the patient's genome/exome in VCF format and their phenotype encoded in [HPO terms](https://hpo.jax.org/app/). The exomiser is also capable of analysing trios/small family genomes.

The main input of the pipeline (`families_file`) is a TSV file and the main output of the pipeline is an HTML file containing pathogenicity score of the called variants.

### Input

#### --families_file

This is a TSV file that contains the following info tab separated

| run_id | proband_id | hpo | vcf_path | vcf_index_path | proband_sex | mother_id | father_id |
| :----: | :--------: | :-: | :------: | :------------: | :---------: | :-------: | :-------: |
|        |            |     |          |                |             |           |           |

The vcf_path column can contain the path to either a multiVCF(trio) or a single-sample VCF.
In the case of a single-sample VCF, the last 2 columns must contain `nan` as a value. An example can be found [here](https://lifebit-featured-datasets.s3.eu-west-1.amazonaws.com/pipelines/exomiser-nf/fam_file.tsv)

In the hpo column, multiple comma-separated HPO terms can be present.

### --application_properties

This is a file needed by exomiser to run. It contains information on where to find the reference data as well as the versioning of the reference genome. An example can be found [here](https://lifebit-featured-datasets.s3.eu-west-1.amazonaws.com/pipelines/exomiser-nf/application.properties)

### --auto_config_yml

This is a file needed by exomiser to run. It contains placeholders in the text that get filled in by the second process of the pipeline just before running exomiser. The one used for testing can be found [here](https://lifebit-featured-datasets.s3.eu-west-1.amazonaws.com/pipelines/exomiser-nf/auto_config.yml)

### --exomiser_data

This path refers to the reference data bundle needed by exomiser (~120 GB!). A copy of such files can be found [here](https://lifebit-featured-datasets.s3.eu-west-1.amazonaws.com/pipelines/exomiser-data-bundle/) . The reference dataset has been added as a parameter, allowing flexibility to pull the data from any resource (i.e. cloud, local storage, ftp, ...) and Nextflow will automatically take care of fetching the data without having to add anything to the pipeline itself.

There are other parameters that can be tweaked to personalize the behaviour of the pipeline. These are referenced in `nextflow.config`

### Processes

Here is the list of steps performed by this pipeline.

1. `process ped_hpo_creation` - this process produces the pedigree (PED) file needed for exomiser to run using a python script.
2. `process exomiser` - this process is where the autoconfig file for exomiser is generated and exomiser is run.

### Output

- a html and a json file containing a report on the analysis
- the autoconfig file, for reproducibility purpose
- a vcf file with the called variants that are identified as causative

### Usage

The pipeline can be run like:

```
nextflow run main.nf --families_file 's3://lifebit-featured-datasets/pipelines/exomiser-nf/fam_file.tsv' \
        --prioritisers 'hiPhivePrioritiser' \
        --exomiser_data 's3://lifebit-featured-datasets/pipelines/exomiser-data-bundle' \
        --application_properties 's3://lifebit-featured-datasets/pipelines/exomiser-nf/application.properties' \
        --auto_config_yml 's3://lifebit-featured-datasets/pipelines/exomiser-nf/auto_config.yml'
```

### Testing

To run the pipeline with `docker` (used by default), type the following commands:

To test the pipeline on a multi-VCF:

```
nextflow run main.nf -profile test_full_family
```

or

```
nextflow run main.nf -profile test_full_multi_hpo
```

To test the pipeline on a single-sample VCF:

```
nextflow run main.nf -profile test_full_single_vcf
```

Be careful when running this, as the pipeline requires the staging of 120 GB of reference data, required by exomiser, so only that takes a while!

### Running on CloudOS

### Profiles

|     profile name     |                              Run locally                               | Run on CloudOS |                                               description                                                |
| :------------------: | :--------------------------------------------------------------------: | :------------: | :------------------------------------------------------------------------------------------------------: |
|   test_full_family   | the data required is so big, it was tested on a c5.4xlarge EC2 machine |   Successful   |             this test is designed to test the pipeline on a multi-VCF with trio information              |
| test_full_single_vcf | the data required is so big, it was tested on a c5.4xlarge EC2 machine |   Successful   |                    this test is designed to test the pipeline on a single-sample-VCF                     |
| test_full_multi_hpo  | the data required is so big, it was tested on a c5.4xlarge EC2 machine |   Successful   | this test is designed to test the pipeline on a multi-VCF with trio information using multiple HPO terms |

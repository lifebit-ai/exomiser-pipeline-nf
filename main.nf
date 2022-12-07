#!/usr/bin/env nextflow
import groovy.json.*

/*
========================================================================================
                         lifebit-ai/exomiser-nf
========================================================================================
 #### Homepage / Documentation
 https://github.com/lifebit-ai/exomiser-nf
----------------------------------------------------------------------------------------
*/
c_teal   = "\033[0;36m";
c_reset  = "\033[0m";
c_white  = "\033[0;37m";
c_yellow = "\033[0;33m";
c_purple = "\033[0;35m";

// Header log info
log.info "-${c_purple}\nPARAMETERS SUMMARY${c_reset}-"
log.info "-${c_teal}config:${c_reset}- ${params.config}"
log.info "-${c_teal}filename_design_file:${c_reset}- ${params.families_file}"
if(params.hpo_file) log.info "-${c_teal}filename_hpo:${c_reset}- ${params.filename_hpo}"
if(params.ped_file) log.info "-${c_teal}filename_ped:${c_reset}- ${params.ped_file}"
log.info "-${c_teal}analysis_mode:${c_reset}- ${params.analysis_mode}"
log.info "-${c_teal}exomiser_data:${c_reset}- ${params.exomiser_data}"
log.info "-${c_teal}exomiser_phenotype_data:${c_reset}- ${params.exomiser_phenotype_data}"
log.info "-${c_teal}phenix_data:${c_reset}- ${params.phenix_data}"
log.info "-${c_teal}pathogenicity_sources:${c_reset}- ${params.pathogenicity_sources}"
log.info "-${c_teal}prioritisers:${c_reset}- ${params.prioritisers}"
log.info "-${c_teal}keep_non_pathogenic:${c_reset}- ${params.keep_non_pathogenic}"
log.info "-${c_teal}min_priority_score:${c_reset}- ${params.min_priority_score}"
log.info "-${c_teal}application_properties:${c_reset}- ${params.application_properties}"
log.info "-${c_teal}auto_config_yml:${c_reset}- ${params.auto_config_yml}"
log.info "-${c_teal}exomiser_data_directory:${c_reset}- ${params.exomiser_data_directory}"
log.info "-${c_teal}exomiser_container_tag:${c_reset}- ${params.exomiser_container_tag}"
log.info "-${c_teal}debug_script:${c_reset}- ${params.debug_script}"
log.info "-${c_teal}echo:${c_reset}- ${params.echo}"
if(params.pathogenicity_sources.contains('CADD')) log.info "-${c_teal}cadd_snvs:${c_reset}- ${params.cadd_snvs}"
if(!params.pathogenicity_sources.contains('CADD')) log.warn("[Lifebit Team] Input tuple does not match input set cardinality declared by process `exomiser`\nKnown warning, does not affect correct execution of the pipeline.")
log.info ""

// /*--------------------------------------------------
//   Check input parameters
// ---------------------------------------------------*/

if(params.families_file) {
   Channel
      .fromPath( "${params.families_file}")
      .ifEmpty { exit 1, "Family file: ${params.families_file} not found"}
      .set {ch_vcf}
} else {
  exit 1, "please specify Family file with --family_file parameter"
}



Channel
    .fromPath(params.families_file)
    .ifEmpty { exit 1, "Cannot find input file : ${params.families_file}" }
    .splitCsv(header:true, sep:'\t', strip: true)
    .map {row -> [ row.run_id, row.proband_id, row.hpo, file(row.vcf_path), file(row.vcf_index_path), row.proband_sex, row.mother_id, row.father_id ] }
    .set {ch_input}

// Conditional creation of channels, custom if provided else default from bin/
projectDir = workflow.projectDir
ch_application_properties = params.application_properties ? Channel.value(file(params.application_properties)) : Channel.fromPath("${projectDir}/bin/application.properties")
ch_auto_config_yml = params.auto_config_yml ? Channel.value(file(params.auto_config_yml)) : Channel.fromPath("${projectDir}/bin/auto_config.yml")

// Stage scripts from bin
ch_add_exomiser_fields_script = Channel.value(file("${projectDir}/bin/add_exomiser_fields_to_genotiers.js"))
ch_get_hpo_terms_script = Channel.value(file("${projectDir}/bin/get_hpo_terms_from_barcode.js"))

// set exomiser specific flags
pathogenicitySourcesList= definePathogenicitySources()
prioritisersList = definePrioritisers()
analysisModesList = defineAnalysisModes()

selected_pathogenicity_sources = params.pathogenicity_sources.split(',').collect{it.trim()}
if (!checkParameterList(selected_pathogenicity_sources, pathogenicitySourcesList)) exit 1, "Unknown source(s) of pathogenicity, the available options are:\n$pathogenicitySourcesList"

selected_prioritisers = params.prioritisers.split(',').collect{it.trim()}
if (!checkParameterList(selected_prioritisers, prioritisersList)) exit 1, "Unknown prioritiser, the available options are:\n$prioritisersList"
println(selected_prioritisers)

selected_analysis_mode = params.analysis_mode.split(',').collect{it.trim()}
if (!checkParameterList(selected_analysis_mode, analysisModesList)) exit 1, "Unknown analysis mode, the available options are:\n$analysisModesList"

ch_exomiser_data = Channel.fromPath("${params.exomiser_data}")
ch_ped_parser_py = Channel.fromPath("${params.ped_parser_py}")
/*--------------------------------------------------
  Create PED and HPO file from design
---------------------------------------------------*/

//remove
//ch_vcf_inspect.dump(tag:'ch_vcf')
if (params.ped_file) ped_ch = Channel.value(file(params.ped_file))
if (params.hpo_file) hpo_ch = Channel.value(file(params.hpo_file))

if(!params.ped_file & !params.hpo_file){
  process ped_hpo_creation {
    container '151515151515/ped_parser_v2'
    publishDir "${params.outdir}/familyfile/", mode: 'copy'
    input:
    file family_file from ch_vcf
    file(ped_parser_py) from ch_ped_parser_py
    output:
    file "*-HPO.txt" into hpo_ch
    file "*.ped" into ped_ch
    script:
    """
    python3 $ped_parser_py --input_family $family_file
    """
  }
}

/*--------------------------------------------------
  Run containarised Exomiser
---------------------------------------------------*/

ch_exomiser_data = Channel.fromPath("${params.exomiser_data}")


process exomiser {
  tag "${vcf_path1}"
  publishDir "${params.outdir}/${proband_id1}", mode: 'copy'

  input:
  set run_id, proband_id1, hpo, file(vcf_path1), file(vcf_index_path1), proband_sex, mother_id, father_id from ch_input
  file "${proband_id1}-HPO.txt" from hpo_ch
  file("${proband_id1}.ped") from ped_ch
  //The following is expected when CADD is omitted,
  // WARN: Input tuple does not match input set cardinality declared by process `exomiser`
  // ch_all_exomiser_data contents can be 1 or 2 folders, (exomiser_data +/- cadd separately)
  // this is fine, as when there is no second dir, a fake input.1 is generated that will be unused
  file(application_properties) from ch_application_properties
  file(auto_config_yml) from ch_auto_config_yml
  file(exomiser_data) from ch_exomiser_data
  each prioritiser from selected_prioritisers

  output:
  set file("*.html"),file("*.vcf"), file("*.json") optional true
  file("*AR.variants.tsv") optional true
  file("*yml") optional true
  file("MultiQC/*.html") optional true
  script:
  final_step = "finished"
  if (!params.mock_exomiser)  {
    def exomiser_executable = "/exomiser/exomiser-cli-"+"${params.exomiser_version}"+".jar"
    def exomiser = "java -Xms2g -Xmx4g -jar "+"${exomiser_executable}"
    """
    echo "Contents in PED"
    cat ${proband_id1}.ped

    # link the staged/downloaded data to predefined path
    ln -s "\$PWD/$exomiser_data/" /data/exomiser-data-bundle
    cat ${proband_id1}.ped > input.ped

    # Workaround for symlinked files not found
    HPO_TERMS=`cat ${proband_id1}-HPO.txt`
    PED_FILE=`${proband_id1}.ped`



    # Modify auto_config.to pass the params
    cp ${auto_config_yml} new_auto_config.yml

    # Swap placeholders with user provided values
    sed -i "s/hpo_ids_placeholder/\$HPO_TERMS/g" new_auto_config.yml
    sed -i "s/analysis_mode_placeholder/${params.analysis_mode}/g" new_auto_config.yml
    sed -i  "s/vcf_placeholder/${vcf_path1}/g" new_auto_config.yml
    sed -i  "s/output_prefix_placeholder/sample-${vcf_path1.simpleName}/g" new_auto_config.yml
    sed -i  "s/prioritiser_placeholder/${prioritiser}/g" new_auto_config.yml
    sed -i  "s/min_priority_score_placeholder/${params.min_priority_score}/g" new_auto_config.yml
    sed -i  "s/keep_non_pathogenic_placeholder/${params.keep_non_pathogenic}/g" new_auto_config.yml
    sed -i  "s/pathogenicity_sources_placeholder/${params.pathogenicity_sources}/g" new_auto_config.yml
    sed -i  "s/ped_placeholder/\$PED_FILE/g" new_auto_config.yml
    sed -i  "s/proband_placeholder/${proband_id1}/g" new_auto_config.yml

    # Printing (ls, see files; cat, injected values validation)
    ${params.debug_script}
    cat new_auto_config.yml

    # Run Exomiser
    ${exomiser} \
    --analysis new_auto_config.yml \
    --spring.config.location=$application_properties \
    --exomiser.data-directory='.'

    # Create the slot for CloudOS html report preview
    mkdir MultiQC
    cp *.html MultiQC/multiqc_report.html
    sed -i  "s/Anonymous/${proband_id1}/" MultiQC/multiqc_report.html

    """
  }else{
    """
    wget -O ${proband_id1}.tsv ${params.mock_exomiser_output_https_url}
    """
  }
}

// Completion notification

workflow.onComplete {
    def anacondaDir = new File('/home/ubuntu/anaconda3')
    anacondaDir.deleteDir()
    def dlBinDir = new File('/home/ubuntu/.dl_binaries')
    dlBinDir.deleteDir()
}


// Functions for parameter validation, mode of inheritance and type of priority


/*--------------------------------------------------
  General functions
---------------------------------------------------*/

// Check parameter existence
def checkParameterExistence(it, list) {
    if (!list.contains(it)) {
        log.warn "Unknown parameter value: ${it}"
        return false
    }
    return true
}

// Compare each parameter with a list of parameters
def checkParameterList(list, realList) {
    return list.every{ checkParameterExistence(it, realList) }
}

/*--------------------------------------------------
  Definitions of accepted values for params
---------------------------------------------------*/


// Define list of priority types
// Omitting available: 'ExomeWalker', requires seed gene positions, targetted
def definePrioritisers() {
    return [
        'hiPhivePrioritiser',
        'phivePrioritiser',
        'phenixPrioritiser'
    ]
}

// Define list of pathogenicity sources
// Omitting available: 'REMM', not available yet from authors for hg38
// See: https://github.com/exomiser/Exomiser/issues/312
def definePathogenicitySources() {
    return [
        'POLYPHEN',
        'MUTATION_TASTER',
        'SIFT',
        'CADD'
    ]
}

def defineAnalysisModes() {
    return [
        'FULL',
        'PASS_ONLY',
    ]
}

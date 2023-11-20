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
if(params.families_file) log.info "-${c_teal}families_file:${c_reset}- ${params.families_file}"
log.info "-${c_teal}analysis_mode:${c_reset}- ${params.analysis_mode}"
log.info "-${c_teal}exomiser_data:${c_reset}- ${params.data_bundle}"
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
      .set {ch_families_file}
} else {
  exit 1, "please specify Family file with --families_file parameter"
}



Channel
    .fromPath(params.families_file)
    .ifEmpty { exit 1, "Cannot find input file : ${params.families_file}" }
    .splitCsv(header:true, sep:'\t', strip: true)
    .map {row -> [ row.proband_id, file(row.vcf_path), file(row.vcf_index_path)] }
    .into {ch_vcf_paths; ch_vcf_paths2}

// Conditional creation of channels, custom if provided else default from bin/
projectDir = workflow.projectDir
ch_application_properties = params.application_properties ? Channel.value(file(params.application_properties)) : Channel.fromPath("${projectDir}/bin/application.properties")
ch_auto_config_yml = params.auto_config_yml ? Channel.value(file(params.auto_config_yml)) : Channel.fromPath("${projectDir}/bin/auto_config.yml")


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
/*--------------------------------------------------
  Create PED and HPO file from design
---------------------------------------------------*/

//remove
//ch_vcf_inspect.dump(tag:'ch_vcf')
// if (params.ped_file) ped_ch = Channel.value(file(params.ped_file))
// if (params.hpo_file) hpo_ch = Channel.value(file(params.hpo_file))

// if(!params.ped_file & !params.hpo_file){
  process ped_hpo_creation {
    container 'quay.io/lifebitaiorg/ped_parser:1.6.6'
    publishDir "${params.outdir}/familyfile/", mode: 'copy'
    errorStrategy 'retry'
    maxErrors 5
    input:
    set proband_id1, file(vcf_path1), file(vcf_index_path1) from ch_vcf_paths
    file family_file from ch_families_file.collect()
    output:
    tuple val(proband_id1), file("${proband_id1}-HPO.txt"), file("${proband_id1}.ped"), file("${proband_id1}_ID.txt") into ch_to_join
    script:
    """
    ped_module.py --input_family ${family_file}
    #to change nan in 0s if there are any 
    sed -i 's/nan/0/g' ${proband_id1}.ped
    #to remove the "parent" line if it's a single sample
    sed -i "/0\t0\t0/d"  ${proband_id1}.ped
    """
  }
// }

/*--------------------------------------------------
  Run containarised Exomiser
---------------------------------------------------*/


ch_combined = ch_vcf_paths2.join(ch_to_join, by: 0).view()

/*--------------------------------------------------
  Run containarised Exomiser
---------------------------------------------------*/

if (!params.data_bundle && params.exomiser_profile_files){
    exomiser_data=params.exomiser_data_profile[params.exomiser_profile_files].data_bundle
    Channel.fromPath("${exomiser_data}")
            .set{ch_exomiser_data }
}else{
    Channel.fromPath("${params.data_bundle}")
          .set{ch_exomiser_data }
}




process exomiser {
  tag "${vcf_path1}"
  submitRateLimit = '1 / 5 m'
  publishDir "${params.outdir}/${proband_id1}", mode: 'copy'
  publishDir "${params.outdir}/", mode: 'copy', pattern: "MultiQC/multiqc_report.html"

  input:
  set val(proband_id1),file(vcf_path1),file(vcf_index1), file(hpo_file), file(ped_file),file(id_file) from ch_combined
  each file(application_properties) from ch_application_properties
  each file(auto_config_yml) from ch_auto_config_yml
  each file(exomiser_data) from ch_exomiser_data
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
    #ls -la
    #echo "Contents in PED"
    # link the staged/downloaded data to predefined path
    mkdir -p /data
    mkdir -p /data/exomiser-data-bundle
    ln -svf "\$PWD/$exomiser_data/" /data/exomiser-data-bundle
    #stat -L $vcf_path1
    #stat -L $vcf_path1 > out.txt
    #cat out.txt
    proband_id1=`cat ${id_file}`
    hpo_band1=`cat ${hpo_file}`
    #echo \$proband_id1
    # Modify auto_config.to pass the params
    cp ${auto_config_yml} new_auto_config.yml
    # Swap placeholders with user provided values
    sed -i "s/hpo_ids_placeholder/\$hpo_band1/g" new_auto_config.yml
    sed -i "s/analysis_mode_placeholder/${params.analysis_mode}/g" new_auto_config.yml
    sed -i  "s/vcf_placeholder/${vcf_path1}/g" new_auto_config.yml
    sed -i  "s/output_prefix_placeholder/sample-${vcf_path1.simpleName}/g" new_auto_config.yml
    sed -i  "s/prioritiser_placeholder/${prioritiser}/g" new_auto_config.yml
    sed -i  "s/min_priority_score_placeholder/${params.min_priority_score}/g" new_auto_config.yml
    sed -i  "s/keep_non_pathogenic_placeholder/${params.keep_non_pathogenic}/g" new_auto_config.yml
    sed -i  "s/pathogenicity_sources_placeholder/${params.pathogenicity_sources}/g" new_auto_config.yml
    sed -i  "s/ped_placeholder/${ped_file}/g" new_auto_config.yml
    sed -i  "s/proband_placeholder/\$proband_id1/g" new_auto_config.yml
    # Printing (ls, see files; cat, injected values validation)
    #${params.debug_script}
    #cat new_auto_config.yml
    # Run Exomiser
    ${exomiser} \
    --analysis new_auto_config.yml \
    --spring.config.location=$application_properties \
    --exomiser.data-directory='.'
    # Create the slot for CloudOS html report preview
    mkdir MultiQC
    cp *.html MultiQC/multiqc_report.html

    sed -i  "s/Anonymous/\$proband_id1/" MultiQC/multiqc_report.html

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

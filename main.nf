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

sample_name = params.sample_name
// Header log info
log.info "-${c_purple}\nPARAMETERS SUMMARY${c_reset}-"
log.info "-${c_teal}config:${c_reset}- ${params.config}"
log.info "-${c_teal}input:${c_reset}- ${params.input}"
log.info "-${c_teal}sample_name:${c_reset}- ${sample_name}"
log.info "-${c_teal}filename_hpo:${c_reset}- ${params.filename_hpo}"
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
log.info "-${c_teal}hpo terms from a file:${c_reset}- ${params.hpo_terms_file}"
log.info "-${c_teal}exomiser_container_tag:${c_reset}- ${params.exomiser_container_tag}"
log.info "-${c_teal}debug_script:${c_reset}- ${params.debug_script}"
log.info "-${c_teal}echo:${c_reset}- ${params.echo}"
if(params.pathogenicity_sources.contains('CADD')) log.info "-${c_teal}cadd_snvs:${c_reset}- ${params.cadd_snvs}"
if(!params.pathogenicity_sources.contains('CADD')) log.warn("[Lifebit Team] Input tuple does not match input set cardinality declared by process `exomiser`\nKnown warning, does not affect correct execution of the pipeline.")
log.info ""

// /*--------------------------------------------------
//   Check input parameters
// ---------------------------------------------------*/

if(params.input) {
   Channel
      .fromPath( "${params.input}" )
      .ifEmpty { exit 1, "VCF file: ${params.input} not found"}
      .into { ch_vcf ; ch_vcf_inspect; ch_vcf_for_geneyx }
} else {
  exit 1, "please specify VCF file with --input parameter"
}

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
 
// Prevent an error in AWSBatch (when running by awsbatch executor) 
// by which this file is taken as /home/ubuntu/hpo_terms_file.txt instead of its correct path.
hpo_terms_filename = "${projectDir}/${params.hpo_terms_file}"


Channel.fromPath("${params.hpo_terms_file}")
      .splitCsv(sep: ',', skip: 1)
      .unique()
      .map {it -> it.toString().replaceAll("\\[", "").replaceAll("\\]", "")}
      .map {it -> "'"+it.trim()+"'"}
      .reduce { a, b -> "$a,$b" }
      .into { ch_hpo_terms_file ; ch_hpo_terms_file_inspect; ch_hpo_terms }
ch_hpo_terms_file_inspect.dump(tag:'ch_hpo_terms (retrieve_hpo_terms: false)')

/*--------------------------------------------------
  Run containarised Exomiser
---------------------------------------------------*/

ch_exomiser_data = Channel.fromPath("${params.exomiser_data}")

ch_vcf_inspect.dump(tag:'ch_vcf')

process exomiser {
  tag "${vcf}-${prioritiser}"
  publishDir "${params.outdir}/${sample_name}", mode: 'copy'

  input:
  file(vcf) from ch_vcf
  //The following is expected when CADD is omitted,
  // WARN: Input tuple does not match input set cardinality declared by process `exomiser`
  // ch_all_exomiser_data contents can be 1 or 2 folders, (exomiser_data +/- cadd separately)
  // this is fine, as when there is no second dir, a fake input.1 is generated that will be unused
  file(application_properties) from ch_application_properties
  file(auto_config_yml) from ch_auto_config_yml
  file(exomiser_data) from ch_exomiser_data
  val(hpo_terms) from ch_hpo_terms
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
    # link the staged/downloaded data to predefined path
    mkdir -p /data
    mkdir -p /data/exomiser-data-bundle
    ln -s "\$PWD/$exomiser_data/" /data/exomiser-data-bundle

    ls -l
    # Workaround for symlinked files not found
    HPO_TERMS="${hpo_terms}"
    
    # error if no HPO term found
    if [[ "\${HPO_TERMS}" == "null" ]]; then
    	echo "WARNING: No HPO terms found. So this step of exomiser is skipped, No report will be generated."
	    echo "Please check HPO terms for the patient in the clinical-portal for whom this sample belongs - ${sample_name}"
      # solutions for AWS batch
      touch no_hpo_term.html
      touch no_hpo_term.vcf
      touch no_hpo_term.json
      touch no_hpo_term.yml
      mkdir -p MultiQC
      touch MultiQC/no_hpo_term.html

    else
      # Modify auto_config.to pass the params
      cp ${auto_config_yml} new_auto_config.yml

      # Swap placeholders with user provided values
      sed -i "s/hpo_ids_placeholder/\$HPO_TERMS/g" new_auto_config.yml
      sed -i "s/analysis_mode_placeholder/${params.analysis_mode}/g" new_auto_config.yml
      sed -i  "s/vcf_placeholder/${vcf}/" new_auto_config.yml
      sed -i  "s/output_prefix_placeholder/sample-${vcf.simpleName}/" new_auto_config.yml
      sed -i  "s/prioritiser_placeholder/${prioritiser}/" new_auto_config.yml
      sed -i  "s/min_priority_score_placeholder/${params.min_priority_score}/" new_auto_config.yml
      sed -i  "s/keep_non_pathogenic_placeholder/${params.keep_non_pathogenic}/" new_auto_config.yml
      sed -i  "s/pathogenicity_sources_placeholder/${params.pathogenicity_sources}/" new_auto_config.yml

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
      sed -i  "s/Anonymous/${sample_name}/" MultiQC/multiqc_report.html
    fi
    """
  }else{
    """
    wget -O ${sample_name}.tsv ${params.mock_exomiser_output_https_url}
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

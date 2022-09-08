#!/bin/bash

# Author - Sangram Keshari Sahu <sangram@lifebit.ai>
# Last modified - 16-Aug-2021

# exit if aws encounter a non-zero exit
#set -e

start_note="
About - A script for sending job request to Genexy-Lifebit AWS SQS.
-------------------------------------------------------------
Note - This script is using AWS-CLI to submit AWS-SQS jobs.
Make sure to have the correct set of AWS credentials in default,
or as AWS enviromental variables.
-------------------------------------------------------------
"

# default arguments
sample_file=""
output=""
annot_job_queue="https://sqs.ap-east-1.amazonaws.com/676396135330/geneyx-annotation-jobs.fifo"
annot_status_queue="https://sqs.ap-east-1.amazonaws.com/676396135330/geneyx-annotation-status.fifo"
processing_id="geneyx-run-`date -u +'%FT%T.000Z'`"
genome_build="hg19"
pipeline="Snv"
status_check_time_interval=2
status_check_time_limit=60
annot_log_file="log_$processing_id.json"
output_basename=""

# do not change
export AWS_DEFAULT_REGION=ap-east-1

help="
About: This script sends a AWS SQS job request for Genexy Annotation, and checks for the job Status.
    Few things to take care - Make sure the AWS credentials are avaiable in the bash enviromental variables.
Usage: ./$(basename $0) [OPTIONS]
Options:
  
  [Mendatory Arguments]
  sample_file                   S3 path of the input VCF file which need to be annotated
  output                        S3 path of a folder where output will be stored
  output_basename               basename of output file
                            
  [Optional Arguments]
  annot_job_queue               AWS SQS URL for Geneyx-annotation-jobs
                                (Default: $annot_job_queue)
  annot_status_queue            AWS SQS URL for Geneyx-annotation-status
                                (Default: $annot_status_queue)
  annot_log_file                A annotate log file to keep the output log of the annotation Job
                                (Default: log_{processing_id}.json )
  processing_id                 A uniqe ID which will be used to assigned to the job run
                                (Default: $processing_id)
  genome_build                  Genome build (Available options - hg18 and hg19 )
                                (Default: $genome_build)
  pipeline                      Pipeline name (Available options - Snv and Sv )
                                (Default: $pipeline)
  status_check_time_interval    In how much interval the status check should be performed. In minutes.
                                (Default: $status_check_time_interval)
  status_check_time_limit       Status check time limit. After this status check will be stoped. In minutes.
                                (Default: $status_check_time_limit)
  help                          This help menu
Example: ./$(basename $0) sample_file="s3://lifebit-geneyx-annotation/test/sample/ERR3239334.vcf.gz" output="s3://lifebit-geneyx-annotation/test/output/test-2"
"

# user defined arguments, over write the default ones
for ARGUMENT in "$@"
do
    KEY=$(echo $ARGUMENT | cut -f1 -d=)
    VALUE=$(echo $ARGUMENT | cut -f2 -d=)   
    case "$KEY" in
            annot_job_queue)                annot_job_queue=${VALUE} ;;
            annot_status_queue)             annot_status_queue=${VALUE} ;; 
            processing_id)                  processing_id=${VALUE} ;; 
            sample_file)                    sample_file=${VALUE} ;; 
            genome_build)                   genome_build=${VALUE} ;; 
            pipeline)                       pipeline=${VALUE} ;; 
            output)                         output=${VALUE} ;; 
            output_basename)                output_basename=${VALUE} ;; 
            annot_status_queue)             annot_status_queue=${VALUE} ;;
            status_check_time_interval)     status_check_time_interval=${VALUE} ;;
            status_check_time_limit)        status_check_time_limit=${VALUE} ;;
            annot_log_file)                 annot_log_file=${VALUE} ;;
            help) echo "$help" 
                exit 1 ;; 
            *) echo "Invalid argument is given. Please check again. For all available arguments - $(basename $0) help" 
                exit 1 ;;
    esac
done

# check for mandatory parameters
if [ -z "${sample_file}" ]; then
    echo 'Please mention sample_file="s3://path-to-vcf-file", which is mendatory in order to annotate'
    exit 1
fi

if [ -z "${output}" ]; then
    echo 'Please mention output="s3://path-to-a-folder", which is mendatory in order to keep the output'
    exit 1
fi

if [ -z "${output_basename}" ]; then
    echo 'Please mention output_basename'
    exit 1
fi

# check pre-equirements tools 
check_tool_status () {
    tool="$1"
    tool_check=$(which "${tool}") 
    tool_status=$(echo "$?")
    if [ ! "$tool_status" = 0 ]; then 
        printf "\033[0;31mCan not found the tool - '${tool}' which is required for $(basename $0)\033[0m\n" 
        exit 1 ; 
    fi
}
check_tool_status "aws"
check_tool_status "jq"

# internal variables
message_group_id='hkgi-annotation'
message_deduplication_id="dedup-$processing_id"
min=0 # a variable to count number of minutes elaped
attempt=0 # a variable to count number of attempts made
limit=10 # Number of messages to get from SQS
tmp_folder="tmp" # create temporary folder to keep sqs responce files
mkdir -p $tmp_folder
annot_status_file="$tmp_folder/status_out_$processing_id.json"
annot_submit_file="$tmp_folder/annotation_submit_$processing_id.json"

echo "$start_note"
echo "Trying to submit annotation Job"
aws sqs send-message \
    --queue-url $annot_job_queue \
    --message-body '{"processingId": "'$processing_id'", "sampleFile": "'$sample_file'", "genomeBuild": "'$genome_build'", "pipeline": "'$pipeline'", "output": "'$output'", "outputBasename": "'$output_basename'"}' \
    --message-group-id $message_group_id \
    --message-deduplication-id $message_deduplication_id \
    > $annot_submit_file
echo "Annotation job submited. Processing ID - '$processing_id'"

echo "User input output s3 path - $output/"
echo "User input output basename - $output_basename"

echo "Starting status check. Each attempt will be made every $status_check_time_interval minute until $status_check_time_limit minutes. You can change this, check '$(basename $0) help'"

while(($min < $status_check_time_limit)); do 
    sleep $(($status_check_time_interval*60))
    min=$(($min + $status_check_time_interval))
    attempt=$(($attempt + 1))
    echo "Attempt-$attempt:"
    
    # check if the s3 path contains the log file and try to download all the 3 files
    echo "Checking if run complete by getting the log file from s3 - "
    exists=$(aws s3 ls $output/$output_basename.log)
    if [ -z "$exists" ]; then
        echo "$output_basename.log not found in the $output/ yet"
    else
        aws s3 cp $output/$output_basename.log .
        aws s3 cp $output/$output_basename.dataSources.json .
        aws s3 cp $output/$output_basename.result.zip .
        #unzip the results file
        unzip -p $output_basename.result.zip > ${output_basename}_annot.tsv
        break
    fi
done


# echo "Starting status check. Each attempt will be made every $status_check_time_interval minute until $status_check_time_limit minutes. You can change this, check '$(basename $0) help'"

# while(($min < $status_check_time_limit)); do 
#     sleep $(($status_check_time_interval*60))
#     min=$(($min + $status_check_time_interval))
#     attempt=$(($attempt + 1))
#     echo "Attempt-$attempt:"
#     aws sqs receive-message \
#         --queue-url $annot_status_queue \
#         --attribute-names All \
#         --message-attribute-names All \
#         --max-number-of-messages $limit \
#         > $annot_status_file

#     for n in $(seq 0 $limit); do 
#         # check though the recived message json
#         jobs_body=$(echo '.Messages['"$n"'].Body')
#         job_id=$(cat $annot_status_file | jq -r $jobs_body | jq '.processingId' | sed "s/\"//g")
#         if [ "$job_id" = "$processing_id" ]; then
#             echo "Job ID - $processing_id found"
#             job_status=$(cat $annot_status_file | jq -r $jobs_body | jq '.status' | sed "s/\"//g")
#             echo "Job Status - $job_status"
#             echo $(cat $annot_status_file | jq -r $jobs_body) > $annot_log_file
#             echo "The complete job log can be found in - $annot_log_file"
#             if [[ ! "$job_status" = "SUCCESS" ]]; then
#                 error_message=$(cat $annot_status_file | jq -r $jobs_body | jq '.errorMessage' | sed "s/\"//g")
#                 echo "Error - $error_message"
#                 exit 1
#             fi
#             break
#         fi
#     done
#     if [ "$job_id" = "$processing_id" ]; then
#         break
#     fi
#     echo "No status found yet"
# done

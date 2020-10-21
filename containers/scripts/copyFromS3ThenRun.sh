#!/bin/bash
#
# &copy; 2017-2018 Regents of the University of California and the Broad Institute. All rights reserved.
#
echo "setting up sigterm trap"
trap "echo SIGINT Received! == $? received;exit" SIGINT 
trap "echo SIGTERM Received! == $? received;exit" SIGTERM 
trap "echo EXIT Recieved! == $? received;exit" EXIT 
trap "echo SIGQUIT Received! == $? received;exit" SIGQUIT 
trap "echo SIGKILL Received! == $? received;exit" SIGKILL
trap "echo SIGSTOP Received! == $? received;exit" SIGSTOP 
trap "echo SIGHUP Received! == $? received;exit" SIGHUP

############################   START getting all inputs ################################

# 
# GP_JOB_DOCKER_BIND_MOUNTS = env variable, colon delimited list
# ---  maybe later? GP_S3_RETURN_POINTS = env variable, colon delimited list - meta and working
# AWS_S3_PREFIX = env_var, s3:<bucketname><optional path>
# GP_JOB_METADATA_DIR = path, under AWS_S3_PREFIX to sync in to bootstrap
# GP_WORKING_DIR = working dir name, create in outer, mount to inner, and sync back
# GP_AWS_SYNC_SCRIPT_NAME = default = aws-sync-from-s3.sh
# GP_JOB_DOCKER_IMAGE = the container - if generic, possibly the same as the next one

# these 5 MUST be provided - no defaults - just strip spaces
GP_JOB_DOCKER_BIND_MOUNTS="$(echo -e "${GP_JOB_DOCKER_BIND_MOUNTS}" | tr -d '[:space:]')"
AWS_S3_PREFIX="$(echo -e "${AWS_S3_PREFIX}" | tr -d '[:space:]')"
GP_JOB_WORKING_DIR="$(echo -e "${GP_JOB_WORKING_DIR}" | tr -d '[:space:]')"
GP_JOB_DOCKER_IMAGE="$(echo -e "${GP_JOB_DOCKER_IMAGE}" | tr -d '[:space:]')"
GP_MODULE_DIR="$(echo -e "${GP_MODULE_DIR}" | tr -d '[:space:]')"
GP_USER_ID="$(echo -e "${GP_USER_ID}" | tr -d '[:space:]')"


# also expect
#    GP_MODULE_NAME
#    GP_MODULE_LSID
#    GP_MODULE_LSID_VERSION
#
# have save modules name as GP_MODULE_SPECIFIC_CONTAINER=$GP_MODULE_NAME_$GP_MODULE_LSID_VERSION
 
# these have defaults that can be overridden
: ${GP_JOB_METADATA_DIR=$GP_JOB_WORKING_DIR/.gp_metadata}
: ${GP_AWS_SYNC_SCRIPT_NAME="aws-sync-from-s3.sh"}
: ${STDOUT_FILENAME=$GP_JOB_METADATA_DIR/stdout.txt}
: ${STDERR_FILENAME=$GP_JOB_METADATA_DIR/stderr.txt}
: ${EXITCODE_FILENAME=$GP_JOB_METADATA_DIR/exit_code.txt}
: ${GP_JOB_WALLTIME_SEC="86400"}

: ${DEBUG_LEVEL=0}

# now strip any spaces that are present of either end
GP_JOB_METADATA_DIR="$(echo -e "${GP_JOB_METADATA_DIR}" | tr -d '[:space:]')"
GP_AWS_SYNC_SCRIPT_NAME="$(echo -e "${GP_AWS_SYNC_SCRIPT_NAME}" | tr -d '[:space:]')"
STDOUT_FILENAME="$(echo -e "${STDOUT_FILENAME}" | tr -d '[:space:]')"
STDERR_FILENAME="$(echo -e "${STDERR_FILENAME}" | tr -d '[:space:]')"
EXITCODE_FILENAME="$(echo -e "${EXITCODE_FILENAME}" | tr -d '[:space:]')"

#
# and a possibly different container id to use to save or reuse a cached container
# there is NO DEFAULT for this one
#
GP_MODULE_SPECIFIC_CONTAINER="$(echo -e "${GP_MODULE_SPECIFIC_CONTAINER}" | tr -d '[:space:]')"
if [ "xGP_MODULE_SPECIFIC_CONTAINER" = "x" ]; then
    # Variable is empty
    echo "== no MODULE_SPECIFIC_CONTAINER specified. No caching of the container will be done at the end of the run "
fi

if [ $DEBUG_LEVEL -gt 0  ]; then
###### print out the environment for later debugging	
# Loop over each line from the env command
# add the test to make it easier to search cloudwatch logs
while read -r line; do
  # Get the string before = (the var name)
  name="${line%=*}"
  eval value="\$$name"

  echo "ENV VAR name: ${name}, value: ${value}"
done <<EOF
$(env)
EOF
fi


############################   finished getting all inputs ################################
# this will NOT be at the same path as on the GP head node and the compute node, but it will be mounted to the
# inner container using the same path as on the head node
#
# Note we need to coordinate with Peter to ensure he doesn't do additional S3 commands in the inner container
# in the generated exec.sh script
#
# /local on the compute node should be mounted to /local in this (outer) container
#
GP_LOCAL_PREFIX=/local

mkdir -p  $GP_LOCAL_PREFIX$GP_JOB_WORKING_DIR
cd $GP_LOCAL_PREFIX$GP_JOB_WORKING_DIR

# sync the metadata dir - VITAL - this is where the aws-sync and the exec script will come from
echo "========== 1. synching gp_metadata_dir"
echo "aws s3 sync $AWS_S3_PREFIX$GP_JOB_METADATA_DIR $GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR"
aws s3 sync $AWS_S3_PREFIX$GP_JOB_METADATA_DIR $GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR 


# make sure scripts in metadata dir are executable
echo "========== 2. chmodding $GP_JOB_METADATA_DIR from $PWD"
chmod -R a+rwx $GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR


###################### TBD: load cached libraries for R modules ##########################
#
#   for this do a lookup given a GP_JOB_DOCKER_IMAGE name to a hard coded path on s3:/opt/gpbeta
# where things were cached in earlier runs
echo "========== 3. Load $MOD_LIB libraries"
# bootstapping until all modules have unique fully-populated containers
#  setup so the inner container loads R libraries, add a package load before the actual module call
# and do the necessary S3 sync based on an environment variable
if [ "x$MOD_LIBS_S3" = "x" ]; then
    # Variable is empty
    echo "========== no module libs to copy in "
else
    # copy in cached module libraries - this is only temporary
    aws s3 sync $AWS_S3_PREFIX$MOD_LIBS_S3 $MOD_LIBS --quiet
    ls -alrt $MOD_LIBS
fi
###################### END TBD: load cached libraries for R modules ##########################

. $GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR/$GP_AWS_SYNC_SCRIPT_NAME

synchDir.sh 30s $GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR $AWS_S3_PREFIX$GP_JOB_METADATA_DIR &

echo "========== S3 copies in complete, DEBUG inside 1st container ================="

. /usr/local/bin/runLocal.sh $@
exit_code=$?


echo "========== END RUNNING Module, copy back from S3  ================="

# send the generated files back
echo "========== 5. PERFORMING aws s3 sync $GP_LOCAL_PREFIX/$GP_JOB_WORKING_DIR $AWS_S3_PREFIX$GP_JOB_WORKING_DIR"
ls $GP_LOCAL_PREFIX/$GP_JOB_WORKING_DIR
aws s3 sync $GP_LOCAL_PREFIX/$GP_JOB_WORKING_DIR $AWS_S3_PREFIX$GP_JOB_WORKING_DIR 

# Synch metadata to ensure stderr.txt etc make it back
echo "========== 6. PERFORMING aws s3 sync  $GP_LOCAL_PREFIX/$GP_JOB_METADATA_DIR $AWS_S3_PREFIX$GP_JOB_METADATA_DIR"
aws s3 sync  $GP_LOCAL_PREFIX/$GP_JOB_METADATA_DIR $AWS_S3_PREFIX$GP_JOB_METADATA_DIR --quiet


# Delete files used as input that come from the user's home directory (but not stuff in tasklib or resources
# to minimize what an attacking malicious container could ever possibly see on the compute node
python /usr/local/bin/deletePrivateInputs.py $GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR/$GP_AWS_SYNC_SCRIPT_NAME $GP_USER_ID $GP_LOCAL_PREFIX

# Delete the JobResults and metadata dirs now that they have sync'd back
echo "=========7.  Removing Job and metadata directories"
rm -rf $GP_LOCAL_PREFIX/$GP_JOB_WORKING_DIR
rm -rf $GP_LOCAL_PREFIX/$GP_JOB_METADATA_DIR

exit $exit_code


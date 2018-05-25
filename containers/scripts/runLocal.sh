#!/bin/bash
#
# &copy; 2017-2018 Regents of the University of California and the Broad Institute. All rights reserved.
#

cd $GP_LOCAL_PREFIX$WORKING_DIR

echo "========== runLocal.sh inside 1st container, runLocal.sh - running module now  ================="

# pull first so that the stderr.txt is not polluted by the output of docker getting the image
docker pull $GP_DOCKER_CONTAINER

# start the container with an endless loop
# copy the desired dirs into it
# run the module command
# copy the contents back out to the local disk

#  --mount type=bind,src={bind_src},dst={bind_dst}

###########  generate mount str from the GP_MOUNT_POINT_ARRAY ########
MOUNT_STR="  "
for i in "${!GP_MOUNT_POINT_ARRAY[@]}"
do
    A_MOUNT=" --mount type=bind,src=$GP_LOCAL_PREFIX${GP_MOUNT_POINT_ARRAY[i]},dst=${GP_MOUNT_POINT_ARRAY[i]} "
    MOUNT_STR=$MOUNT_STR$A_MOUNT
done

CONTAINER_ID="`docker run -d   --mount type=bind,src=$GP_LOCAL_PREFIX$GP_METADATA_DIR,dst=$GP_METADATA_DIR $MOUNT_STR -t $GP_DOCKER_CONTAINER sleep 1d`"

echo CONTAINER_ID is $CONTAINER_ID

# the vi TASKLIB and MOD_LIBS are handled different so that it gets captured in the saved image

if [ ! "x$MOD_LIBS_S3" = "x" ]; then
    # Variable is empty
    echo "========== COPY IN module libs $MOD_LIBS "
	docker exec $CONTAINER_ID mkdir -p $MOD_LIBS
	docker cp $GP_LOCAL_PREFIX$MOD_LIBS/. $CONTAINER_ID:$MOD_LIBS
fi

# tasklib should NOT be in the mount points
#
# Try to log the case where a populated tasklib is already present inside the container
#   - see if we can fail if it already exists and is populated
#
echo GP_TASKLIB is $GP_TASKLIB
docker exec $CONTAINER_ID mkdir -p $GP_TASKLIB
docker cp $GP_LOCAL_PREFIX$TASKLIB $CONTAINER_ID:$GP_TASKLIB


#
# the actual exec - do we capture stderr here or move it inside of the exec.sh generated by GP
#
echo EXEC IS "docker exec -e GP_METADATA_DIR="$GP_METADATA_DIR" -t $CONTAINER_ID sh $GP_METADATA_DIR/exec.sh >$GP_LOCAL_PREFIX$STDOUT_FILENAME 2>$GP_LOCAL_PREFIX$STDERR_FILENAME "

docker exec -e GP_METADATA_DIR="$GP_METADATA_DIR" -t $CONTAINER_ID sh $GP_MODULE_EXEC >$GP_LOCAL_PREFIX$STDOUT_FILENAME 2>$GP_LOCAL_PREFIX$STDERR_FILENAME 

echo "======== runLocal: Module execution complete  ========"
docker stop $CONTAINER_ID
/usr/local/bin/saveContainerInECR.sh





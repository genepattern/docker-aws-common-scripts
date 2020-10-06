#!/bin/bash
#  
# &copy; 2017-2018 Regents of the University of California and the Broad Institute. All rights reserved.
#
: ${GP_MODULE_EXEC=$GP_JOB_METADATA_DIR/exec.sh}

cd $GP_LOCAL_PREFIX$WORKING_DIR

echo "========== runLocal.sh inside 1st container, runLocal.sh - running module now  ================="
# +++ PULL IS NOW IN THE  resolveContainerNameToCacheOrNot.sh SCRIPT +++++

. resolveContainerNameToCacheOrNot.sh 
DOCKER_PULL_EXIT=$?

echo " ### DOCKER PULL EXIT CODE $DOCKER_PULL_EXIT =="
echo " ### docker = $GP_JOB_DOCKER_IMAGE "
echo " ### ECR cache = $GP_MODULE_SPECIFIC_CONTAINER"
echo " ### USE THIS = $CONTAINER_TO_USE"

if [ $DOCKER_PULL_EXIT -eq 0  ]; then

# start the container with an endless loop
# copy the desired dirs into it
# run the module command
# copy the contents back out to the local disk

#  --mount type=bind,src={bind_src},dst={bind_dst}

###########  generate mount str from the GP_MOUNT_POINT_ARRAY ########
# this we create by splitting the mount points that are provided delimited with a colon
GP_MOUNT_POINT_ARRAY=(${GP_JOB_DOCKER_BIND_MOUNTS//:/ })

if [ $DEBUG_LEVEL -gt 0  ]; then
    echo "Mount points for the containers are:"
    for i in "${!GP_MOUNT_POINT_ARRAY[@]}"
    do
        echo "Mount    $i=>${GP_MOUNT_POINT_ARRAY[i]}"
    done
    echo "GP_JOB_METADATA_DIR = ==$GP_JOB_METADATA_DIR =="
    echo "GP_JOB_MODULE_DIR == $GP_JOB_MODULE_DIR =="
    echo "GP_WORKING_DIR = == $GP_WORKING_DIR =="


fi

MOUNT_STR="  "
for i in "${!GP_MOUNT_POINT_ARRAY[@]}"
do
    RW_FLAG="  "
    A_MOUNT=" --mount type=bind,src=$GP_LOCAL_PREFIX${GP_MOUNT_POINT_ARRAY[i]},dst=${GP_MOUNT_POINT_ARRAY[i]}"

    #
    # job dir, metadata dir have to be read/write.  TaskLib is writable for some modules so allow it too
    # everything else is readonly when GP_READONLY_BIND_MOUNTS is set to true
    #
    if [ ${GP_READONLY_BIND_MOUNTS,,} = "true"   ]; then
        THE_DIR="${GP_MOUNT_POINT_ARRAY[i]}"
        if [ ${THE_DIR} == "$GP_JOB_METADATA_DIR"  ]; then
            RW_FLAG="  "
        elif [ "$THE_DIR" == "$GP_JOB_MODULE_DIR"  ]; then
            RW_FLAG="  "
        elif [ "$THE_DIR" == "$GP_WORKING_DIR"  ]; then
            RW_FLAG="  "
        else 
            RW_FLAG=",readonly  "
        fi
    fi

    MOUNT_STR=$MOUNT_STR$A_MOUNT$RW_FLAG
    # make sure the mounts are rwx for whatever user is inside the container, not ideal but a workaround for now
    chmod -R a+rwx $GP_LOCAL_PREFIX${GP_MOUNT_POINT_ARRAY[i]}
    if [ $DEBUG_LEVEL -gt 0  ]; then
        echo FILE PERMISSIONS =========================================$GP_LOCAL_PREFIX${GP_MOUNT_POINT_ARRAY[i]}
        ls -alrt $GP_LOCAL_PREFIX${GP_MOUNT_POINT_ARRAY[i]}
    fi
done
WALLTIME_UNIT="s"
echo "CONTAINER RUN IS docker run -d --privileged=false  --cap-drop all --mount type=bind,src=$GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR,dst=$GP_JOB_METADATA_DIR $MOUNT_STR --entrypoint ""  -t $GP_JOB_DOCKER_IMAGE sleep ${GP_JOB_WALLTIME_SEC}${WALLTIME_UNIT} "

#
# test if this container uses 'sleep #s' or 'sleep #' without the 's' then launch with the approriate call
# the docker-r-seurat-scripts container used BuildRoot 2014.02 which fails on the sleep command if an s is present
# Note this will still fail if we get a non-unix container
#
docker run  --mount type=bind,src=$GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR,dst=$GP_JOB_METADATA_DIR $MOUNT_STR --entrypoint "" -t $GP_JOB_DOCKER_IMAGE  sleep 0s 

exit_code=$?

if [ $exit_code -ne 0  ];
then
   echo "sleep failed, retry without the 's'"
   CONTAINER_ID="`docker run -d  --mount type=bind,src=$GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR,dst=$GP_JOB_METADATA_DIR $MOUNT_STR -t $GP_JOB_DOCKER_IMAGE sleep ${GP_JOB_WALLTIME_SEC} `" 
else 
   CONTAINER_ID="`docker run -d  --mount type=bind,src=$GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR,dst=$GP_JOB_METADATA_DIR $MOUNT_STR -t $GP_JOB_DOCKER_IMAGE sleep ${GP_JOB_WALLTIME_SEC}s `" 
   exit_code=$?
fi

if [ $exit_code -ne 0  ];
then
    echo "a. FAILED to launch container sleep, exiting"
    exit $exit_code
fi

echo CONTAINER_ID is $CONTAINER_ID
if [ -z "$CONTAINER_ID" ];
then
   echo "b. Failed to launch container sleep, exiting"
   exit 999
fi

if docker exec -t $CONTAINER_ID id | grep root
then
    # container is running as root by default.
    # create a new user in it if we can and use that user for the next steps
    echo "===================  I am Groot! (I mean the module container $GP_JOB_DOCKER_IMAGE is running as user root by default) "
    # case insensitive compare of the variable
    if [ ${GP_CONTAINER_CANT_RUN_AS_ROOT,,} = "true"   ]
    then
        echo "Stopping execution because default user in container $GP_JOB_DOCKER_IMAGE is root.  Execution may be unsafe." >>$GP_LOCAL_PREFIX$STDERR_FILENAME 2>&1
        return
    fi
else

    echo "CONTAINER IS NOT RUNNING AS ROOT (Groot)!"
fi



# the GP_MODULE_DIR and MOD_LIBS are handled different so that it gets captured in the saved image

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
# docker exec $CONTAINER_ID ls -alrt  $GP_MODULE_DIR
docker cp $GP_LOCAL_PREFIX$GP_MODULE_DIR/ $CONTAINER_ID:$GP_MODULE_DIR
# docker exec $CONTAINER_ID ls -alrt  $GP_MODULE_DIR

#
# bootstrap package loading for old modules using shared containers
#
if [ -f "$GP_LOCAL_PREFIX$GP_MODULE_DIR/r.package.info" ]
then
        #echo "$GP_MODULE_DIR/r.package.info found.">$GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR/tedlog1.txt 
        # docker exec $CONTAINER_ID  ls /build/source/installPackages.R
	INSTALL_R_PRESENT = $?
        if [ $INSTALL_R_PRESENT != 0 ]
	then
		docker cp /usr/local/bin/installPackages.R  $CONTAINER_ID:/build/source/installPackages.R
		docker exec $CONTAINER_ID /usr/local/bin/installPackages.R $GP_MODULE_DIR/r.package.info
        fi
	docker exec $CONTAINER_ID Rscript /build/source/installPackages.R $GP_MODULE_DIR/r.package.info >$GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR/r.package.installs.out.txt 2>$GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR/r.package.installs.err.txt
fi

#
# the actual exec - do we capture stderr here or move it inside of the exec.sh generated by GP
#
echo EXEC IS "docker exec -e GP_JOB_METADATA_DIR="$GP_JOB_METADATA_DIR" -t $CONTAINER_ID sh $GP_JOB_METADATA_DIR/exec.sh >$GP_LOCAL_PREFIX$STDOUT_FILENAME 2>$GP_LOCAL_PREFIX$STDERR_FILENAME "
docker exec  -e GP_JOB_METADATA_DIR="$GP_JOB_METADATA_DIR" -t $CONTAINER_ID sh $GP_MODULE_EXEC >>$GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR/dockerout.log 2>>$GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR/dockererr.log 

exit_code=$?
echo "{ \"exit_code\": $exit_code }" >> $GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR/docker_exit_code.txt
echo "DOCKER EXEC EXIT CODE IS $exit_code"
if [ $exit_code -ne 0 ];then
    echo "Problem launching container" 
    echo "$(cat ${GP_LOCAL_PREFIX}${GP_JOB_METADATA_DIR}/dockererr.log)"
    exit $exit_code
fi


echo "======== runLocal: Module execution complete  ========"
docker stop $CONTAINER_ID
echo "Saving to ECR "
/usr/local/bin/saveContainerInECR.sh

# end block if DOCKER_PULL_EXIT eq 0
fi



# clean up exitted containers so that the docker space does not fill up with old
# containers we won't run again.  Maybe we should leave images as they might actually be reused
# but not for now
echo "=========== removing all exited containers =============="
docker ps -aq --no-trunc -f status=exited | xargs docker rm
# and remove downloaded images to keep them from piling up
docker image prune -a -f

return $DOCKER_PULL_EXIT
if [ $DOCKER_PULL_EXIT -ne 0 ];then
    return $DOCKER_PULL_EXIT
else 
    return $exit_code
fi


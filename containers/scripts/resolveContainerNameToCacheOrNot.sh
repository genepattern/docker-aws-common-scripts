

if [ "x$GP_MODULE_SPECIFIC_CONTAINER" = "x" ]; then
    # Variable is empty
    echo "== no MODULE_SPECIFIC_CONTAINER specified. Using default for test purposes "
    # GP_MODULE_SPECIFIC_CONTAINER=liefeld/test-cache_module_specific_container
 
    GP_MODULE_SPECIFIC_CONTAINER="`python /usr/local/bin/make_repo_name.py $GP_MODULE_LSID $GP_MODULE_NAME`"
    echo "== ECR TAG is  $GP_MODULE_SPECIFIC_CONTAINER =="
fi

CONTAINER_NAME=$GP_MODULE_SPECIFIC_CONTAINER
CONTAINER_VERSION=1
#PROFILE="--profile genepattern"
PROFILE=""

AWS_ACCOUNT="`python /usr/local/bin/get_aws_account.py`"
# echo " == found AWS account ID = $AWS_ACCOUNT "

aws --region us-east-1 ecr describe-images --repository-name $CONTAINER_NAME  > repo.json
if [ -s repo.json ];
then
   echo "Container already exists in ECR"
   CONTAINER_TO_USE=$CONTAINER_NAME
   LATEST_TAG="`python /usr/local/bin/getLastImageTag.py`"

   # login to the AWS ECR
   aws --region us-east-1 ecr get-login --no-include-email  > dockerlogin.sh
   sh dockerlogin.sh

   if [ $GP_JOB_CONTAINER_DONT_USE_CACHE ]; then
      echo "ECR Caching disabled"
      CONTAINER_TO_USE=$GP_JOB_DOCKER_IMAGE
      docker pull $GP_JOB_DOCKER_IMAGE >>$GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR/dockerout.log 2>>$GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR/dockererr.log
      exit_code=$?
      echo "{ \"exit_code\": $exit_code }" >> $GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR/docker_exit_code.txt
      echo "DOCKER PULL EXIT CODE IS $exit_code"
      if [ $exit_code -ne 0 ]; then
         echo "Problem pulling container. ${GP_LOCAL_PREFIX}${GP_JOB_METADATA_DIR}/dockererr.log"
         echo "$(cat ${GP_LOCAL_PREFIX}${GP_JOB_METADATA_DIR}/dockererr.log)"
         return $exit_code
      fi


   else 
       echo "========== USING ECR CACHED CONTAINER ================="
       # pull the ECR container
       docker pull $AWS_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/${CONTAINER_NAME}:$LATEST_TAG >>$GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR/dockerout.log 2>>$GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR/dockererr.log

       # tell the local docker that  this container is that container
       docker tag $AWS_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/${CONTAINER_NAME}:$LATEST_TAG $GP_JOB_DOCKER_IMAGE
       exit_code=$?
       echo "{ \"exit_code\": $exit_code }" >> $GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR/docker_exit_code.txt
       echo "DOCKER PULL EXIT CODE IS $exit_code"
       if [ $exit_code -ne 0 ]; then
          echo "Problem pulling container"
          echo "$(cat ${GP_LOCAL_PREFIX}${GP_JOB_METADATA_DIR}/dockererr.log)"
          return $exit_code
       fi
   fi
else
   echo " == Pulling $GP_JOB_DOCKER_IMAGE from dockerhub "
   CONTAINER_TO_USE=$GP_JOB_DOCKER_IMAGE
   docker pull -q $GP_JOB_DOCKER_IMAGE
fi

echo "{ \"container_used\": $CONTAINER_TO_USE }" >> $GP_LOCAL_PREFIX$GP_JOB_METADATA_DIR/docker_container_used.json




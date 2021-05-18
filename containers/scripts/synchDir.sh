#!/bin/bash
while true
do
  #echo "Sleep - sync cycle $1 $2 $3"
  sleep $1
  aws s3 sync $2 $3
done


#!/bin/bash
CONTAINER_ID_STATS=$2
OUTFILE_STATS=$3

echo "# CONTAINER ID: $2" >> $OUTFILE_STATS
echo "# Docker ps - running on this compute node " >> $OUTFILE_STATS
docker ps  >> $OUTFILE_STATS 2>&1
echo ""
echo "# stats (one time) for all running containers" >> $OUTFILE_STATS 2>&1
docker stats --no-stream  >> $OUTFILE_STATS 2>&1

echo ""
echo "# stats every 30s for this container"  >> $OUTFILE_STATS 2>&1
docker stats --no-stream $CONTAINER_ID_STATS  >> $OUTFILE_STATS 2>&1 

while true; do
  sleep $1
  docker stats --no-stream $CONTAINER_ID_STATS | tail -1   >> $OUTFILE_STATS 2>&1 
done


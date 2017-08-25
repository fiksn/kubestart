#!/bin/sh

REPO_NAME=${REPO_NAME:-"fiksn/kubestart"}
TAG=${TAG:-"canary"}

echo "If you want to push automatically export TAG=\"latest\" or something"

docker build -t $REPO_NAME:$TAG .
if [ "$TAG" != "canary" ]; then
  docker push $REPO_NAME:$TAG
fi

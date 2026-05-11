#!/usr/bin/env bash

app="asterinas"
docker_tag="0.17.2-20260407"

echo ">>> build ${app}"

[ ! -d ${app} ] && git clone https://github.com/rayylee/${app}

docker run -it --privileged --network=host \
    -v /dev:/dev -v $PWD/$app:/root/asterinas  \
    asterinas/asterinas:$docker_tag

# make ENABLE_KVM=1 run_kenel


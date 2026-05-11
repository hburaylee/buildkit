#!/usr/bin/env bash

app="asterinas"
docker_tag="0.17.2-20260407"

ws=1
mnt_dir="/workspace"

echo ">>> build ${app}"

if [ "$ws" != 1 ]; then
    mnt_dir="$PWD/$app"
    [ ! -d ${app} ] && git clone https://cnb.cool/rayylee/asterinas
fi

docker_id=$(docker ps -a 2>/dev/null | grep -m 1 "asterinas/asterinas" | awk '{print $1}')

if [ -z "$docker_id" ]; then
    docker run -it --privileged --network=host \
        -v /dev:/dev -v $mnt_dir:/root/asterinas  \
        asterinas/asterinas:$docker_tag
else
    is_exited="$(docker ps -a 2>/dev/null | grep -m 1 $docker_id | grep Exited)"
    if [ -n "$is_exited" ]; then
        docker start ${docker_id}
    fi
    docker exec -it ${docker_id} /bin/sh
fi

# make ENABLE_KVM=1 run_kenel

exit 0

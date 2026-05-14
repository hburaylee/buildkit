#!/usr/bin/env bash

app="asterinas"
docker_tag="0.17.2-20260407"

ws="${WS:-1}"
mnt_dir="/workspace"

echo ">>> build ${app}"

do_sync() {
    git remote add github https://github.com/asterinas/asterinas
    git fetch github
    git checkout main       # 或你使用的默认分支 (如 master)
    git merge github/main   # 合并GitHub 的更改
    git push origin main    # 推送到 GitLab
}

do_runkernel() {
    if [ -e /dev/kvm ]; then
        make ENABLE_KVM=1 SMP=4 run_kernel
    else
        make ENABLE_KVM=0 SMP=4 run_kernel
    fi
}

do_gdbserver() {
    if [ -e /dev/kvm ]; then
        make ENABLE_KVM=1 SMP=4 gdb_server
    else
        make ENABLE_KVM=0 SMP=4 gdb_server
    fi
}

if [ "$ws" != 1 ]; then
    mnt_dir="$PWD/$app"
    [ ! -d ${app} ] && git clone https://cnb.cool/rayylee/asterinas
fi

if [ -n "$1" ]; then
    if [ "$1" == "run_kernel" ]; then
        do_runkernel
    elif [ "$1" == "gdb_server" ]; then
        do_gdbserver
    elif [ "$1" == "sync" ]; then
        pushd ${mnt_dir}
            do_sync
        popd
    fi
    exit 0
fi

cp -f $0 ${mnt_dir}/

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
    docker exec -it ${docker_id} /bin/bash
fi


exit 0

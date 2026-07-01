#!/usr/bin/env bash

cd $(dirname $0)

app="asterinas"
docker_tag="0.18.0-20260701"

cur_dir="$(pwd)"
app_dir="$cur_dir/$app"

echo ">>> build ${app}"

do_sync() {
    git remote add github https://github.com/asterinas/asterinas
    git fetch github
    git checkout main       # 或你使用的默认分支 (如 master)
    # git merge github/main   # 合并GitHub 的更改
    # git push origin main    # 推送到 GitLab
}

do_iso() {
    make iso AUTO_INSTALL=false
}


do_runnixos() {
    if [ -e /dev/kvm ]; then
        make nixos && \
            make ENABLE_KVM=1 SMP=4 run_nixos
    else
        make nixos && \
            make ENABLE_KVM=0 SMP=4 run_nixos
    fi
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

if [ -e Cargo.toml ]; then
    app_dir="$(pwd)"
else
    [ ! -d ${app} ] && git clone https://github.com/rayylee/asterinas
fi

if [ -n "$1" ]; then
    if [ "$1" == "run_kernel" ]; then
        do_runkernel
    elif [ "$1" == "iso" ]; then
        do_iso
    elif [ "$1" == "run_nixos" ]; then
        do_runnixos
    elif [ "$1" == "gdb_server" ]; then
        do_gdbserver
    elif [ "$1" == "sync" ]; then
        do_sync
    fi
    exit 0
fi


############ Enter pod ############

if [ -e /root/ovmf ] && [ -e /.dockerenv ]; then
    echo "Already in the pod..."
    exit 0
fi

[ ! -e Cargo.toml ] && cp -f $0 ${app_dir}/

docker_id=$(docker ps -a 2>/dev/null | grep -m 1 raylee-aster | awk '{print $1}')

if [ -z "$docker_id" ]; then
    docker run --name raylee-aster -it --privileged --network=host \
        -v /dev:/dev -v $app_dir:/root/asterinas  \
        asterinas/asterinas:$docker_tag
else
    is_exited="$(docker ps -a 2>/dev/null | grep -m 1 $docker_id | grep Exited)"
    if [ -n "$is_exited" ]; then
        docker start ${docker_id}
    fi
    docker exec -it ${docker_id} /bin/bash
fi


exit 0

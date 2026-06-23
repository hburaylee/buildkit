#!/usr/bin/env bash

app="linux"
repo="https://cnb.cool/rayylee/linux"

app_dir="/workspace/$app"

echo ">>> build ${app}"


do_clone() {
    if [ ! -d ${app} ]; then
        git clone --depth 1 $repo
    fi
}

do_upstream() {
    do_clone
    pushd ${app_dir}
        git remote add upstream https://github.com/torvalds/linux
        git fetch --depth=1 upstream master
        git switch --detach upstream/master
    popd
}

if [ -n "$1" ]; then
    if [ "$1" == "upstream" ]; then
        do_upstream
    fi
    exit 0
fi

do_clone
pushd ${app_dir}
    [ ! -e .config ] && make defconfig
    make -j $(nproc) compile_commands.json
popd

exit 0

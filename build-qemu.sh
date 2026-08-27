#!/usr/bin/env bash

app="qemu"
repo="https://gitlab.com/qemu-project/qemu"

app_dir="$(pwd)/$app"

echo ">>> build ${app}"

do_clone() {
    if [ ! -d ${app} ]; then
        git clone --depth 1 $repo
    fi
}

do_build() {
    pushd ${app_dir} > /dev/null
        [ -d build ] && rm -rf build
        mkdir build
        pushd build > /dev/null
            ../configure
            make -j $(nproc)
        popd > /dev/null
    popd > /dev/null
}


if [ -n "$1" ]; then
    if [ "$1" == "download" ]; then
       do_clone
    fi
fi


do_clone
do_build

exit 0

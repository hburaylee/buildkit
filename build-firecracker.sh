#!/usr/bin/env bash

app="firecracker"
repo="https://github.com/firecracker-microvm/firecracker"

app_dir="$(pwd)/$app"

echo ">>> build ${app}"

do_clone() {
    if [ ! -d ${app} ]; then
        git clone --depth 1 $repo -b v1.16.1
    fi
}

do_clone
pushd ${app_dir}
    cargo build && file ./build/cargo_target/debug/firecracker
popd

exit 0

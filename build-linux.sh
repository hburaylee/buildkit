#!/usr/bin/env bash

app="linux"
repo="https://cnb.cool/rayylee/linux"

ws_dir="${WS:-1}"
app_dir="/workspace/$app"

echo ">>> build ${app}"

if [ -z "$WS" ]; then
    app_dir="$PWD/$app"
    if [ ! -d ${app} ]; then
        git clone $repo
    fi
else
    app_dir="${ws_dir}/$app"
fi

pushd ${app_dir}
    [ ! -e .config ] && make defconfig
    make -j $(nproc) compile_commands.json
popd

exit 0

#!/usr/bin/env bash

cd $(dirname $0)

app="fio"
repo="https://github.com/axboe/$app"
repo_tag="fio-3.42"

echo ">>> build ${app}"

if [ ! -d $app ]; then
    git clone $repo -b $repo_tag
fi

if [ -d $app ]; then
    pushd $app
    ./configure --build-static --esx
    make -j$(nproc)
    popd
fi

exit 0

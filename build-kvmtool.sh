#!/usr/bin/env bash

app="kvmtool"
repo="https://github.com/kvmtool/kvmtool"

use_ws="${WS:-1}"
mnt_dir="/workspace"

echo ">>> build ${app}"

do_sync() {
    git remote add github $repo
    git fetch github
    git checkout main       # 或你使用的默认分支 (如 master)
    git merge github/main   # 合并GitHub 的更改
    git push origin main    # 推送到 GitLab
}

if [ -z "$WS" ] && [ -d ${app} ]; then
    mnt_dir="$PWD/$app"
elif [ "$use_ws" != 1 ]; then
    mnt_dir="$PWD/$app"
    [ ! -d ${app} ] && git clone $repo
fi

if [ -n "$1" ]; then
    if [ "$1" == "sync" ]; then
        pushd ${mnt_dir}
            do_sync
        popd
    fi
    exit 0
fi

cp -f $0 ${mnt_dir}/

make -j $(nproc) lkvm-static

exit 0

#!/usr/bin/env bash

cd $(dirname $0)

app="kvmtool"
repo="https://github.com/hburaylee/$app"
upstream="https://github.com/kvmtool/$app"

mnt_dir="/workspace"

echo ">>> build ${app}"

do_sync() {
    git remote add github $upstream
    git fetch github
    git checkout main       # 或你使用的默认分支 (如 master)
    git merge github/main   # 合并GitHub 的更改
    git push origin main    # 推送到 GitLab
}

[ ! -d ${app} ] && git clone $repo

if [ -n "$1" ]; then
    if [ "$1" == "sync" ]; then
        do_sync
    fi
    exit 0
fi

pushd $app
    make -j $(nproc) lkvm-static
popd

exit 0

#!/usr/bin/env bash

# 最核心、最权威的仓库是 Linus Torvalds 的树（mainline）
#  https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
# 官方还维护着 stable 稳定版
#  https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git

app="linux"
repo="https://cnb.cool/rayylee/linux"
upstream_repo="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"

app_dir="$app"

echo ">>> build ${app}"


do_clone() {
    if [ ! -d ${app} ]; then
        git clone --depth 1 $repo
    fi
}

do_upstream() {
    do_clone
    pushd ${app_dir}
        git fetch --unshallow

        git remote add upstream ${upstream_repo}
        git fetch upstream master
        git checkout master
        git merge upstream/master
    popd
}

if [ -n "$1" ]; then
    if [ "$1" == "download" ]; then
        do_clone
    elif [ "$1" == "upstream" ]; then
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

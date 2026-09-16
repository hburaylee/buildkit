#!/usr/bin/env bash

# 最核心、最权威的仓库是 Linus Torvalds 的树（mainline）
#  https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
# 官方还维护着 stable 稳定版
#  https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git

# 清华大学 - 国内最常用的镜像之一，同步较及时
#   https://mirrors.tuna.tsinghua.edu.cn/git/linux.git
# 中国科学技术大学 - 支持断点续传（通过 git fetch）
#   https://mirrors.ustc.edu.cn/linux.git
# 华中科技大学 - 提供双栈线路
#   https://mirrors.hust.edu.cn/git/linux.git
# 南京大学 - 同样提供帮助文档
#   https://mirror.nju.edu.cn/git/linux.git
# 北京镜像站 - 由官方团队维护，针对北京地区优化
#   See: <https://kernel.googlesource.com/pub/scm/docs/kernel/website/+/refs/tags/v2026-09-02-01/content/news/2020-01-11-beijing-git-mirror.rst>
#   git://kernel.source.codeaurora.cn/pub/scm/.../linux.git

app="linux"
repo="https://cnb.cool/rayylee/linux"
upstream_repo="git://kernel.source.codeaurora.cn/pub/scm/.../linux.git"

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

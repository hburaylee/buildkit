#!/usr/bin/env bash

# 构建/运行 kernelet（设计文档在 ./kernelet，实现在 ./linux，均为本目录下的真实目录）
#
#   ./build-kernelet.sh              # 全量构建: 内核+endovisor.ko、镜像、host 运行时
#   ./build-kernelet.sh kernel       # 只构建内核 (bzImage + virt/endovisor/endovisor.ko)
#   ./build-kernelet.sh image        # 只构建 kernelet 镜像 (KLET_KERNEL=hello 可换 probe/mem/...)
#   ./build-kernelet.sh runtime      # 只构建 host 运行时 (holder 等)
#   ./build-kernelet.sh run [test]   # QEMU 运行测试, 默认 hello; test 可为 probe/mem-func/pie/...
#
# 串口日志在 kernelet/prototype/.build/serial-<test>.log

cd $(dirname $0)

app="kernelet"
# linux / kernelet 是本目录下的真实目录
[ -d linux ] || { echo "[Err] $(pwd) 下没有 linux 目录" >&2; exit 1; }
[ -d kernelet ] || { echo "[Err] $(pwd) 下没有 kernelet 目录" >&2; exit 1; }
linux_dir="$(pwd)/linux"
proto_dir="$(pwd)/kernelet/prototype"
fragment="$proto_dir/linux/config.fragment"
endovisor_ko="$linux_dir/virt/endovisor/endovisor.ko"
jobs=$(nproc)
klet_kernel="${KLET_KERNEL:-hello}"

echo ">>> build ${app}"

# 前置检查: linux 树必须是打过 carrier-hooks 补丁、含 endovisor 模块的树
[ -e "$linux_dir/include/linux/kernelet.h" ] || {
    echo "[Err] $linux_dir 没有 include/linux/kernelet.h, 请先打 0001-carrier-hooks.patch" >&2; exit 1; }
[ -d "$linux_dir/virt/endovisor" ] || {
    echo "[Err] $linux_dir 缺少 virt/endovisor/" >&2; exit 1; }

do_kernel() {
    pushd "$linux_dir"
        # tinyconfig + 原型 fragment + CONFIG_ENDOVISOR=m, 每次重新生成, 幂等
        make ARCH=x86_64 tinyconfig
        { cat "$fragment"; echo 'CONFIG_ENDOVISOR=m'; } > /tmp/klet.config
        ARCH=x86_64 ./scripts/kconfig/merge_config.sh -m -O . .config /tmp/klet.config
        make ARCH=x86_64 olddefconfig
        make ARCH=x86_64 -j$jobs bzImage modules
    popd
    ls -l "$linux_dir/arch/x86/boot/bzImage" "$endovisor_ko"
}

do_image() {
    # 首次需要网络下载 Rust 依赖 (make crates), 之后全部离线
    make -C "$proto_dir" image KLET_KERNEL=$klet_kernel
}

do_runtime() {
    make -C "$proto_dir" runtime
}

do_run() {
    local test="${1:-hello}"
    make -C "$proto_dir" "$test" LINUX_DIR="$linux_dir" ENDOVISOR_KO="$endovisor_ko"
}

case "$1" in
    kernel)  do_kernel ;;
    image)   do_image ;;
    runtime) do_runtime ;;
    run)     shift; do_run "$@" ;;
    "")      do_kernel; do_image; do_runtime ;;
    *)       echo "usage: $0 [kernel|image|runtime|run [test]]" >&2; exit 1 ;;
esac

exit 0

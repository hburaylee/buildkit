
#!/usr/bin/env bash
#
# build-xiuos.sh — 构建 XiZi (XiZi_AIoT_Micro) 内核 + ai_agent 应用
#
# 用法:
#   ./build-xiuos.sh                     # 默认构建 imx6q-sabrelite
#   ./build-xiuos.sh qemu-virt-a64       # 构建 aarch64 QEMU virt 板
#   ./build-xiuos.sh --run [board]       # 构建后启动 QEMU
#   ./build-xiuos.sh --clean-port [board]  # 强制清理 ai_agent 端口构建目录后重建
#   ./build-xiuos.sh --help
#
# 已固化的构建系统注意事项（详见 AI_AGENT_XIUOS_PORT_SUMMARY.md）:
#   1. ai_agent 端口 Makefile 没有按架构分目录——切换 imx6q-sabrelite ↔
#      qemu-virt-a64 时残留的 .o 会导致 "file in wrong format" 链接失败，
#      本脚本用 .last-board 标记自动检测并清理。
#   2. 该构建系统无头文件依赖追踪（make.obj 跨次累积），每次全量重建。
#   3. qemu-virt-a64 的交叉工具链在默认 PATH

set -euo pipefail

BUILDKIT="${BUILDKIT:-/workspace/buildkit}"
XIUOS_REPO_URL="https://cnb.cool/rayylee/xiuos"
XIUOS_REPO_BRANCH="multi-kernel"
XIUOS_REPO_DIR="${BUILDKIT}/xiuos"
XIUOS_ROOT="${XIUOS_REPO_DIR}/Ubiquitous/XiZi_AIoT_Micro"
PORT_BUILD="${BUILDKIT}/packages_ai_agent/platform/xiuos/build"
LAST_BOARD_MARKER="${PORT_BUILD}/.last-board"

RUN_AFTER_BUILD=0
FORCE_CLEAN_PORT=0
BOARD="imx6q-sabrelite"

usage() {
    sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --run|-r)       RUN_AFTER_BUILD=1 ;;
        --clean-port)   FORCE_CLEAN_PORT=1 ;;
        --help|-h)      usage ;;
        imx6q-sabrelite|qemu-virt-a64) BOARD="$1" ;;
        *)
            echo "错误: 未知参数 '$1'（支持板型: imx6q-sabrelite, qemu-virt-a64）" >&2
            exit 1
            ;;
    esac
    shift
done

# ── 下载代码：仓库不存在时自动克隆 ──
if [ ! -d "${XIUOS_REPO_DIR}/.git" ]; then
    if [ -e "${XIUOS_REPO_DIR}" ]; then
        echo "错误: ${XIUOS_REPO_DIR} 已存在但不是 git 仓库，请手动处理后再运行" >&2
        exit 1
    fi
    echo "==> 首次运行: 克隆 ${XIUOS_REPO_URL}（分支: ${XIUOS_REPO_BRANCH}）"
    mkdir -p "${BUILDKIT}"
    if ! git clone -b "${XIUOS_REPO_BRANCH}" "${XIUOS_REPO_URL}" "${XIUOS_REPO_DIR}"; then
        echo "错误: 克隆 xiuos 仓库失败，请确认已安装 git 且网络可达" >&2
        exit 1
    fi
else
    CURRENT_BRANCH="$(git -C "${XIUOS_REPO_DIR}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    if [ -n "${CURRENT_BRANCH}" ] && [ "${CURRENT_BRANCH}" != "${XIUOS_REPO_BRANCH}" ]; then
        echo "==> 注意: 仓库当前分支为 ${CURRENT_BRANCH}，将按已检出代码构建（预期分支: ${XIUOS_REPO_BRANCH}）"
    fi
fi

if [ ! -d "${XIUOS_ROOT}" ]; then
    echo "错误: 内核目录不存在: ${XIUOS_ROOT}（请确认仓库分支/目录结构）" >&2
    exit 1
fi

# ── 按板型准备工具链 ────────────────────────────────────────────────
case "$BOARD" in
    imx6q-sabrelite)
        TOOLCHAIN="arm-none-eabi-gcc"
        ;;
    qemu-virt-a64)
        TOOLCHAIN="aarch64-none-elf-gcc"
        ;;
esac

if ! command -v "${TOOLCHAIN}" >/dev/null 2>&1; then
    echo "错误: 找不到 ${TOOLCHAIN}（qemu-virt-a64 需要 aarch64-none-elf-gcc 工具链）" >&2
    exit 1
fi

# ── 跨架构切换检测：端口构建目录残留异架构 .o 会污染链接 ──────────
if [ -f "${LAST_BOARD_MARKER}" ]; then
    LAST_BOARD="$(cat "${LAST_BOARD_MARKER}")"
    if [ "${LAST_BOARD}" != "${BOARD}" ] || [ "${FORCE_CLEAN_PORT}" = 1 ]; then
        echo "==> 清理 ai_agent 端口构建目录（上次: ${LAST_BOARD}, 本次: ${BOARD}）"
        rm -rf "${PORT_BUILD}"
    fi
fi

echo "==> 板型: ${BOARD}  工具链: ${TOOLCHAIN}"
echo "==> 内核目录: ${XIUOS_ROOT}"

cd "${XIUOS_ROOT}"

echo "==> make clean"
make clean >/dev/null

echo "==> make BOARD=${BOARD} -j$(nproc)"
if ! make BOARD="${BOARD}" -j"$(nproc)" > /tmp/build-xiuos.log 2>&1; then
    echo "错误: 构建失败，日志见 /tmp/build-xiuos.log（末 30 行）：" >&2
    tail -30 /tmp/build-xiuos.log >&2
    exit 1
fi

ARTIFACT="${XIUOS_ROOT}/build/XiZi-${BOARD}.elf"
if [ ! -f "${ARTIFACT}" ]; then
    echo "错误: 构建成功但产物缺失: ${ARTIFACT}" >&2
    exit 1
fi
mkdir -p "${PORT_BUILD}"
echo "${BOARD}" > "${LAST_BOARD_MARKER}"

SIZE="$(du -h "${ARTIFACT}" | cut -f1)"
echo "==> 构建成功: ${ARTIFACT} (${SIZE})，日志: /tmp/build-xiuos.log"

# ── 可选：启动 QEMU ────────────────────────────────────────────────
if [ "${RUN_AFTER_BUILD}" = 1 ]; then
    echo "==> 启动 QEMU（Ctrl-A X 退出）"
    case "${BOARD}" in
        imx6q-sabrelite)
            exec qemu-system-arm -M sabrelite -m 1G -smp 4 -cpu cortex-a9 \
                -display none -serial null -serial stdio \
                -kernel "${ARTIFACT}"
            ;;
        qemu-virt-a64)
            exec qemu-system-aarch64 -M virt,gic-version=3 -cpu cortex-a53 \
                -m 1G -smp 4 -nographic \
                -kernel "${ARTIFACT}"
            ;;
    esac
fi

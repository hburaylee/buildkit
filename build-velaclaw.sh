#!/usr/bin/env bash
#
# build-velaclaw.sh — 下载 VelaClaw (packages/ai_agent) 仓库并静态编译
#
# 依据文档:
#   - packages/ai_agent/README.md  (Linux 独立编译章节)
#   - packages/ai_agent/CMakeLists.txt (AGENT_STANDALONE / AGENT_STATIC)
#
# 用法:
#   ./build-velaclaw.sh [命令]
#
# 命令:
#   (无参数)   下载源码 → 安装依赖 → 静态编译 (完整流程)
#   download   下载源码 (已存在则跳过, 保留本地修改)
#   build      静态编译 (源码不存在时自动下载)
#   clean      清理构建目录 build-linux/
#   help       显示帮助
#
# 环境变量 (均有默认值):
#   VELACLAW_DIR          源码目录     (默认: <脚本所在目录>/packages_ai_agent)
#   VELACLAW_REPO         仓库地址     (默认: https://cnb.cool/rayylee/packages_ai_agent)
#   VELACLAW_BRANCH       分支         (默认: multi-kernel, 静态编译支持所在分支)
#   VELACLAW_JOBS         编译并行数   (默认: nproc)
#   VELACLAW_BUILD_TYPE   构建类型     (默认: Release)
#   VELACLAW_CMAKE_EXTRA  附加 CMake 参数, 如 "-DAGENT_ENABLE_MCP=ON"
#
# 示例:
#   ./build-velaclaw.sh                                  # 下载 + 静态编译
#   ./build-velaclaw.sh build                            # 只编译
#   VELACLAW_CMAKE_EXTRA="-DAGENT_ENABLE_MCP=ON -DAGENT_ENABLE_MQTT=ON" \
#       ./build-velaclaw.sh build                        # 静态编译(开 MCP+MQTT)
#
# 产物: ${VELACLAW_DIR}/build-linux/ai_agent (完全静态链接, 可直接拷贝到其他
# x86-64 Linux 运行; strip 后约 2.1MB)
#

set -euo pipefail

# ── 全局配置 ─────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

app="packages_ai_agent"
VELACLAW_DIR="${VELACLAW_DIR:-${SCRIPT_DIR}/${app}}"
VELACLAW_REPO="${VELACLAW_REPO:-https://cnb.cool/rayylee/${app}}"
VELACLAW_BRANCH="${VELACLAW_BRANCH:-multi-kernel}"
VELACLAW_JOBS="${VELACLAW_JOBS:-$(nproc 2>/dev/null || echo 4)}"
VELACLAW_BUILD_TYPE="${VELACLAW_BUILD_TYPE:-Release}"
VELACLAW_CMAKE_EXTRA="${VELACLAW_CMAKE_EXTRA:-}"

BUILD_DIR="${VELACLAW_DIR}/build-linux"

# ── 工具函数 ─────────────────────────────────────────────────────────────────

info()  { printf '\033[1;32m[velaclaw]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[velaclaw]\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[1;31m[velaclaw 错误]\033[0m %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# 有 sudo 用 sudo, 没有则要求已具 root 权限
as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif have sudo; then
        sudo "$@"
    else
        die "需要 root 权限执行: $* (请配置 sudo 或以 root 运行)"
    fi
}

# ── 步骤 1: 下载源码 ─────────────────────────────────────────────────────────

do_download() {
    if [ -d "${VELACLAW_DIR}/.git" ]; then
        info "源码已存在: ${VELACLAW_DIR} (当前分支 $(git -C "${VELACLAW_DIR}" branch --show-current), 跳过下载)"
        return
    fi

    info "克隆 ${VELACLAW_REPO} (分支 ${VELACLAW_BRANCH}) → ${VELACLAW_DIR}"
    git clone --branch "${VELACLAW_BRANCH}" "${VELACLAW_REPO}" "${VELACLAW_DIR}"
    info "源码下载完成"
}

# ── 步骤 2: 依赖检查/安装 ────────────────────────────────────────────────────

do_deps() {
    local missing=()
    for pkg in git cmake pkg-config build-essential libmbedtls-dev; do
        dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        info "安装编译依赖: ${missing[*]}"
        as_root apt update
        as_root apt install -y "${missing[@]}"
    else
        info "编译依赖已齐全 (cmake / pkg-config / libmbedtls-dev)"
    fi
}

# ── 步骤 3: 静态编译 ─────────────────────────────────────────────────────────

do_build() {
    do_download
    do_deps

    info "静态编译 (AGENT_STANDALONE=ON AGENT_STATIC=ON ${VELACLAW_BUILD_TYPE}, -j${VELACLAW_JOBS})"
    (
        cd "${VELACLAW_DIR}"
        # shellcheck disable=SC2086
        cmake -B build-linux \
            -DAGENT_STANDALONE=ON \
            -DAGENT_STATIC=ON \
            -DCMAKE_BUILD_TYPE="${VELACLAW_BUILD_TYPE}" \
            ${VELACLAW_CMAKE_EXTRA}
        cmake --build build-linux -j"${VELACLAW_JOBS}"
    )

    local bin="${BUILD_DIR}/ai_agent"
    [ -x "$bin" ] || die "编译失败: 未生成 ${bin}"

    info "编译完成: ${bin} ($(du -h "$bin" | cut -f1))"
    if file "$bin" | grep -q 'statically linked'; then
        info "链接方式: 静态链接 ✓ (无需目标机安装任何运行库)"
    else
        warn "链接方式: 未检测到静态链接, 请检查 libmbedtls-dev 是否提供 .a 静态库"
    fi
    info "运行: ${bin}   (数据目录 ${BUILD_DIR}/agent-data/)"
    info "瘦身 (可选): strip ${bin}"
}

# ── 其他命令 ─────────────────────────────────────────────────────────────────

do_clean() {
    [ -d "${BUILD_DIR}" ] || { info "无构建目录: ${BUILD_DIR}"; exit 0; }
    info "清理 ${BUILD_DIR}"
    rm -rf "${BUILD_DIR}"
}

cmd_help() {
    sed -n '3,50p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ── 入口 ─────────────────────────────────────────────────────────────────────

case "${1:-build}" in
    download)  do_download ;;
    build)     do_build ;;
    all)       do_build ;;
    clean)     do_clean ;;
    help|-h|--help) cmd_help ;;
    *)         die "未知命令: $1 (执行 $(basename "$0") help 查看用法)" ;;
esac

return 0

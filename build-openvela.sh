#!/usr/bin/env bash
#
# build-velaclaw.sh — VelaClaw (packages/ai_agent) 一键下载与编译脚本
#
# 依据文档:
#   - docs/zh-cn/quickstart/openvela_ubuntu_quick_start.md (openvela 环境搭建/源码下载/编译)
#   - packages/ai_agent/README.md                          (AI Agent 启用/编译/Linux 独立编译)
#
# 用法:
#   ./build-velaclaw.sh <命令>
#
# 命令:
#   all         下载源码 → 启用 AI Agent → 编译固件 (完整流程)
#   download    安装依赖并下载 openvela 源码 (repo init + sync)
#   enable      在板级 defconfig 中启用 AI Agent (幂等, 非交互)
#   menuconfig  打开 menuconfig 手动调整配置
#   build       编译 openvela 固件
#   emulator    启动 Vela Emulator 运行编译产物
#   linux       Linux 独立编译 ai_agent (无需完整 openvela 源码)
#   help        显示帮助
#
# 环境变量 (均有默认值):
#   OPENVELA_DIR       openvela 源码目录          (默认: <脚本所在目录>/openvela)
#   VELACLAW_SOURCE    源码平台 github|gitee|gitcode (默认: github)
#   VELACLAW_PROTO     传输协议 ssh|https           (默认: https)
#   VELACLAW_CONFIG    板级配置名                   (默认: goldfish-arm64-v8a-ap)
#   VELACLAW_JOBS      编译并行数                   (默认: nproc)
#   VELACLAW_BUILD_TYPE  Linux 独立编译类型          (默认: Release)
#   VELACLAW_CMAKE_EXTRA  Linux 独立编译附加参数, 如
#                        "-DAGENT_ENABLE_MCP=ON -DAGENT_STATIC=ON"
#
# 示例:
#   ./build-velaclaw.sh all                                    # 完整流程
#   VELACLAW_SOURCE=gitee ./build-velaclaw.sh download         # 从 Gitee 拉源码
#   ./build-velaclaw.sh build                                  # 只编译
#   ./build-velaclaw.sh emulator                               # 跑模拟器
#   ./build-velaclaw.sh linux                                  # Linux 独立编译
#   VELACLAW_CMAKE_EXTRA="-DAGENT_ENABLE_MQTT=ON -DAGENT_STATIC=ON" \
#       ./build-velaclaw.sh linux                              # 独立编译(开MQTT+静态)
#

set -euo pipefail

# ── 全局配置 ─────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OPENVELA_DIR="${OPENVELA_DIR:-${SCRIPT_DIR}/openvela}"
VELACLAW_SOURCE="${VELACLAW_SOURCE:-github}"
VELACLAW_PROTO="${VELACLAW_PROTO:-https}"
VELACLAW_CONFIG="${VELACLAW_CONFIG:-goldfish-arm64-v8a-ap}"
VELACLAW_JOBS="${VELACLAW_JOBS:-$(nproc 2>/dev/null || echo 4)}"
VELACLAW_BUILD_TYPE="${VELACLAW_BUILD_TYPE:-Release}"
VELACLAW_CMAKE_EXTRA="${VELACLAW_CMAKE_EXTRA:-}"

BOARD_CONFIG_PATH="vendor/openvela/boards/vela/configs/${VELACLAW_CONFIG}"
AGENT_PACKAGE_DIR="${OPENVELA_DIR}/packages/ai_agent"

# AI Agent 需要的额外 Kconfig 项 (SYSTEM_POPEN 供 run_shell 工具使用)
AGENT_DEFCONFIG_LINES=(
    "CONFIG_EXAMPLES_AI_AGENT_VELA=y"
    "CONFIG_SYSTEM_POPEN=y"
)

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

manifest_url() {
    case "${VELACLAW_SOURCE}:${VELACLAW_PROTO}" in
        github:ssh)  echo "ssh://git@github.com/open-vela/manifests.git" ;;
        github:https) echo "https://github.com/open-vela/manifests.git" ;;
        gitee:ssh)   echo "ssh://git@gitee.com/open-vela/manifests.git" ;;
        gitee:https) echo "https://gitee.com/open-vela/manifests.git" ;;
        gitcode:ssh) echo "ssh://git@gitcode.com/open-vela/manifests.git" ;;
        gitcode:https) echo "https://gitcode.com/open-vela/manifests.git" ;;
        *) die "无效的源码平台/协议: ${VELACLAW_SOURCE}/${VELACLAW_PROTO} \
(可选 VELACLAW_SOURCE=github|gitee|gitcode, VELACLAW_PROTO=ssh|https)" ;;
    esac
}

# ── 步骤 1: 依赖安装 (对应快速入门「步骤一」) ───────────────────────────────

install_deps() {
    info "检查并安装编译依赖 (git curl cmake python3 libc++abi-dev build-essential)..."
    local missing=()
    for pkg in git curl cmake python3 libc++abi-dev build-essential; do
        dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        as_root apt update
        as_root apt install -y "${missing[@]}"
    else
        info "基础编译依赖已齐全"
    fi

    # Git LFS: 仓库含大文件, 未配置会导致文件损坏 (见快速入门说明)
    if ! have git-lfs; then
        info "安装 Git LFS..."
        curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh \
            | as_root bash
        as_root apt-get install -y git-lfs
    fi
    if ! git lfs install >/dev/null 2>&1; then
        die "git lfs install 失败, 请手动执行后重试"
    fi
    info "Git LFS 就绪"
}

install_repo_tool() {
    if have repo; then
        info "repo 工具已安装: $(command -v repo)"
        return
    fi
    info "安装 repo 工具..."
    local tmp; tmp="$(mktemp)"
    curl -sSL "https://storage.googleapis.com/git-repo-downloads/repo" > "$tmp"
    chmod +x "$tmp"
    if [ "$(id -u)" -eq 0 ] || have sudo; then
        as_root mv "$tmp" /usr/local/bin/repo
    else
        # 无 root 权限时装到用户目录
        mkdir -p "${HOME}/.local/bin"
        mv "$tmp" "${HOME}/.local/bin/repo"
        case ":${PATH}:" in
            *":${HOME}/.local/bin:"*) ;;
            *) warn "请将 ~/.local/bin 加入 PATH 后重试" ;;
        esac
    fi
    have repo || die "repo 安装后仍不可用, 请检查 PATH"
}

# ── 步骤 2: 下载源码 (对应快速入门「步骤二」) ───────────────────────────────

cmd_download() {
    install_deps
    install_repo_tool

    if [ -d "${OPENVELA_DIR}/.repo" ]; then
        info "检测到已有 openvela 工作区: ${OPENVELA_DIR}, 跳过 repo init"
    else
        info "初始化 openvela 工作区: ${OPENVELA_DIR}"
        info "源码平台: ${VELACLAW_SOURCE} (${VELACLAW_PROTO})"
        mkdir -p "${OPENVELA_DIR}"
        (
            cd "${OPENVELA_DIR}"
            repo init -u "$(manifest_url)" -b dev -m openvela.xml \
                --repo-url=https://mirrors.tuna.tsinghua.edu.cn/git/git-repo/ \
                --git-lfs
        )
    fi

    info "同步源码 (repo sync, 首次耗时较长, 中断后可重复执行本命令续传)..."
    (
        cd "${OPENVELA_DIR}"
        repo sync -c -j"${VELACLAW_JOBS}"
    )
    info "源码同步完成 (ai_agent 位于 packages/ai_agent, 由 manifest 自动管理)"
}

# ── 步骤 3: 启用 AI Agent (对应 README「menuconfig 启用」, 非交互版) ────────

cmd_enable() {
    [ -d "${OPENVELA_DIR}" ] || die "openvela 目录不存在: ${OPENVELA_DIR} (先执行 download)"
    local defconfig="${OPENVELA_DIR}/${BOARD_CONFIG_PATH}/defconfig"
    [ -f "$defconfig" ] || die "defconfig 不存在: ${defconfig} (检查 VELACLAW_CONFIG)"

    info "板级配置: ${VELACLAW_CONFIG}"
    local changed=0

    for line in "${AGENT_DEFCONFIG_LINES[@]}"; do
        local sym="${line%%=*}"
        # 去掉已有的否定行 (如 "# CONFIG_XXX is not set")
        if grep -q "^# ${sym} is not set$" "$defconfig"; then
            sed -i "/^# ${sym} is not set$/d" "$defconfig"
            changed=1
        fi
        if ! grep -q "^${sym}=" "$defconfig"; then
            printf '%s\n' "$line" >> "$defconfig"
            info "已追加 ${line}"
            changed=1
        fi
    done

    if [ "$changed" -eq 0 ]; then
        info "AI Agent 已启用 (defconfig 无需修改)"
    else
        info "defconfig 已更新, 其余模块 (FEISHU/WEIXIN/MQTT/NODE/MCP) 走 Kconfig 默认值(y)"
    fi
}

# ── 编译 / 模拟器 (对应快速入门「步骤三/四」) ───────────────────────────────

cmd_menuconfig() {
    [ -d "${OPENVELA_DIR}" ] || die "openvela 目录不存在: ${OPENVELA_DIR}"
    cd "${OPENVELA_DIR}"
    ./build.sh "${BOARD_CONFIG_PATH}/" --cmake menuconfig
}

cmd_build() {
    [ -d "${OPENVELA_DIR}" ] || die "openvela 目录不存在: ${OPENVELA_DIR} (先执行 download)"
    [ -d "${AGENT_PACKAGE_DIR}" ] || die "未找到 ai_agent 包: ${AGENT_PACKAGE_DIR}"
    cmd_enable
    info "编译 openvela (${VELACLAW_CONFIG}, -j${VELACLAW_JOBS})..."
    (
        cd "${OPENVELA_DIR}"
        ./build.sh "${BOARD_CONFIG_PATH}/" --cmake -j"${VELACLAW_JOBS}"
    )
    info "编译完成, 产物: ${OPENVELA_DIR}/cmake_out/vela_${VELACLAW_CONFIG}/"
    info "运行模拟器: ${SCRIPT_DIR}/$(basename "$0") emulator"
}

cmd_emulator() {
    local out="${OPENVELA_DIR}/cmake_out/vela_${VELACLAW_CONFIG}"
    [ -d "$out" ] || die "编译产物不存在: ${out} (先执行 build)"
    info "启动 Vela Emulator..."
    (
        cd "${OPENVELA_DIR}"
        ./emulator.sh "cmake_out/vela_${VELACLAW_CONFIG}" -no-window
    )
}

# ── Linux 独立编译 (对应 README「方式二: Linux 独立编译」) ──────────────────

cmd_linux() {
    local pkg="${AGENT_PACKAGE_DIR}"
    if [ ! -d "$pkg" ]; then
        # 允许直接用独立仓库 (不含完整 openvela 时)
        pkg="${SCRIPT_DIR}/packages_ai_agent"
        [ -d "$pkg" ] || die "未找到 ai_agent 源码 (${AGENT_PACKAGE_DIR} 或 ${pkg})"
    fi

    # 依赖: libmbedtls-dev
    if ! pkg-config --exists mbedtls 2>/dev/null; then
        info "安装 libmbedtls-dev (独立编译依赖)..."
        as_root apt update
        as_root apt install -y libmbedtls-dev pkg-config
    fi

    info "Linux 独立编译: ${pkg}"
    (
        cd "$pkg"
        # shellcheck disable=SC2086
        cmake -B build-linux -DAGENT_STANDALONE=ON \
            -DCMAKE_BUILD_TYPE="${VELACLAW_BUILD_TYPE}" \
            ${VELACLAW_CMAKE_EXTRA}
        cmake --build build-linux -j"${VELACLAW_JOBS}"
    )
    info "编译完成: ${pkg}/build-linux/ai_agent"
    info "运行: ${pkg}/build-linux/ai_agent   (数据目录 ${pkg}/build-linux/agent-data/)"
}

# ── 入口 ─────────────────────────────────────────────────────────────────────

cmd_all() {
    cmd_download
    cmd_build
    info "全部完成! 启动模拟器: $(basename "$0") emulator"
}

cmd_help() {
    sed -n '3,50p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

case "${1:-help}" in
    all)        cmd_all ;;
    download)   cmd_download ;;
    enable)     cmd_enable ;;
    menuconfig) cmd_menuconfig ;;
    build)      cmd_build ;;
    emulator)   cmd_emulator ;;
    linux)      cmd_linux ;;
    help|-h|--help) cmd_help ;;
    *)          die "未知命令: $1 (执行 $(basename "$0") help 查看用法)" ;;
esac


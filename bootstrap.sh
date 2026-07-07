#!/usr/bin/env bash

echo "Bootstrap start ..."

# ====================== Install Functions ======================
install_apt()
{
    apt update

    apt install -y build-essential
    apt install -y linux-perf
    apt install -y dh-autoreconf
    apt install -y libcurl4-gnutls-dev
    apt install -y libexpat1-dev
    apt install -y gettext
    apt install -y zlib1g-dev
    apt install -y libssl-dev
    apt install -y libncurses5-dev
    apt install -y libpcre2-dev
    apt install -y libclang-dev
    apt install -y libseccomp-dev
    apt install -y python3
    apt install -y zstd
    apt install -y make
    apt install -y gcc
    apt install -y flex
    apt install -y bison
    apt install -y bc
    apt install -y libelf-dev
    apt install -y autoconf
    apt install -y git
    apt install -y iputils-ping
    apt install -y lrzsz
    apt install -y tmux
    apt install -y universal-ctags
    apt install -y clangd
    apt install -y bubblewrap
    apt install -y npm
}

setting_podman() {
    cat > /etc/containers/registries.conf << EOF
unqualified-search-registries = ["docker.io"]  # 默认还是搜docker.io
# 重点! 把镜像源地址“附魔”到docker.io前缀上!
[[registry]]
prefix = "docker.io"
location = "docker.m.daocloud.io"   # DaoCloud, 连接全世界
[[registry]]
prefix = "docker.io"
location = "docker.1ms.run"       # 毫秒加速, YYDS
[[registry]]
prefix = "docker.io"
location = "hub.rat.dev"          # 鼠鼠快车, 稳
[[registry]]
prefix = "docker.io"
location = "docker.xuanyuan.me"   # 轩辕快递, 使命必达
[[registry]]
prefix = "docker.io"
location = "docker.1panel.live"   # 1Panel专线, 官方认证
EOF
}

get_github_release() {
    local repo=$1
    if command -v jq >/dev/null 2>&1; then
        curl -sL "https://api.github.com/repos/${repo}/releases/latest" | jq -r .tag_name
    else
        curl -sL "https://api.github.com/repos/${repo}/releases/latest" \
            | grep -o '"tag_name":[[:space:]]*"[^"]*"' \
            | head -n 1 \
            | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/'
    fi
}

install_skills()
{
    local gitdir="$HOME/github"
    local repo_name="rust-skills"
    [ ! -d $gitdir ] && mkdir -p $gitdir
    pushd $gitdir
        if [ ! -d $gitdir/$repo_name ]; then
            git clone https://github.com/actionbook/rust-skills
            pushd $gitdir/$repo_name
                git reset --hard fa60f79
            popd
        fi
    popd
    local SKILLS=(
        "m01-ownership"
        "m02-resource"
        "m03-mutability"
        "m04-zero-cost"
        "m05-type-driven"
        "m06-error-handling"
        "m07-concurrency"
        "m10-performance"
        "m14-mental-model"
        "m15-anti-pattern"
        "unsafe-checker"
        "rust-symbol-analyzer"
        "rust-call-graph"
        "rust-code-navigator"
        "rust-deps-visualizer"
        "rust-refactor-helper"
        "coding-guidelines"
        "rust-learner"
    )
    local TARGET_DIR="$HOME/.claude/skills"
    [ ! -d $TARGET_DIR ] && mkdir -p $TARGET_DIR
    for skill in "${SKILLS[@]}"; do
        SRC="$gitdir/$repo_name/skills/$skill"
        DEST="$TARGET_DIR/$skill"
        if [ -n "$skill" ]; then
            if [ -d "$DEST" ]; then
                rm -rf "$DEST"
            fi
            cp -r "$SRC" "$DEST"
        fi
    done
    SRC="doc/aster/aster-code-write"
    DEST="$TARGET_DIR/aster-code-write"
    [ -d "$DEST" ] && rm -rf "$DEST"
    cp -r "$SRC" "$DEST"
}

setting_claude() {
    apt update
    if ! command -v npm >/dev/null 2>&1; then
        apt install -y npm
    fi
    if ! command -v claude >/dev/null 2>&1; then
        npm install -g @anthropic-ai/claude-code
    fi
    [ ! -d $HOME/.claude ] && mkdir -p $HOME/.claude
    # See https://aiping.cn/docs/UseCases/coding-assistant
    cat > $HOME/.claude/settings.json << EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://aiping.cn/api/v1/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "<YOUR_API_KEY>",
    "API_TIMEOUT_MS": "3000000",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": 1,
    "ANTHROPIC_MODEL": "Claude-Sonnet-4.6",
    "ANTHROPIC_SMALL_FAST_MODEL": "Claude-Haiku-4.5",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "Claude-Sonnet-4.6",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "Claude-Opus-4.5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "Claude-Haiku-4.5"
  }
}
EOF
}

install_rust()
{
    if [ -e $HOME/.cargo/bin/rustup ]; then
        return 0
    fi
    export RUSTUP_DIST_SERVER="https://rsproxy.cn"
    curl https://sh.rustup.rs -sSf | sh -s -- -y

    for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -e "$rcfile" ]; then
            if ! grep -q '\.cargo/env"' "$rcfile" 2>/dev/null; then
                echo '. "$HOME/.cargo/env"' >> $rcfile
            fi
        fi
    done
}

install_delta()
{
    local insdir=/usr/local/bin
    local pkgname="delta"
    local release="0.18.2"

    if command -v $pkgname >/dev/null 2>&1; then
        return 0
    fi

    [ ! -d $insdir ] && mkdir -p $insdir

    if [ ! -e ${pkgname}-${release}-x86_64-unknown-linux-musl.tar.gz ]; then
        wget https://github.com/dandavison/delta/releases/download/${release}/delta-${release}-x86_64-unknown-linux-musl.tar.gz
    fi
    [ -d delta-${release}-x86_64-unknown-linux-musl ] && rm -rf delta-${release}-x86_64-unknown-linux-musl
    tar -xf delta-${release}-x86_64-unknown-linux-musl.tar.gz
    cp -f delta-${release}-x86_64-unknown-linux-musl/delta ${insdir}/
    chmod a+x ${insdir}/delta
    [ -d delta-${release}-x86_64-unknown-linux-musl ] && rm -rf delta-${release}-x86_64-unknown-linux-musl
    [ -e delta-${release}-x86_64-unknown-linux-musl.tar.gz ] && rm -f delta-${release}-x86_64-unknown-linux-musl.tar.gz

    cat > ${HOME}/.gitconfig <<EOF
[color]
    ui = auto
[core]
    editor = vi
    pager = delta
[interactive]
    diffFilter = delta --color-only
[delta]
    navigate = true
    dark = true
    blame-code-style = syntax
    blame-palette = "#55007f #7f007f #7f7f00 #aa0044 #44aa00 #0044aa #007f7f #007f00"
    blame-timestamp-output-format = "%Y-%m-%d %H:%M"
    blame-format = "{commit:<8} {timestamp:<16} {author:<18}"
EOF

    for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -e "$rcfile" ]; then
            if ! grep -q "^alias git-cm=" "$rcfile" 2>/dev/null; then
                echo "alias git-cm='git commit -s -a'" >> "$rcfile"
            fi

            if ! grep -q "^alias git-log=" "$rcfile" 2>/dev/null; then
                echo "alias git-log='git log --pretty=format:\"%h - %an %ae, %ar : %s\"'" >> "$rcfile"
            fi
        fi
    done
}

install_bat()
{
    local insdir=/usr/local/bin
    local pkgname="bat"
    local release="v0.26.1"

    if command -v $pkgname >/dev/null 2>&1; then
        return 0
    fi

    [ ! -d $insdir ] && mkdir -p $insdir

    if [ ! -e ${pkgname}-${release}-x86_64-unknown-linux-musl.tar.gz ]; then
        wget https://github.com/sharkdp/${pkgname}/releases/download/${release}/${pkgname}-${release}-x86_64-unknown-linux-musl.tar.gz
    fi
    [ -d ${pkgname}-${release}-x86_64-unknown-linux-musl ] && rm -rf ${pkgname}-${release}-x86_64-unknown-linux-musl
    tar -xf ${pkgname}-${release}-x86_64-unknown-linux-musl.tar.gz
    cp -f ${pkgname}-${release}-x86_64-unknown-linux-musl/bat ${insdir}/
    chmod a+x ${insdir}/bat
    [ -d ${pkgname}-${release}-x86_64-unknown-linux-musl ] && rm -rf ${pkgname}-${release}-x86_64-unknown-linux-musl
    [ -e ${pkgname}-${release}-x86_64-unknown-linux-musl.tar.gz ] && rm -f ${pkgname}-${release}-x86_64-unknown-linux-musl.tar.gz

    for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -e "$rcfile" ]; then
            if ! grep -q "^alias cat=" "$rcfile" 2>/dev/null; then
                echo "alias cat='bat -pp'" >> "$rcfile"
            fi
        fi
    done
}

install_zellij()
{
    local insdir=/usr/local/bin
    local zellij_release="v0.44.0"

    if command -v zellij >/dev/null 2>&1; then
        return 0
    fi

    [ ! -d $insdir ] && mkdir -p $insdir

    if [ ! -e zellij-x86_64-unknown-linux-musl.tar.gz ]; then
        wget https://github.com/zellij-org/zellij/releases/download/${zellij_release}/zellij-x86_64-unknown-linux-musl.tar.gz
    fi
    tar -xf zellij-x86_64-unknown-linux-musl.tar.gz -C ${insdir}/
    chmod a+x ${insdir}/zellij

    [ ! -d ~/.config/zellij ] && mkdir -p ~/.config/zellij
    cp -f config/zeiilj.kdl ~/.config/zellij/config.kdl

    [ -e zellij-x86_64-unknown-linux-musl.tar.gz ] && rm -f zellij-x86_64-unknown-linux-musl.tar.gz
    # sed -i 's|// mouse_mode false|mouse_mode false|' ~/.config/zellij/config.kdl
}

install_ripgrep()
{
    local insdir=/usr/local/bin
    local pkgname="ripgrep"
    local release="15.1.0"

    if command -v rg >/dev/null 2>&1; then
        return 0
    fi

    [ ! -d $insdir ] && mkdir -p $insdir

    if [ ! -e ${pkgname}-${release}-x86_64-unknown-linux-musl.tar.gz ]; then
        wget https://github.com/BurntSushi/${pkgname}/releases/download/${release}/${pkgname}-${release}-x86_64-unknown-linux-musl.tar.gz
    fi
    [ -d ${pkgname}-${release}-x86_64-unknown-linux-musl ] && rm -rf ${pkgname}-${release}-x86_64-unknown-linux-musl
    tar -xf ${pkgname}-${release}-x86_64-unknown-linux-musl.tar.gz
    cp -f ${pkgname}-${release}-x86_64-unknown-linux-musl/rg ${insdir}/
    chmod a+x ${insdir}/rg
    [ -d ${pkgname}-${release}-x86_64-unknown-linux-musl ] && rm -rf ${pkgname}-${release}-x86_64-unknown-linux-musl
    [ -e ${pkgname}-${release}-x86_64-unknown-linux-musl.tar.gz ] && rm -f ${pkgname}-${release}-x86_64-unknown-linux-musl.tar.gz
}

install_codex()
{
    local insdir=/usr/local/bin
    local pkgname="codex"
    local repo="openai/$pkgname"
    local release="$(get_github_release $repo)"

    [ ! -d $HOME/.codex ] && mkdir -p $HOME/.codex
    cat > $HOME/.codex/config.toml << EOF
[model_providers.aiping]
name = "AIPing Responses API"
base_url = "https://aiping.cn/api/v1"
env_key = "AIPING_API_KEY"
wire_api = "responses"
requires_openai_auth = false
request_max_retries = 4
stream_max_retries = 10
stream_idle_timeout_ms = 300000
EOF
    cat > $HOME/.codex/aiping.config.toml << EOF
model_provider = "aiping"
model = "gpt-5.5"
model_reasoning_effort = "high"
approval_policy = "on-request"
EOF

    if command -v $pkgname >/dev/null 2>&1; then
        return 0
    fi

    [ ! -d $insdir ] && mkdir -p $insdir

    if [ ! -e ${pkgname}-x86_64-unknown-linux-musl.tar.gz ]; then
        wget https://github.com/${repo}/releases/download/${release}/${pkgname}-x86_64-unknown-linux-musl.tar.gz
    fi
    tar -xf ${pkgname}-x86_64-unknown-linux-musl.tar.gz
    cp -f ${pkgname}-x86_64-unknown-linux-musl ${insdir}/${pkgname}
    chmod a+x ${insdir}/${pkgname}
    [ -e ${pkgname}-x86_64-unknown-linux-musl ] && rm -f ${pkgname}-x86_64-unknown-linux-musl
    [ -e ${pkgname}-x86_64-unknown-linux-musl.tar.gz ] && rm -f ${pkgname}-x86_64-unknown-linux-musl.tar.gz
}

install_opencode()
{
    local insdir=/usr/local/bin
    local pkgname="opencode"
    local repo="anomalyco/$pkgname"
    local release="$(get_github_release $repo)"

    if command -v opencode >/dev/null 2>&1; then
        return 0
    fi

    [ ! -d $insdir ] && mkdir -p $insdir
    if [ ! -e ${pkgname}-linux-x64.tar.gz ]; then
        wget https://github.com/${repo}/releases/download/${release}/${pkgname}-linux-x64.tar.gz
    fi
    [ -e  ${pkgname}-linux-x64.tar.gz ] && tar -xf ${pkgname}-linux-x64.tar.gz -C ${insdir}/
    [ -e  ${pkgname}-linux-x64.tar.gz ] && rm -f ${pkgname}-linux-x64.tar.gz
}

install_pandoc()
{
    local insdir=/usr/local/bin
    local pkgname="pandoc"
    local release="3.10"
    local filename="${pkgname}-${release}-linux-amd64"

    if command -v pandoc >/dev/null 2>&1; then
        return 0
    fi

    [ ! -d $insdir ] && mkdir -p $insdir

    if [ ! -e ${filename}.tar.gz ]; then
        wget https://github.com/jgm/${pkgname}/releases/download/${release}/${filename}.tar.gz
    fi

    [ -e ${filename}.tar.gz ] && tar -xf ${filename}.tar.gz --strip-components=2 -C ${insdir}/ ${pkgname}-${release}/bin/
    [ -e ${filename}.tar.gz ] && rm -f ${filename}.tar.gz
}

install_vimll()
{
    local gitdir="$HOME/github"
    [ ! -d $gitdir ] && mkdir -p $gitdir
    pushd $gitdir
        [ ! -d $gitdir/vimll ] && git clone https://github.com/hbuxiaofei/vimll
        pushd $gitdir/vimll
            bash install.sh
        popd
    popd
}

install_nvimll()
{
    local gitdir="$HOME/github"
    [ ! -d $gitdir ] && mkdir -p $gitdir
    pushd $gitdir
        [ ! -d $gitdir/nvimll ] && git clone https://github.com/hbuxiaofei/nvimll
        pushd $gitdir/nvimll
            bash install.sh
        popd
    popd
}

# ====================== Help Information ======================
all_available()
{
    echo "$(declare -F | grep '^declare -f install_' | awk '{print $3}' | sed 's/^install_//' | tr '\n' ' ' | sed 's/ $//')"
}

show_help()
{
    cat << EOF
Usage: $0 [command]

Available commands:
    all                Run all install functions (install_*)
    <name>             Run the specified install function (e.g. apt, rust, zellij)
    -h, --help, help   Show this help message

Available install functions:
    $(all_available)

Examples:
    $0 all                  # Run all installations
    $0 apt                  # Run only install apt
    $0 rust                 # Run only install rust
    $0 -h                   # Show help
EOF
}

# ====================== Main ============================
main() {
    # Show help if no arguments or help requested
    if [ $# -eq 0 ] || [[ "$1" =~ ^(-h|--help|help)$ ]]; then
        show_help
        exit 0
    fi

    # Handle "all" command
    if [ "$1" = "all" ]; then
        echo "Running all installation tasks..."
        for func in $(declare -F | grep '^declare -f install_' | awk '{print $3}'); do
            echo "==> Running ${func} ..."
            "$func"
            echo "==> ${func} completed"
        done
        echo "All installation tasks finished!"
        exit 0
    fi

    # Handle one or more specific function names
    for arg in "$@"; do
        func_name="install_${arg}"

        if declare -F "$func_name" > /dev/null; then
            echo "==> Running ${func_name} ..."
            "$func_name"
            echo "==> ${func_name} completed"
        else
            echo "Error: Installation function '${func_name}' not found (argument: ${arg})" >&2
            echo "Available arguments: $(all_available)" >&2
            exit 1
        fi
    done

    echo "Specified tasks completed successfully!"
}

# Run main function with all arguments
main "$@"

exit 0

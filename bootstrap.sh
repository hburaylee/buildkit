#!/usr/bin/env bash

# ====================== Install Functions ======================
install_apt()
{
    apt update

    apt install -y build-essential
    apt install -y dh-autoreconf
    apt install -y libcurl4-gnutls-dev
    apt install -y libexpat1-dev
    apt install -y gettext
    apt install -y zlib1g-dev
    apt install -y libssl-dev
    apt install -y libncurses5-dev
    apt install -y libpcre2-dev
    apt install -y python3
    apt install -y make
    apt install -y gcc
    apt install -y autoconf
    apt install -y git
    apt install -y iputils-ping
    apt install -y lrzsz
    apt install -y tmux
}

install_rust()
{
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

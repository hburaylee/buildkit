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
    apt install -y make
    apt install -y gcc
    apt install -y autoconf
    apt install -y git
    apt install -y iputils-ping
    apt install -y lrzsz
}

install_rust()
{
    export RUSTUP_DIST_SERVER="https://rsproxy.cn"
    curl https://sh.rustup.rs -sSf | sh
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

    # sed -i 's|// mouse_mode false|mouse_mode false|' ~/.config/zellij/config.kdl
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

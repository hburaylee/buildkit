#!/usr/bin/env bash
#
#
#


version="v0.20.7"
tarball="ollama-linux-amd64.tar.zst"


file_wget() {
    if command -v mwget >/dev/null 2>&1; then
        mwget $1
    else
        wget $1
    fi
}

if [ ! -e ${tarball} ]; then
    file_wget https://github.com/ollama/ollama/releases/download/${version}/${tarball}
fi

[ -d ollama ] && rm -rf ollama
mkdir ollama

tar -I zstd -xvf ollama-linux-amd64.tar.zst -C ./ollama/

exit 0

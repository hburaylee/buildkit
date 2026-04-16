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

# ollama
# Base URL: http://localhost:11434/api/chat (暂不支持  http://localhost:11434/v1/chat/completions)
#

# ./ollama/bin/ollama serve
# ./ollama/bin/ollama run gemma3:270m
#
# curl -s https://z6xlkuyp7d-3000.cnb.run/v1/chat/completions \
#     -H "Content-Type: application/json" \
#     -H "Authorization: Bearer sk-21158cb317be4ed78072c64e5da105414ba223cf10fe4ba4" \
#     -d '{"model": "gemma3:270m","messages":[{"role": "user","content": "你好"}], "stream":false}'


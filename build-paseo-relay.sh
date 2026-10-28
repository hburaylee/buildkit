#!/usr/bin/env bash

app="paseo-relay-rs"

echo ">>> build ${app}"

if ! command -v paseo >/dev/null 2>&1; then
    npm install -g @getpaseo/cli
fi

[ ! -d ${app} ] && git clone https://github.com/rayylee/${app}
pushd ${app}
	cargo build --release
popd

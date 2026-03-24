#!/usr/bin/env bash

app="mwget"

echo ">>> build ${app}"

[ ! -d ${app} ] && git clone https://github.com/rayylee/${app} 
pushd ${app}
	cargo build --release
popd


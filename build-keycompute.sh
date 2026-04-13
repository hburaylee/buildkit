#!/usr/bin/env bash

app="keycompute"

echo ">>> build ${app}"

apt install -y redis
apt install -y postgresql
apt install -y librust-openssl-sys-dev
apt install -y librust-glib-sys-dev
apt install -y librust-cairo-sys-rs-dev
apt install -y libgdk-pixbuf-2.0-dev
apt install -y librust-atk-sys-dev
apt install -y librust-pango-sys-dev
apt install -y librust-gdk-dev
apt install -y libsoup-3.0-dev
apt install -y libjavascriptcoregtk-4.1-dev
apt install -y libwebkit2gtk-4.1-dev

[ ! -d ${app} ] && git clone https://github.com/rayylee/${app}
pushd ${app}
    cargo build --workspace --exclude desktop --exclude mobile --verbose
popd


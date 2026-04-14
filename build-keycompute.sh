#!/usr/bin/env bash

app="keycompute"

echo ">>> build ${app}"

apt_install() {
    apt install -y podman
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
}

setting_podman() {
    cat >  /etc/containers/registries.conf << EOF
unqualified-search-registries = ["docker.io"]  # 默认还是搜docker.io
# 重点! 把镜像源地址“附魔”到docker.io前缀上!
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

apt_install
setting_podman

[ ! -d ${app} ] && git clone https://github.com/rayylee/${app}
pushd ${app}
    cargo build --workspace --exclude desktop --exclude mobile --verbose
popd


#!/usr/bin/env bash

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



# rust
export RUSTUP_DIST_SERVER="https://rsproxy.cn"
curl https://sh.rustup.rs -sSf | sh

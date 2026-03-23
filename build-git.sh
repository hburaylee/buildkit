#! /usr/bin/env bash

echo ""
echo "This may take some time, please sit back and take a coffee."
echo ""

mkdir -p output
git clone https://github.com/git/git -b v2.53.0
cd git

export NO_OPENSSL=1
export CFLAGS="${CFLAGS} -static"

make configure
./configure prefix=/usr/local
make
make install
make clean

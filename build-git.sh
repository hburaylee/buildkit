#! /usr/bin/env bash

echo ">>> build git"

[ ! -d git ] && git clone https://github.com/git/git -b v2.53.0
pushd git
	# export NO_OPENSSL=1
	# export NO_CURL=1
	export CFLAGS="${CFLAGS} -static -O2"

	make configure
	./configure prefix=/usr/local
	make -j $(nproc) git
popd

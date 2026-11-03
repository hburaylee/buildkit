#!/bin/bash

# codex-cli 0.166.0
# smoke-codex-pytest.sh

export UV_PYTHON=/run/current-system/sw/bin/python3.12
export PYTHONPATH="/root/codex/sdk/python/src:/root/codex/sdk/python/tests"
export BASE=/root/codex

pushd codex/scripts/codex_package/smoke_tests
    uv run --frozen pytest -v --compression gzip \
        --package-target x86_64-unknown-linux-musl \
        --cli-archive "$BASE/codex-package-x86_64-unknown-linux-musl.tar.gz" \
        --app-server-archive "$BASE/codex-app-server-package-x86_64-unknown-linux-musl.tar.gz" \
        --symbols-archive "$BASE/codex-symbols-x86_64-unknown-linux-musl.tar.gz" \
        test_codex_package.py
popd

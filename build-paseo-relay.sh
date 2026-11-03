#!/usr/bin/env bash

app="paseo-relay-rs"

echo ">>> build ${app}"

if ! command -v paseo >/dev/null 2>&1; then
    npm install -g @getpaseo/cli
fi


start_client() {
    # npm install -g @getpaseo/cli
    paseo daemon stop

    # Relay endpoints must be host:port; the port is dropped from the app link.
    RELAY_HOST="rcore-os.org.cn:80"
    APP_BASE_URL="http://rcore-os.org.cn"

    PASEO_APP_BASE_URL=$APP_BASE_URL \
        PASEO_RELAY_ENDPOINT=$RELAY_HOST \
        PASEO_RELAY_PUBLIC_ENDPOINT=$RELAY_HOST \
        PASEO_RELAY_ENABLED=true \
        PASEO_RELAY_USE_TLS=false \
        paseo daemon start

    # paseo daemon pair --relay
}

start_client_cnb() {
    paseo daemon stop

    PORT=80
    URL="${CNB_VSCODE_PROXY_URI//\{\{port\}\}/$PORT}"
    URL="${URL#https://}"

    RELAY_HOST="${URL}:443"
    APP_BASE_URL="https://${URL}"

    # ~/.paseo/config.json
    paseo daemon config set app.baseUrl "$APP_BASE_URL"
    paseo daemon config set daemon.cors.allowedOrigins "[\"https://${URL}\"]"
    paseo daemon config set daemon.relay.enabled true
    paseo daemon config set daemon.relay.endpoint "$RELAY_HOST"
    paseo daemon config set daemon.relay.publicEndpoint "$RELAY_HOST"
    paseo daemon config set daemon.relay.useTls true
    paseo daemon config set daemon.relay.publicUseTls true

    paseo daemon start

    paseo daemon pair --relay
}

start_relay_server() {
    local paseo_relay="./paseo-relay-rs/target/x86_64-unknown-linux-musl/release/paseo-relay"
    if [ ! -e $paseo_relay ]; then
        paseo_relay="./paseo-relay-rs/target/x86_64-unknown-linux-musl/debug/paseo-relay"
    fi
    if [ ! -e $paseo_relay ]; then
        paseo_relay="./paseo-relay-rs/target/release/paseo-relay"
    fi
    if [ ! -e $paseo_relay ]; then
        paseo_relay="./paseo-relay-rs/target/debug/paseo-relay"
    fi
    PASEO_RELAY_HOST=0.0.0.0 \
        PASEO_RELAY_DEBUG=false \
        PASEO_RELAY_PORT=80 \
        $paseo_relay
}

if [ -n "$1" ]; then
    if [ "$1" == "server" ]; then
        start_relay_server
    elif [ "$1" == "client" ]; then
        start_client_cnb
    fi
    exit 0
fi

[ ! -d ${app} ] && git clone https://github.com/rayylee/${app}
pushd ${app}
	cargo build --release
popd

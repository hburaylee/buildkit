#!/usr/bin/env bash
#


# ollama
# Base URL: http://localhost:11434/api/chat (暂不支持  http://localhost:11434/v1/chat/completions)
#

API_URL="https://4l23vuj5an-3000.cnb.run/v1"
API_KEY="sk-a116f17b0bf14c4d9e63f449b3d47d91ba9cb36a53f4458c"
API_MODEL="gemma3:270m"

do_start() {
    nohup ./ollama/bin/ollama serve > ollama.log 2>&1 &
    sleep 1
    ./ollama/bin/ollama pull gemma3:270m
}

do_chat() {

    BACKEND_URI=$(echo "$CNB_VSCODE_PROXY_URI" | sed "s/{{port}}/3000/g")
    curl -s ${API_URL}/chat/completions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d "$(cat <<EOF
        {
            "model": "${API_MODEL}",
            "messages": [{"role": "user", "content": "你好"}], "stream":false
        }
EOF
)"

}

case "$1" in
    start)
        do_start
        ;;
    chat)
        do_chat
        ;;
    *)
        echo "Usage: $0 {start|chat [model_name]}"
        echo "  start  - Start Ollama service in background"
        echo "  chat   - Start chat"
        exit 1
        ;;
esac

exit 0

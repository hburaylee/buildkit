#!/usr/bin/env bash
#


# ollama
# Base URL: http://localhost:11434/api/chat (暂不支持  http://localhost:11434/v1/chat/completions)
#           OLLAMA_BASE=$(echo "$CNB_VSCODE_PROXY_URI" | sed "s/{{port}}/11434/g") && echo $OLLAMA_BASE/api/chat

API_URL="https://wuot4fa6z8-80.cnb.run/v1"
API_KEY="sk-daa8bd8af04049918ab2890dba6ab980aab0b7d17ae64f8f"
API_MODEL="gemma3:270m"

do_start() {
    nohup ./ollama/bin/ollama serve > ollama.log 2>&1 &
    sleep 1
    ./ollama/bin/ollama pull gemma3:270m
}

do_chat() {

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

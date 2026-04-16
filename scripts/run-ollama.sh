#!/usr/bin/env bash
#


# ollama
# Base URL: http://localhost:11434/api/chat (暂不支持  http://localhost:11434/v1/chat/completions)
#

do_start() {
    nohup ./ollama/bin/ollama serve > ollama.log 2>&1 &
    sleep 1
    ./ollama/bin/ollama pull gemma3:270m
}

do_chat() {

    BACKEND_URI=$(echo "$CNB_VSCODE_PROXY_URI" | sed "s/{{port}}/3000/g")
    curl -s $BACKEND_URI/v1/chat/completions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer sk-21158cb317be4ed78072c64e5da105414ba223cf10fe4ba4" \
        -d '{"model": "gemma3:270m","messages":[{"role": "user","content": "你好"}], "stream":false}'
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

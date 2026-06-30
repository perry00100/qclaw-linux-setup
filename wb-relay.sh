#!/bin/bash
# ============================================================
# wb-relay — 双 WorkBuddy GitHub 协调中继
# 通过 GitHub 仓库交换消息，不需要开放端口
# 用法: bash <(curl -fsSL https://raw.githubusercontent.com/perry00100/qclaw-linux-setup/main/wb-relay.sh)
#
# 首次运行会提示输入 GitHub Token（不硬编码）
# ============================================================
set -euo pipefail

GITHUB_USER="perry00100"
RELAY_REPO="qclaw-linux-setup"
RELAY_BRANCH="main"
RELAY_DIR="wb-relay"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERR]${NC}  $1"; }

get_token() {
    if [ -f ~/.wb_relay_token ]; then
        GITHUB_TOKEN=$(cat ~/.wb_relay_token)
        return
    fi
    echo -n "请输入 GitHub Personal Access Token（repo 权限）: "
    read -rs GITHUB_TOKEN
    echo ""
    [ -z "$GITHUB_TOKEN" ] &amp;&amp; { err "Token 不能为空"; exit 1; }
    echo "$GITHUB_TOKEN" > ~/.wb_relay_token
    chmod 600 ~/.wb_relay_token
    info "Token 已保存到 ~/.wb_relay_token"
}

detect_identity() {
    if [ -f ~/.wb_identity ]; then
        MY_NAME=$(cat ~/.wb_identity)
    else
        echo -n "请输入你的身份 (A 或 B): "
        read -r ans
        case "$ans" in a|A) MY_NAME="workbuddy-a" ;; b|B) MY_NAME="workbuddy-b" ;; *) MY_NAME="$ans" ;; esac
        echo "$MY_NAME" > ~/.wb_identity
    fi
    PARTNER="workbuddy-b"; [ "$MY_NAME" = "workbuddy-b" ] &amp;&amp; PARTNER="workbuddy-a"
    info "我是: $MY_NAME  |  对方: $PARTNER"
}

gh_api() {
    local m="$1" p="$2" d="${3:-}"
    if [ -n "$d" ]; then curl -sf -X "$m" "https://api.github.com$p" -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" -d "$d" 2>/dev/null
    else curl -sf -X "$m" "https://api.github.com$p" -H "Authorization: token $GITHUB_TOKEN" 2>/dev/null; fi
}

get_sha() {
    gh_api GET "/repos/$GITHUB_USER/$RELAY_REPO/contents/$RELAY_DIR/$1?ref=$RELAY_BRANCH" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('sha',''))" 2>/dev/null || echo ""
}

gh_push() {
    local p="$1" c="$2" m="$3"
    local b64=$(echo -n "$c" | base64 -w0)
    local s=$(get_sha "$p")
    local d='{"branch":"'$RELAY_BRANCH'","message":"'$m'","content":"'$b64'"'
    [ -n "$s" ] &amp;&amp; d+=',"sha":"'$s'"'
    d+='}'
    gh_api PUT "/repos/$GITHUB_USER/$RELAY_REPO/contents/$p" "$d" > /dev/null 2>&amp;1
}

gh_read() {
    gh_api GET "/repos/$GITHUB_USER/$RELAY_REPO/contents/$RELAY_DIR/$1?ref=$RELAY_BRANCH" 2>/dev/null \
    | python3 -c "import sys,json,base64; d=json.load(sys.stdin); print(base64.b64decode(d['content']).decode(), end='')" 2>/dev/null || true
}

cmd_send() {
    local ev="${1:-}" pl="${2:-}"
    [ -z "$ev" ] &amp;&amp; { err "用法: wb-relay send <事件> [载荷]"; exit 1; }
    local ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local fn="msg_${MY_NAME}_$(date +%s).yaml"
    local c="from: $MY_NAME\nto: $PARTNER\nevent: $ev\nts: $ts\npayload: ${pl:-null}"
    gh_push "$RELAY_DIR/inbox/$PARTNER/$fn" "$(echo -e "$c")" "wb-relay: $MY_NAME → $PARTNER [$ev]"
    info "消息已发送: $ev"
}

cmd_inbox() {
    info "检查收件箱..."
    local msgs=$(gh_api GET "/repos/$GITHUB_USER/$RELAY_REPO/contents/$RELAY_DIR/inbox/$MY_NAME?ref=$RELAY_BRANCH" 2>/dev/null \
    | python3 -c "
import sys,json
try:
    items=json.load(sys.stdin)
    if isinstance(items,list):
        for i in items: print(i['name'])
except: pass" 2>/dev/null || true)
    [ -z "$msgs" ] &amp;&amp; { info "收件箱为空"; return; }
    echo "$msgs" | while read -r f; do
        echo "──────────────"
        echo "📨 $f"
        local c=$(gh_read "inbox/$MY_NAME/$f")
        echo "$c"
        gh_push "$RELAY_DIR/archive/$MY_NAME/$f" "$c" "wb-relay: archive $f"
        local s=$(get_sha "$RELAY_DIR/inbox/$MY_NAME/$f")
        [ -n "$s" ] &amp;&amp; gh_api DELETE "/repos/$GITHUB_USER/$RELAY_REPO/contents/$RELAY_DIR/inbox/$MY_NAME/$f" \
            '{"branch":"'$RELAY_BRANCH'","message":"wb-relay: read '$f'","sha":"'$s'"}' > /dev/null 2>&amp;1 || true
    done
}

cmd_share() {
    local k="${1:-}" v="${2:-}"
    [ -z "$k" ] &amp;&amp; { err "用法: wb-relay share <key> <value>"; exit 1; }
    local c="from: $MY_NAME\nkey: $k\nvalue: $v\nts: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    gh_push "$RELAY_DIR/memory/${k}.yaml" "$(echo -e "$c")" "wb-relay: share '$k'"
    info "记忆已共享: $k = $v"
}

cmd_fetch() {
    local k="${1:-}"
    [ -z "$k" ] &amp;&amp; { err "用法: wb-relay fetch <key>"; exit 1; }
    local v=$(gh_read "memory/${k}.yaml")
    [ -n "$v" ] &amp;&amp; echo "$v" || warn "未找到记忆: $k"
}

cmd_status() {
    info "检查 $PARTNER 状态..."
    local my=$(date +%s)
    gh_push "$RELAY_DIR/status/$MY_NAME" "online: $my" "wb-relay: heartbeat $MY_NAME" > /dev/null 2>&amp;1
    local pt=$(gh_read "status/$PARTNER" 2>/dev/null | grep "online:" | awk '{print $2}' || echo "0")
    local now=$(date +%s)
    local df=$((now - pt))
    if [ "$df" -lt 300 ] 2>/dev/null; then echo -e "${GREEN}🟢 $PARTNER 在线${NC}（${df}秒前心跳）"
    else echo -e "${RED}🔴 $PARTNER 离线${NC}"; fi
}

cmd_list() {
    info "共享记忆列表:"
    gh_api GET "/repos/$GITHUB_USER/$RELAY_REPO/contents/$RELAY_DIR/memory?ref=$RELAY_BRANCH" 2>/dev/null \
    | python3 -c "
import sys,json
try:
    items=json.load(sys.stdin)
    if isinstance(items,list):
        for i in items: print(f\"  📄 {i['name'].replace('.yaml',''):30s} {i.get('size','?')}B\")
    else: print('  (空)')
except: print('  (无法读取)')" 2>/dev/null || echo "  (空)"
}

main() {
    get_token
    detect_identity
    gh_api GET "/repos/$GITHUB_USER/$RELAY_REPO/contents/$RELAY_DIR?ref=$RELAY_BRANCH" > /dev/null 2>&amp;1 || \
        gh_push "$RELAY_DIR/.keep" "wb-relay coordination directory" "wb-relay: init" > /dev/null 2>&amp;1 || true
    case "${1:-help}" in
        send|s)          cmd_send "${2:-}" "${3:-}" ;;
        inbox|in|mail)   cmd_inbox ;;
        share|remember|mem) cmd_share "${2:-}" "${3:-}" ;;
        fetch|recall|get) cmd_fetch "${2:-}" ;;
        status|ping|who) cmd_status ;;
        list|ls|memories) cmd_list ;;
        *)
            echo "================================================"
            echo "  🧠 wb-relay — 双 WorkBuddy GitHub 协调中继"
            echo "================================================"
            echo ""
            echo "通信:"
            echo "  wb-relay send <事件> [载荷]   发送消息"
            echo "  wb-relay inbox                检查收件箱"
            echo ""
            echo "记忆:"
            echo "  wb-relay share <key> <value>  写入共享记忆"
            echo "  wb-relay fetch <key>          读取共享记忆"
            echo "  wb-relay list                 列出所有记忆"
            echo ""
            echo "状态:"
            echo "  wb-relay status               查看对方在线状态"
            echo "================================================" ;;
    esac
}
main "$@"
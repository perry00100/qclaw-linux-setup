#!/bin/bash
# ============================================================
# wb-relay — 双 WorkBuddy GitHub 协调中继
# 通过 GitHub 仓库交换消息，不需要开放端口
# 用法: bash <(curl -fsSL https://raw.githubusercontent.com/perry00100/qclaw-linux-setup/main/wb-relay.sh)
#
# 首次运行会提示输入 GitHub Token（不硬编码）
# ============================================================
set -euo pipefail

# ---- 默认配置 ----
GITHUB_USER="perry00100"
RELAY_REPO="qclaw-linux-setup"
RELAY_BRANCH="main"
RELAY_DIR="wb-relay"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERR]${NC}  $1"; }
me()    { echo -e "${BLUE}[ME]${NC}   $1"; }

# ---- Token 获取 ----
get_token() {
    if [ -f ~/.wb_relay_token ]; then
        GITHUB_TOKEN=$(cat ~/.wb_relay_token)
        return
    fi
    echo -n "请输入 GitHub Personal Access Token（repo 权限）: "
    read -rs GITHUB_TOKEN
    echo ""
    if [ -z "$GITHUB_TOKEN" ]; then
        err "Token 不能为空"
        exit 1
    fi
    echo "$GITHUB_TOKEN" > ~/.wb_relay_token
    chmod 600 ~/.wb_relay_token
    info "Token 已保存到 ~/.wb_relay_token（仅本机可读）"
}

# ---- 检测身份 ----
detect_identity() {
    if [ -f ~/.wb_identity ]; then
        MY_NAME=$(cat ~/.wb_identity)
    else
        echo -n "请输入你的身份 (A 或 B): "
        read -r ans
        case "$ans" in
            a|A) MY_NAME="workbuddy-a" ;;
            b|B) MY_NAME="workbuddy-b" ;;
            *)   MY_NAME="$ans" ;;
        esac
        echo "$MY_NAME" > ~/.wb_identity
    fi
    PARTNER="workbuddy-b"
    [ "$MY_NAME" = "workbuddy-b" ] && PARTNER="workbuddy-a"
    info "我是: $MY_NAME  |  对方: $PARTNER"
}

# ---- GitHub API 调用 ----
gh_api() {
    local method="$1" path="$2" data="${3:-}"
    if [ -n "$data" ]; then
        curl -sf -X "$method" "https://api.github.com$path" \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$data" 2>/dev/null
    else
        curl -sf -X "$method" "https://api.github.com$path" \
            -H "Authorization: token $GITHUB_TOKEN" 2>/dev/null
    fi
}

# ---- 获取仓库默认分支的 SHA ----
get_sha() {
    gh_api GET "/repos/$GITHUB_USER/$RELAY_REPO/contents/$RELAY_DIR/$1?ref=$RELAY_BRANCH" 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('sha',''))" 2>/dev/null || echo ""
}

# ---- 写入文件到仓库 ----
gh_push() {
    local path="$1" content="$2" msg="$3"
    local b64_content=$(echo -n "$content" | base64 -w0)
    local existing_sha=$(get_sha "$path")
    local data='{"branch":"'$RELAY_BRANCH'","message":"'$msg'","content":"'$b64_content'"'
    if [ -n "$existing_sha" ]; then
        data+=',"sha":"'$existing_sha'"'
    fi
    data+='}'
    gh_api PUT "/repos/$GITHUB_USER/$RELAY_REPO/contents/$path" "$data" > /dev/null 2>&1
}

# ---- 读取文件 ----
gh_read() {
    gh_api GET "/repos/$GITHUB_USER/$RELAY_REPO/contents/$RELAY_DIR/$1?ref=$RELAY_BRANCH" 2>/dev/null \
        | python3 -c "
import sys,json,base64
try:
    d=json.load(sys.stdin)
    print(base64.b64decode(d['content']).decode(), end='')
except: print('', end='')
" 2>/dev/null || true
}

# ============================================================
# 核心功能
# ============================================================

# ---- 发送消息 ----
cmd_send() {
    local event="${1:-}" payload="${2:-}"
    [ -z "$event" ] && { err "用法: wb-relay send <事件> [载荷]"; exit 1; }
    local ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local content="---
from: $MY_NAME
to: $PARTNER
event: $event
ts: $ts
payload: |"
    [ -n "$payload" ] && content+="
  $payload" || content+="
  null"
    
    local filename="msg_${MY_NAME}_$(date +%s).yaml"
    gh_push "$RELAY_DIR/inbox/$PARTNER/$filename" "$content" "wb-relay: $MY_NAME → $PARTNER [$event]"
    info "消息已发送: $event"
}

# ---- 检查收件箱 ----
cmd_inbox() {
    info "检查收件箱..."
    local msgs=$(gh_api GET "/repos/$GITHUB_USER/$RELAY_REPO/contents/$RELAY_DIR/inbox/$MY_NAME?ref=$RELAY_BRANCH" 2>/dev/null \
        | python3 -c "
import sys,json
try:
    items=json.load(sys.stdin)
    if isinstance(items,list):
        for i in items:
            print(i['name'])
except: pass
" 2>/dev/null || true)
    
    if [ -z "$msgs" ]; then
        info "收件箱为空"
        return
    fi
    echo "$msgs" | while read -r fname; do
        echo "──────────────────────────────"
        echo "📨 $fname"
        gh_read "inbox/$MY_NAME/$fname" | head -10
        # 读完移入归档
        local content=$(gh_read "inbox/$MY_NAME/$fname")
        gh_push "$RELAY_DIR/archive/$MY_NAME/$fname" "$content" "wb-relay: archive $fname"
        # 删除
        local sha=$(get_sha "$RELAY_DIR/inbox/$MY_NAME/$fname")
        if [ -n "$sha" ]; then
            gh_api DELETE "/repos/$GITHUB_USER/$RELAY_REPO/contents/$RELAY_DIR/inbox/$MY_NAME/$fname" \
                '{"branch":"'$RELAY_BRANCH'","message":"wb-relay: read '$fname'","sha":"'$sha'"}' > /dev/null 2>&1 || true
        fi
    done
}

# ---- 共享记忆 ----
cmd_share() {
    local key="${1:-}" value="${2:-}"
    [ -z "$key" ] && { err "用法: wb-relay share <key> <value>"; exit 1; }
    local content="---
from: $MY_NAME
key: $key
value: $value
ts: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    gh_push "$RELAY_DIR/memory/${key}.yaml" "$content" "wb-relay: share '$key'"
    info "记忆已共享: $key = $value"
}

# ---- 读取共享记忆 ----
cmd_fetch() {
    local key="${1:-}"
    [ -z "$key" ] && { err "用法: wb-relay fetch <key>"; exit 1; }
    local val=$(gh_read "memory/${key}.yaml")
    if [ -n "$val" ]; then
        echo "$val"
    else
        warn "未找到记忆: $key"
    fi
}

# ---- 查看对方状态 ----
cmd_status() {
    info "检查 $PARTNER 状态..."
    local my_ts=$(date +%s)
    gh_push "$RELAY_DIR/status/$MY_NAME" "online: $my_ts" "wb-relay: heartbeat $MY_NAME" > /dev/null 2>&1
    
    local partner_ts=$(gh_read "status/$PARTNER" 2>/dev/null | grep "online:" | awk '{print $2}' || echo "0")
    local now=$(date +%s)
    local diff=$((now - partner_ts))
    
    if [ "$diff" -lt 300 ] 2>/dev/null; then
        echo -e "${GREEN}🟢 $PARTNER 在线${NC}（${diff}秒前心跳）"
    else
        echo -e "${RED}🔴 $PARTNER 离线${NC}"
    fi
}

# ---- 已读消息去重文件 ----
SEEN_FILE="$HOME/.wb_relay_seen"

seen_init() {
    touch "$SEEN_FILE"
}

seen_check() {
    local id="$1"
    grep -qF "$id" "$SEEN_FILE" 2>/dev/null
}

seen_add() {
    local id="$1"
    echo "$id" >> "$SEEN_FILE"
    # 只保留最近 200 条
    tail -200 "$SEEN_FILE" > "${SEEN_FILE}.tmp" && mv "${SEEN_FILE}.tmp" "$SEEN_FILE"
}

# ---- 实时监听（自动轮询） ----
cmd_listen() {
    info "📡 进入实时监听模式（每10秒自动检查收件箱）"
    info "按 Ctrl+C 退出"
    echo ""
    
    # 先发送心跳
    gh_push "$RELAY_DIR/status/$MY_NAME" "online: $(date +%s)" "wb-relay: heartbeat $MY_NAME" > /dev/null 2>&1
    
    seen_init
    local empty_count=0
    
    while true; do
        # 1. 刷新心跳（每30秒）
        if [ $((empty_count % 3)) -eq 0 ]; then
            gh_push "$RELAY_DIR/status/$MY_NAME" "online: $(date +%s)" "wb-relay: heartbeat $MY_NAME" > /dev/null 2>&1
        fi
        
        # 2. 检查收件箱
        local msgs=$(gh_api GET "/repos/$GITHUB_USER/$RELAY_REPO/contents/$RELAY_DIR/inbox/$MY_NAME?ref=$RELAY_BRANCH" 2>/dev/null \
            | python3 -c "
import sys,json
try:
    items=json.load(sys.stdin)
    if isinstance(items,list):
        for i in items: print(i['name'])
except: pass" 2>/dev/null || true)
        
        local new_count=0
        if [ -n "$msgs" ]; then
            while IFS= read -r fname; do
                [ -z "$fname" ] && continue
                if ! seen_check "$fname"; then
                    seen_add "$fname"
                    new_count=$((new_count + 1))
                    echo ""
                    echo "═══════════════════════════════════════"
                    echo -e "${GREEN}📨 新消息 ${fname}${NC}"
                    echo "───────────────────────────────────────"
                    local content=$(gh_read "inbox/$MY_NAME/$fname" 2>/dev/null)
                    echo "$content"
                    
                    # 归档 + 删除
                    gh_push "$RELAY_DIR/archive/$MY_NAME/$fname" "$content" "wb-relay: archive $fname" > /dev/null 2>&1
                    local sha=$(get_sha "$RELAY_DIR/inbox/$MY_NAME/$fname" 2>/dev/null)
                    if [ -n "$sha" ]; then
                        gh_api DELETE "/repos/$GITHUB_USER/$RELAY_REPO/contents/$RELAY_DIR/inbox/$MY_NAME/$fname" \
                            '{"branch":"'$RELAY_BRANCH'","message":"wb-relay: read '$fname'","sha":"'$sha'"}' > /dev/null 2>&1 || true
                    fi
                    echo "═══════════════════════════════════════"
                    echo ""
                fi
            done <<< "$msgs"
        fi
        
        [ "$new_count" -eq 0 ] && empty_count=$((empty_count + 1)) || empty_count=0
        
        sleep 10
    done
}

# ---- 列出所有共享记忆 ----
cmd_list() {
    info "共享记忆列表:"
    gh_api GET "/repos/$GITHUB_USER/$RELAY_REPO/contents/$RELAY_DIR/memory?ref=$RELAY_BRANCH" 2>/dev/null \
        | python3 -c "
import sys,json
try:
    items=json.load(sys.stdin)
    if isinstance(items,list):
        for i in items:
            print(f\"  📄 {i['name'].replace('.yaml',''):30s} {i.get('size','?')}B\")
    else:
        print('  (空)')
except: print('  (无法读取)')" 2>/dev/null || echo "  (空)"
}

# ============================================================
# 主入口
# ============================================================
main() {
    get_token
    detect_identity
    
    # 确保 relay 目录存在
    gh_api GET "/repos/$GITHUB_USER/$RELAY_REPO/contents/$RELAY_DIR?ref=$RELAY_BRANCH" > /dev/null 2>&1 || \
        gh_push "$RELAY_DIR/.keep" "wb-relay coordination directory" "wb-relay: init" > /dev/null 2>&1 || true

    case "${1:-help}" in
        send|s)
            cmd_send "${2:-}" "${3:-}"
            ;;
        inbox|in|mail)
            cmd_inbox
            ;;
        listen|l|watch)
            cmd_listen
            ;;
        share|remember|mem)
            cmd_share "${2:-}" "${3:-}"
            ;;
        fetch|recall|get)
            cmd_fetch "${2:-}"
            ;;
        status|ping|who)
            cmd_status
            ;;
        list|ls|memories)
            cmd_list
            ;;
        *)
            echo "================================================"
            echo "  🧠 wb-relay — 双 WorkBuddy GitHub 协调中继"
            echo "================================================"
            echo ""
            echo "用法: wb-relay <命令> [参数]"
            echo ""
            echo "通信:"
            echo "  wb-relay send <事件> [载荷]   发送消息给另一方"
            echo "  wb-relay inbox                检查收件箱"
            echo "  wb-relay listen               实时监听（每10秒自动检查）"
            echo ""
            echo "记忆:"
            echo "  wb-relay share <key> <value>  写入共享记忆"
            echo "  wb-relay fetch <key>          读取共享记忆"
            echo "  wb-relay list                 列出所有共享记忆"
            echo ""
            echo "状态:"
            echo "  wb-relay status               查看对方在线状态"
            echo ""
            echo "示例:"
            echo "  wb-relay send hello '{\"msg\":\"你好B\"}'"
            echo "  wb-relay share result '分析完成'"
            echo "  wb-relay inbox"
            echo "  wb-relay status"
            echo "================================================"
            ;;
    esac
}

main "$@"

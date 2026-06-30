#!/bin/bash
# ============================================================
# QClaw/Linux 一键恢复脚本
# 用法: bash <(curl -fsSL https://gist.githubusercontent.com/perry00100/xxx/raw/restore.sh)
# 或手动: wget https://raw.githubusercontent.com/perry00100/... && chmod +x restore.sh && ./restore.sh
# ============================================================

set -e

# ---- 配置（首次运行会提示输入）----
GITHUB_TOKEN=""   # GitHub Personal Access Token（支持 classic PAT 或 fine-grained PAT）
GITHUB_USER="perry00100"
BACKUP_DATE="20260629"

# OpenClaw 安装目录（默认 ~/.qclaw）
QCLAW_HOME="$HOME/.qclaw"

# ---- 颜色 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ---- 检测操作系统 ----
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &> /dev/null; then
            OS="debian"
        elif command -v yum &> /dev/null; then
            OS="rhel"
        elif command -v pacman &> /dev/null; then
            OS="arch"
        else
            OS="unknown"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        OS="unknown"
    fi
    log_info "检测到系统: $OSTYPE ($OS)"
}

# ---- 安装依赖 ----
install_deps() {
    log_info "安装系统依赖..."

    if [[ "$OS" == "debian" ]]; then
        sudo apt-get update -qq
        sudo apt-get install -y -qq git curl unzip jq > /dev/null 2>&1
    elif [[ "$OS" == "rhel" ]]; then
        sudo yum install -y -q git curl unzip jq > /dev/null 2>&1
    elif [[ "$OS" == "arch" ]]; then
        sudo pacman -Sy --noconfirm git curl unzip jq > /dev/null 2>&1
    elif [[ "$OS" == "macos" ]]; then
        which git curl unzip jq > /dev/null 2>&1 || brew install git curl jq > /dev/null 2>&1
    fi

    # Node.js
    if ! command -v node &> /dev/null; then
        log_info "安装 Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash - > /dev/null 2>&1
        sudo apt-get install -y -qq nodejs > /dev/null 2>&1
    fi
    log_info "Node.js $(node --version), npm $(npm --version)"
}

# ---- 安装 OpenClaw ----
install_openclaw() {
    if command -v openclaw &> /dev/null; then
        log_info "OpenClaw 已安装: $(openclaw --version 2>/dev/null || echo 'version unknown')"
    else
        log_info "安装 OpenClaw..."
        npm install -g openclaw 2>&1 | tail -3
    fi
}

# ---- 备份现有配置 ----
backup_existing() {
    if [[ -d "$QCLAW_HOME" ]]; then
        BACKUP_DIR="$HOME/qclaw-backup-$(date +%Y%m%d-%H%M%S)"
        log_warn "发现现有 QClaw 配置，备份到: $BACKUP_DIR"
        cp -r "$QCLAW_HOME" "$BACKUP_DIR"
    else
        log_info "未发现现有配置，跳过备份"
    fi
}

# ---- 克隆记忆备份（推荐方式 - 已解压结构）----
restore_memory_backup() {
    log_info "恢复记忆/配置备份..."
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    GIT_HTTP_PATH="https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/qclaw-memory-backup.git"
    git clone --depth=1 "$GIT_HTTP_PATH" qclaw-memory-backup 2>&1 | tail -3

    # 恢复记忆文件
    if [[ -d "qclaw-memory-backup/memory" ]]; then
        mkdir -p "$QCLAW_HOME/memory"
        cp -r qclaw-memory-backup/memory/* "$QCLAW_HOME/memory/" 2>/dev/null || true
        log_info "记忆文件已恢复 ($(ls qclaw-memory-backup/memory/*.md 2>/dev/null | wc -l) 个文件)"
    fi

    # 恢复关键脚本
    if [[ -d "qclaw-memory-backup/scripts" ]]; then
        mkdir -p "$QCLAW_HOME/scripts"
        cp -r qclaw-memory-backup/scripts/* "$QCLAW_HOME/scripts/" 2>/dev/null || true
        log_info "脚本已恢复"
    fi

    # 恢复独立技能（如果有）
    if [[ -d "qclaw-memory-backup/skills" ]]; then
        mkdir -p "$QCLAW_HOME/skills"
        cp -r qclaw-memory-backup/skills/* "$QCLAW_HOME/skills/" 2>/dev/null || true
        log_info "独立技能已恢复"
    fi

    cd ~
    rm -rf "$TEMP_DIR"
    log_info "记忆备份恢复完成"
}

# ---- 恢复技能备份（5分卷ZIP，需下载合并）----
restore_skills_backup() {
    log_info "恢复技能备份（5分卷，下载合并）..."
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    # 下载所有分卷
    SKILLS_REPO_API="https://api.github.com/repos/${GITHUB_USER}/qclaw-skills-backup/releases/latest"
    log_info "获取 Release 信息..."
    ASSET_URLS=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" "$SKILLS_REPO_API" | \
        jq -r '.assets[] | "\(.id)|\(.name)|\(.browser_download_url)"')

    mkdir -p parts
    while IFS='|' read -r id name url; do
        [[ -z "$name" ]] && continue
        log_info "下载 $name..."
        curl -L -o "parts/$name" \
            -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/octet-stream" \
            "$url" 2>&1 | grep -v '%' || true
    done <<< "$ASSET_URLS"

    # 合并分卷
    log_info "合并分卷..."
    cat parts/skills-part*.zip > skills-full.zip

    # 解压到正确位置
    mkdir -p "$QCLAW_HOME/skills"
    unzip -q skills-full.zip -d "$QCLAW_HOME/skills"

    RESTORED=$(ls "$QCLAW_HOME/skills" 2>/dev/null | wc -l)
    log_info "技能恢复完成 ($RESTORED 个目录)"

    cd ~
    rm -rf "$TEMP_DIR"
}

# ---- 配置 GitHub Token ----
config_github_token() {
    log_info "配置 GitHub Token..."
    openclaw config set github.token "$GITHUB_TOKEN" 2>/dev/null || \
        log_warn "Token 配置失败，请手动在 OpenClaw 界面中配置"
}

# ---- 打印汇总 ----
summary() {
    echo ""
    echo "=========================================="
    echo -e "${GREEN}✅ QClaw 恢复完成！${NC}"
    echo "=========================================="
    echo ""
    echo "  📁 配置目录: $QCLAW_HOME"
    echo "  🔑 GitHub Token: ${GITHUB_TOKEN:0:8}..."
    echo "  📦 技能数: $(ls $QCLAW_HOME/skills 2>/dev/null | wc -l)"
    echo "  🧠 记忆文件: $(ls $QCLAW_HOME/memory 2>/dev/null/*.md 2>/dev/null | wc -l)"
    echo ""
    echo "  下一步:"
    echo "    1. 重启 OpenClaw: openclaw restart"
    echo "    2. 检查状态: openclaw status"
    echo "    3. 手动验证技能: openclaw skills list"
    echo ""
}

# ============================================================
# 主流程
# ============================================================
main() {
    echo ""
    echo "=========================================="
    echo -e "${GREEN}🖥️  QClaw Linux 一键恢复脚本${NC}"
    echo "=========================================="
    echo ""

    # 读取 Token
    if [[ -z "$GITHUB_TOKEN" ]]; then
        read -p "请输入 GitHub PAT (perry00100 的 Token): " -s GITHUB_TOKEN
        echo ""
    fi
    if [[ -z "$GITHUB_TOKEN" ]]; then
        log_error "Token 不能为空！"
        exit 1
    fi
    export GITHUB_TOKEN
    log_info "Token 已设置 (${GITHUB_TOKEN:0:8}...)"

    detect_os
    install_deps
    install_openclaw
    backup_existing
    restore_memory_backup

    # 询问是否恢复技能（耗流量/时间）
    if [[ "$1" == "--with-skills" ]]; then
        restore_skills_backup
    else
        log_warn "跳过技能恢复（需 ~100MB 下载）。加 --with-skills 强制恢复。"
        log_info "技能备份地址: https://github.com/${GITHUB_USER}/qclaw-skills-backup/releases"
    fi

    config_github_token
    summary
}

main "$@"

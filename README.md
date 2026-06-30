# 🖥️ QClaw Linux 一键恢复脚本

## 功能
- 自动检测 Linux 发行版并安装依赖
- 安装 Node.js + OpenClaw
- 从 GitHub 恢复记忆文件、脚本、独立技能
- （可选）恢复完整的 155 个技能备份

## 使用方法

### 快速恢复（记忆+配置）
`ash
bash <(curl -fsSL https://raw.githubusercontent.com/perry00100/qclaw-linux-setup/main/restore.sh)
`

### 完整恢复（含全部技能，~100MB）
`ash
bash <(curl -fsSL https://raw.githubusercontent.com/perry00100/qclaw-linux-setup/main/restore.sh) --with-skills
`

## 备份数据来源

| 仓库 | 内容 | 大小 |
|------|------|------|
| [perry00100/qclaw-memory-backup](https://github.com/perry00100/qclaw-memory-backup) | 记忆/脚本/独立技能 | ~5 MB |
| [perry00100/qclaw-skills-backup](https://github.com/perry00100/qclaw-skills-backup) | 155个技能完整备份 | ~99 MB |

## 配置
编辑脚本开头的 GITHUB_TOKEN 为你的 PAT。

## 支持系统
- Ubuntu / Debian
- CentOS / RHEL
- Arch Linux
- macOS
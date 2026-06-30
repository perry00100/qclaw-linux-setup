# 🖥️ QClaw Linux 一键恢复脚本

## 功能
- 自动检测 Linux 发行版并安装依赖（Node.js / git / curl / jq）
- 安装 OpenClaw
- 从 GitHub 恢复记忆文件、脚本、独立技能
- （可选）恢复完整的 155 个技能备份

## 使用方法

### 快速恢复（记忆+配置）
`ash
bash <(curl -fsSL https://raw.githubusercontent.com/perry00100/qclaw-linux-setup/main/restore.sh)
`
首次运行会提示输入 GitHub PAT。

### 完整恢复（含全部技能，~100MB）
`ash
bash <(curl -fsSL https://raw.githubusercontent.com/perry00100/qclaw-linux-setup/main/restore.sh) --with-skills
`

## 备份数据来源

| 仓库 | 内容 | 大小 |
|------|------|------|
| [qclaw-memory-backup](https://github.com/perry00100/qclaw-memory-backup) | 记忆/脚本/独立技能 | ~5 MB |
| [qclaw-skills-backup](https://github.com/perry00100/qclaw-skills-backup) | 155个技能完整备份 | ~99 MB |
| [four-dimension-heart-method](https://github.com/perry00100/four-dimension-heart-method) | 四维心法 v3 | - |

## 支持系统
- ✅ Ubuntu / Debian
- ✅ CentOS / RHEL
- ✅ Arch Linux
- ✅ macOS

## 备份 GitHub Token
在 [GitHub Settings → Personal Access Tokens](https://github.com/settings/tokens) 生成 classic PAT，需要 repo 权限。
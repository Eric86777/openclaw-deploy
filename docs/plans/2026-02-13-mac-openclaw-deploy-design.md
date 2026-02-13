# OpenClaw Mac 本地部署脚本设计文档

**日期**: 2026-02-13
**文件**: `openclaw-deploy-mac.sh`
**定位**: 独立的 macOS 本地 OpenClaw 一键部署管理脚本

---

## 1. 概述

从现有 VPS 版 `openclaw-deploy.sh` 中提取 OpenClaw 模块，适配 macOS 平台，创建独立的 Mac 部署脚本。功能与 VPS 版 OpenClaw 模块完全对齐，但所有系统调用适配 macOS。

## 2. 范围

- 仅包含 OpenClaw 服务（不含 CRS、Sub2API、Resp Proxy）
- 服务管理采用轻量 PID 模式（非 launchd）
- 不需要 root 权限

## 3. 核心适配映射

| 功能 | VPS (Linux) | Mac |
|------|-------------|-----|
| 包管理 | apt-get / yum / dnf | brew |
| Node.js 安装 | nodesource 脚本 | `brew install node` |
| 服务启停 | systemctl start/stop/restart | nohup + PID 文件 + kill |
| 服务状态 | systemctl is-active | PID 文件 + kill -0 + lsof |
| 端口检测 | `ss -lntp` | `lsof -i :PORT -sTCP:LISTEN` |
| 日志查看 | `journalctl -u openclaw` | `tail -f ~/.openclaw/gateway.log` |
| 配置路径 | `/root/.openclaw/` | `$HOME/.openclaw/` |
| IP 显示 | `curl -s4 ip.sb` | `127.0.0.1` / `localhost` |
| 权限要求 | root (EUID=0) | 普通用户 |
| sed 命令 | `sed -i "s\|...\|"` | `sed -i '' "s\|...\|"` |
| 环境变量 | systemd EnvironmentFile | 启动前 `source .env` |

## 4. 一键部署流程

```
[1/4] 检测环境
  ├─ 检测 Homebrew → 没装则自动安装（区分 Apple Silicon / Intel 路径）
  ├─ 检测 Node.js 22+ → 没有或版本低则 brew install node
  └─ 检测 npm 全局安装权限 → EACCES 则修复 prefix

[2/4] 安装 OpenClaw
  └─ npm install -g openclaw@latest

[3/4] 交互式模型配置
  ├─ 选择 API 来源（11种，与 VPS 版 openclaw_config_model 一致）
  │   ├─ 已验证可用的反代: CRS / sub2api-gemini / sub2api-gpt / sub2api-antigravity
  │   ├─ 通用配置: Anthropic反代 / OpenAI兼容中转 / OpenRouter / Gemini反代
  │   └─ 官方直连: Anthropic / OpenAI / Google Gemini
  ├─ 输入 API Key / Base URL
  ├─ 配置模型 ID
  ├─ 配置网关端口和 Token
  └─ 生成 ~/.openclaw/openclaw.json + ~/.openclaw/.env

[4/4] 初始化并启动
  ├─ 创建目录结构:
  │   ├─ ~/.openclaw/agents/main/sessions/
  │   ├─ ~/.openclaw/credentials/
  │   └─ ~/.openclaw/workspace/
  ├─ source ~/.openclaw/.env (加载环境变量)
  ├─ nohup openclaw gateway --port <port> --verbose >> ~/.openclaw/gateway.log 2>&1 &
  ├─ 写入 PID 到 ~/.openclaw/gateway.pid
  └─ 等待 5 秒后验证端口是否监听
```

## 5. 服务管理

### 5.1 PID 生命周期管理

**状态检测（三重验证）**:
```
1. PID 文件存在？
   ├─ 是 → kill -0 $pid 进程存活？
   │        ├─ 是 → ps -p $pid 是 node/openclaw？
   │        │        ├─ 是 → "running"
   │        │        └─ 否 → 清理 PID 文件，继续端口检测
   │        └─ 否 → 清理 PID 文件，继续端口检测
   └─ 否 → 端口检测
2. lsof -i :<port> -sTCP:LISTEN 有结果？
   ├─ 是 → "running_no_pid"（运行中但无 PID 文件）
   └─ 否 → "stopped"
```

**启动流程**:
1. 检查端口是否被占用
2. 如被占用，显示占用进程信息，询问是否 kill
3. source ~/.openclaw/.env
4. nohup 启动 + 写 PID
5. sleep 3 + 验证

**停止流程**:
1. 读取 PID
2. SIGTERM 优雅关闭
3. 等待最多 10 秒
4. 超时则 SIGKILL
5. 清理 PID 文件
6. lsof 验证端口已释放

**重启流程**:
1. 读取 PID
2. 检查端口上是否有不同于 PID 的孤儿进程
3. 如有，先 kill 孤儿进程
4. 停止 → 启动

### 5.2 日志管理

- 日志路径: `~/.openclaw/gateway.log`
- 启动时检查日志大小，>10MB 自动轮转（重命名为 .log.1）
- 查看日志: `tail -100f` 实时跟踪

## 6. 配置管理

### 6.1 模型配置 — openclaw_config_model()

从 VPS 版完整移植（~400 行），包含 11 种 API 来源选择。逻辑是纯 bash + 文件写入，无平台依赖，可直接复用。

### 6.2 快速替换 API — openclaw_quick_api()

从 VPS 版完整移植（~350 行），包含 6 种快捷预设。适配点:
- `sed -i` → `sed -i ''`
- 替换后的 `systemctl restart` → PID 重启
- IP 显示改为 localhost

### 6.3 频道管理 — openclaw_channels()

从 VPS 版完整移植（~400 行），包含完整子菜单:
- Telegram Bot 配置（Token 输入 + JSON 配置生成）
- WhatsApp 配置（QR 码登录流程）
- Discord Bot 配置（Token + 权限指引）
- Slack 配置（双 Token: App + Bot）
- 查看频道状态 / 日志
- 断开/删除频道

辅助函数同步移植:
- `openclaw_update_channel()` — Node.js JSON5 配置合并
- `openclaw_remove_channel()` — Node.js 配置移除

适配点: 频道操作后的 `systemctl restart` → PID 重启

### 6.4 查看/编辑配置

- `openclaw_show_config()` — IP 显示改为 localhost，去掉 SSH 隧道提示
- `openclaw_edit_config()` — 编辑器使用 `${EDITOR:-nano}`

### 6.5 安全检查

- `openclaw doctor` — CLI 命令，无平台依赖，直接调用

## 7. 菜单结构

```
OpenClaw Mac 本地部署工具 v1.0.0
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[部署与更新]
1. 一键部署（首次安装）
2. 更新版本

[服务管理]
3. 查看状态
4. 查看日志
5. 启动服务
6. 停止服务
7. 重启服务

[配置管理]
8. 模型配置（完整配置/首次部署）
9. 快速替换 API（保留现有设置）
10. 频道管理（登录/配置）
11. 查看当前配置
12. 编辑配置文件
13. 安全检查（doctor）

14. 卸载 OpenClaw

0. 退出
```

## 8. Homebrew 与 npm 处理

### 8.1 Homebrew 检测与安装

```
if ! command -v brew:
  检测架构 (uname -m)
  ├─ arm64 → Apple Silicon: /opt/homebrew/bin/brew
  └─ x86_64 → Intel: /usr/local/bin/brew
  安装 Homebrew
  配置 PATH
```

### 8.2 npm 全局权限修复

```
检测 npm install -g 是否会 EACCES:
  测试 npm prefix -g 路径是否可写
  ├─ 可写 → 正常安装
  └─ 不可写 →
      设置 npm prefix = ~/.npm-global
      添加 ~/.npm-global/bin 到 PATH
      写入 ~/.zshrc 或 ~/.bash_profile
```

## 9. 卸载流程

1. 停止服务（kill PID）
2. npm uninstall -g openclaw
3. 询问是否删除配置目录 ~/.openclaw/
4. 清理 PID 文件和日志

## 10. 不包含的功能

- CRS、Sub2API、Resp Proxy 模块
- launchd 开机自启
- root 权限检查
- SSH 隧道提示（本地运行不需要）

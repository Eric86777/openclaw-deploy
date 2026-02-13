# OpenClaw Deploy - 一键部署工具箱

一键部署和管理 OpenClaw 及相关 AI 代理服务的 Bash 脚本工具箱。

从 [net-tcp-tune.sh](https://github.com/Eric86777/vps-tcp-tune) v4.9.0 独立提取。

## 包含服务

| 服务 | 说明 |
|------|------|
| **OpenClaw** | AI 多渠道消息网关，支持 Telegram/WhatsApp/Discord/Slack |
| **CRS** | Claude Relay Service，Claude 多账户中转/拼车 |
| **Sub2API** | 订阅转 API 服务部署管理 |
| **Responses API 转换代理** | 将 Responses API 转换为 Chat Completions API，支持沉浸式翻译等工具 |

## 使用方法

### VPS / Linux 服务器

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Eric86777/openclaw-deploy/main/openclaw-deploy.sh)
```

或下载后运行：

```bash
curl -fsSL https://raw.githubusercontent.com/Eric86777/openclaw-deploy/main/openclaw-deploy.sh -o openclaw-deploy.sh
chmod +x openclaw-deploy.sh
sudo bash openclaw-deploy.sh
```

### Mac 本地部署

Mac 版仅包含 OpenClaw 服务（不含 CRS、Sub2API、Resp Proxy），使用轻量 PID 模式管理服务，无需 root 权限。

```bash
curl -fsSL https://raw.githubusercontent.com/Eric86777/openclaw-deploy/main/openclaw-deploy-mac.sh -o openclaw-deploy-mac.sh
chmod +x openclaw-deploy-mac.sh
bash openclaw-deploy-mac.sh
```

**Mac 版功能：**
- 一键部署与更新
- 服务管理（启动/停止/重启/状态/日志）
- 模型配置（11 种 API 来源：CRS、sub2api、Anthropic、OpenAI、Gemini、OpenRouter 等）
- 快速替换 API（保留现有设置）
- 频道管理（Telegram / WhatsApp / Discord / Slack）
- 查看/编辑配置、安全检查（doctor）、卸载

**Mac 版要求：**
- macOS（Apple Silicon / Intel 均支持）
- 自动安装 Homebrew 和 Node.js 22+

## 系统要求

| 平台 | 要求 |
|------|------|
| **Linux (VPS)** | Debian/Ubuntu/CentOS/RHEL/Fedora, Root 权限, Bash 4.0+ |
| **macOS (本地)** | macOS 12+, 普通用户权限, 自动安装 Homebrew + Node.js |

## 功能菜单

### VPS 版

```
1. OpenClaw 部署管理 (AI多渠道消息网关)
2. CRS 部署管理 (Claude多账户中转/拼车)
3. Sub2API 部署管理
4. OpenAI Responses API 转换代理
0. 退出
```

### Mac 版

```
[部署与更新]
1. 一键部署（首次安装）    2. 更新版本

[服务管理]
3. 查看状态    4. 查看日志    5. 启动    6. 停止    7. 重启

[配置管理]
8. 模型配置    9. 快速替换 API    10. 频道管理
11. 查看配置   12. 编辑配置       13. 安全检查

14. 卸载 OpenClaw
0. 退出
```

每个服务都提供完整的生命周期管理：一键部署、更新、启动/停止/重启、配置管理、日志查看、卸载。

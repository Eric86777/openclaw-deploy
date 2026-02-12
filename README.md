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

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Eric86777/openclaw-deploy/main/openclaw-deploy.sh)
```

或下载后运行：

```bash
curl -fsSL https://raw.githubusercontent.com/Eric86777/openclaw-deploy/main/openclaw-deploy.sh -o openclaw-deploy.sh
chmod +x openclaw-deploy.sh
sudo bash openclaw-deploy.sh
```

## 系统要求

- Linux (Debian/Ubuntu/CentOS/RHEL/Fedora)
- Root 权限
- Bash 4.0+

## 功能菜单

```
1. OpenClaw 部署管理 (AI多渠道消息网关)
2. CRS 部署管理 (Claude多账户中转/拼车)
3. Sub2API 部署管理
4. OpenAI Responses API 转换代理
0. 退出
```

每个服务都提供完整的生命周期管理：一键部署、更新、启动/停止/重启、配置管理、日志查看、卸载。

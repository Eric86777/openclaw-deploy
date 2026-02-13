# OpenClaw Mac 本地部署脚本 实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 创建独立的 `openclaw-deploy-mac.sh` 脚本，在 macOS 上一键部署和管理 OpenClaw，功能与 VPS 版 OpenClaw 模块对齐。

**Architecture:** 单文件 bash 脚本，从 VPS 版 `openclaw-deploy.sh` 的 OpenClaw 模块（行 1494-3431）提取并适配 macOS。服务管理使用 PID 文件 + nohup 模式替代 systemd。所有 Linux 系统调用替换为 macOS 等价命令。

**Tech Stack:** Bash 脚本, Homebrew, Node.js 22+, npm, OpenClaw CLI

**VPS 源文件:** `openclaw-deploy.sh` 行 1494-3431（约 1940 行）

---

## Task 1: 脚本骨架 — 头部、颜色、常量、工具函数

**Files:**
- Create: `openclaw-deploy-mac.sh`

**Step 1: 创建脚本文件，写入头部和基础设施**

```bash
#!/bin/bash
#=============================================================================
# OpenClaw Deploy Mac - macOS 本地部署工具
# 功能：在 Mac 上一键部署和管理 OpenClaw (AI多渠道消息网关)
# 适配自 openclaw-deploy.sh VPS 版
#=============================================================================

MAC_TOOLKIT_VERSION="1.0.0"

#=============================================================================
# 颜色定义（与 VPS 版一致）
#=============================================================================
gl_hong='\033[31m'      # 红色
gl_lv='\033[32m'        # 绿色
gl_huang='\033[33m'     # 黄色
gl_bai='\033[0m'        # 重置
gl_kjlan='\033[96m'     # 亮青色
gl_zi='\033[35m'        # 紫色
gl_hui='\033[90m'       # 灰色

#=============================================================================
# Mac 版常量（对应 VPS 版行 1497-1503，路径改为 $HOME）
#=============================================================================
OPENCLAW_HOME_DIR="${HOME}/.openclaw"
OPENCLAW_CONFIG_FILE="${HOME}/.openclaw/openclaw.json"
OPENCLAW_ENV_FILE="${HOME}/.openclaw/.env"
OPENCLAW_DEFAULT_PORT="18789"
OPENCLAW_PID_FILE="${HOME}/.openclaw/gateway.pid"
OPENCLAW_LOG_FILE="${HOME}/.openclaw/gateway.log"

#=============================================================================
# 共享工具函数
#=============================================================================

# 操作完成暂停（与 VPS 版 break_end 一致）
break_end() {
    echo -e "${gl_lv}操作完成${gl_bai}"
    echo "按任意键继续..."
    read -n 1 -s -r -p ""
    echo ""
}

# 检测系统是否为 macOS
check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        echo -e "${gl_hong}错误: 此脚本仅支持 macOS${gl_bai}"
        echo "VPS/Linux 请使用 openclaw-deploy.sh"
        exit 1
    fi
}
```

**Step 2: 验证脚本语法**

Run: `bash -n openclaw-deploy-mac.sh`
Expected: 无输出（语法正确）

**Step 3: Commit**

```bash
git add openclaw-deploy-mac.sh
git commit -m "feat: add Mac deploy script skeleton with constants and utilities"
```

---

## Task 2: Homebrew 检测与 Node.js 安装

**Files:**
- Modify: `openclaw-deploy-mac.sh`

**对应 VPS 版:** `openclaw_install_nodejs()` 行 1540-1615
**Mac 适配:** 用 brew 替代 nodesource 脚本，增加 Homebrew 自身检测

**Step 1: 写入 Homebrew 检测和 Node.js 安装函数**

```bash
#=============================================================================
# 环境检测与安装
#=============================================================================

# 检测并安装 Homebrew
ensure_homebrew() {
    if command -v brew &>/dev/null; then
        return 0
    fi

    echo -e "${gl_huang}⚠ Homebrew 未安装${gl_bai}"
    echo ""
    read -e -p "是否自动安装 Homebrew？(Y/N): " confirm
    case "$confirm" in
        [Yy])
            echo "正在安装 Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

            # 配置 PATH（区分 Apple Silicon / Intel）
            if [[ "$(uname -m)" == "arm64" ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
                # 写入 shell 配置
                local shell_rc="${HOME}/.zshrc"
                if ! grep -q '/opt/homebrew/bin/brew shellenv' "$shell_rc" 2>/dev/null; then
                    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$shell_rc"
                fi
            else
                eval "$(/usr/local/bin/brew shellenv)"
            fi

            if command -v brew &>/dev/null; then
                echo -e "${gl_lv}✅ Homebrew 安装成功${gl_bai}"
                return 0
            else
                echo -e "${gl_hong}❌ Homebrew 安装失败，请手动安装: https://brew.sh${gl_bai}"
                return 1
            fi
            ;;
        *)
            echo -e "${gl_hong}❌ 需要 Homebrew 来安装依赖${gl_bai}"
            return 1
            ;;
    esac
}

# 检测并安装 Node.js 22+（Mac 版，对应 VPS 版行 1540-1615）
mac_openclaw_install_nodejs() {
    echo -e "${gl_kjlan}[1/4] 检测 Node.js 环境...${gl_bai}"

    if command -v node &>/dev/null; then
        local node_version=$(node -v | sed 's/v//' | cut -d. -f1)
        if [ "$node_version" -ge 22 ]; then
            echo -e "${gl_lv}✅ Node.js $(node -v) 已安装${gl_bai}"
            return 0
        else
            echo -e "${gl_huang}⚠ Node.js 版本过低 ($(node -v))，OpenClaw 需要 22+${gl_bai}"
        fi
    else
        echo -e "${gl_huang}⚠ Node.js 未安装${gl_bai}"
    fi

    echo "正在通过 Homebrew 安装 Node.js..."
    ensure_homebrew || return 1

    brew install node

    if command -v node &>/dev/null; then
        local installed_ver=$(node -v | sed 's/v//' | cut -d. -f1)
        if [ "$installed_ver" -ge 22 ]; then
            echo -e "${gl_lv}✅ Node.js $(node -v) 安装成功${gl_bai}"
            return 0
        else
            echo -e "${gl_hong}❌ Homebrew 安装的 Node.js 版本低于 22，请运行: brew upgrade node${gl_bai}"
            return 1
        fi
    else
        echo -e "${gl_hong}❌ Node.js 安装失败${gl_bai}"
        return 1
    fi
}
```

**Step 2: 验证语法**

Run: `bash -n openclaw-deploy-mac.sh`
Expected: 无输出

**Step 3: Commit**

```bash
git add openclaw-deploy-mac.sh
git commit -m "feat: add Homebrew detection and Node.js installation for Mac"
```

---

## Task 3: npm 权限处理与 OpenClaw 安装

**Files:**
- Modify: `openclaw-deploy-mac.sh`

**对应 VPS 版:** `openclaw_install_pkg()` 行 1618-1633
**Mac 适配:** 检测 npm 全局安装权限，必要时修复 prefix

**Step 1: 写入 npm 权限修复和 OpenClaw 安装函数**

```bash
# 检测并修复 npm 全局安装权限
fix_npm_permissions() {
    local npm_prefix=$(npm prefix -g 2>/dev/null)
    if [ -w "$npm_prefix/lib" ] 2>/dev/null; then
        return 0  # 目录可写，无需修复
    fi

    echo -e "${gl_huang}⚠ npm 全局安装目录权限不足${gl_bai}"
    echo "正在配置 npm 使用用户目录..."

    mkdir -p "${HOME}/.npm-global"
    npm config set prefix "${HOME}/.npm-global"

    # 添加到 PATH
    local shell_rc="${HOME}/.zshrc"
    if ! grep -q '.npm-global/bin' "$shell_rc" 2>/dev/null; then
        echo 'export PATH="${HOME}/.npm-global/bin:${PATH}"' >> "$shell_rc"
    fi
    export PATH="${HOME}/.npm-global/bin:${PATH}"

    echo -e "${gl_lv}✅ npm 全局目录已配置为 ~/.npm-global${gl_bai}"
}

# 安装 OpenClaw（Mac 版，对应 VPS 版行 1618-1633）
mac_openclaw_install_pkg() {
    echo -e "${gl_kjlan}[2/4] 安装 OpenClaw...${gl_bai}"
    echo -e "${gl_hui}正在下载并安装，可能需要 1-3 分钟...${gl_bai}"
    echo ""

    # 先修复权限
    fix_npm_permissions

    npm install -g openclaw@latest --loglevel info

    if command -v openclaw &>/dev/null; then
        local ver=$(openclaw --version 2>/dev/null || echo "unknown")
        echo -e "${gl_lv}✅ OpenClaw ${ver} 安装成功${gl_bai}"
        return 0
    else
        echo -e "${gl_hong}❌ OpenClaw 安装失败${gl_bai}"
        echo -e "${gl_zi}请尝试手动安装: npm install -g openclaw@latest${gl_bai}"
        return 1
    fi
}
```

**Step 2: 验证语法**

Run: `bash -n openclaw-deploy-mac.sh`

**Step 3: Commit**

```bash
git add openclaw-deploy-mac.sh
git commit -m "feat: add npm permission fix and OpenClaw package installation"
```

---

## Task 4: 模型配置函数

**Files:**
- Modify: `openclaw-deploy-mac.sh`

**对应 VPS 版:** `openclaw_config_model()` 行 1636-2049
**Mac 适配:** 此函数是纯 bash + 文件写入，基本无平台依赖，直接复制。唯一变化：删除 VPS 特有的 `break_end` 在错误处理中的调用改为直接 return。

**Step 1: 从 VPS 版完整复制 openclaw_config_model() 函数（行 1636-2049）**

直接复制，无需修改。此函数操作的是 `$OPENCLAW_CONFIG_FILE` 和 `$OPENCLAW_ENV_FILE`（已在常量中定义为 Mac 路径）。

**Step 2: 同时复制辅助函数 openclaw_get_port()（行 1518-1528）**

```bash
# 获取当前端口（与 VPS 版一致，行 1518-1528）
openclaw_get_port() {
    if [ -f "$OPENCLAW_CONFIG_FILE" ]; then
        local port=$(sed -nE 's/.*"?port"?[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "$OPENCLAW_CONFIG_FILE" 2>/dev/null | head -1)
        if [ -n "$port" ]; then
            echo "$port"
            return
        fi
    fi
    echo "$OPENCLAW_DEFAULT_PORT"
}
```

**Step 3: 验证语法**

Run: `bash -n openclaw-deploy-mac.sh`

**Step 4: Commit**

```bash
git add openclaw-deploy-mac.sh
git commit -m "feat: add model configuration with 11 API source types"
```

---

## Task 5: PID 服务管理 — 状态检测、端口检查

**Files:**
- Modify: `openclaw-deploy-mac.sh`

**对应 VPS 版:** `openclaw_check_status()` 行 1505-1515, `openclaw_check_port()` 行 1531-1537
**Mac 适配:** systemctl → PID 文件 + kill -0 + lsof, ss → lsof

**Step 1: 写入 Mac 版状态检测和端口检查**

```bash
#=============================================================================
# Mac 服务管理（PID 模式，替代 VPS 版 systemd）
#=============================================================================

# 端口检测（Mac 版，替代 VPS 版 ss -lntp）
mac_openclaw_check_port() {
    local port=$1
    if lsof -i ":${port}" -sTCP:LISTEN -t &>/dev/null; then
        return 1  # 端口被占用
    fi
    return 0  # 端口可用
}

# 状态检测（Mac 版，三重验证，替代 VPS 版 systemctl）
mac_openclaw_check_status() {
    if ! command -v openclaw &>/dev/null; then
        echo "not_installed"
        return
    fi

    local port=$(openclaw_get_port)

    # 检查 PID 文件
    if [ -f "$OPENCLAW_PID_FILE" ]; then
        local pid=$(cat "$OPENCLAW_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            # PID 存在，验证进程身份
            if ps -p "$pid" -o comm= 2>/dev/null | grep -q "node\|openclaw"; then
                echo "running"
                return
            fi
        fi
        # PID 过期，清理
        rm -f "$OPENCLAW_PID_FILE"
    fi

    # 降级检测：检查端口
    if lsof -i ":${port}" -sTCP:LISTEN -t &>/dev/null; then
        echo "running_no_pid"
        return
    fi

    echo "stopped"
}

# 日志轮转（>10MB 时轮转）
rotate_log_if_needed() {
    if [ -f "$OPENCLAW_LOG_FILE" ]; then
        local size=$(stat -f%z "$OPENCLAW_LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt 10485760 ]; then
            mv "$OPENCLAW_LOG_FILE" "${OPENCLAW_LOG_FILE}.1"
            echo -e "${gl_zi}日志已轮转（>10MB）${gl_bai}"
        fi
    fi
}
```

**Step 2: 验证语法**

Run: `bash -n openclaw-deploy-mac.sh`

**Step 3: Commit**

```bash
git add openclaw-deploy-mac.sh
git commit -m "feat: add PID-based status detection and port checking for Mac"
```

---

## Task 6: PID 服务管理 — 启动、停止、重启

**Files:**
- Modify: `openclaw-deploy-mac.sh`

**对应 VPS 版:** `openclaw_start()` 行 2260-2272, `openclaw_stop()` 行 2275-2286, `openclaw_restart()` 行 2289-2317
**Mac 适配:** systemctl → nohup/PID/kill, 加入 .env 加载, 优雅关闭, 端口冲突检测

**Step 1: 写入启动函数**

```bash
# 启动服务（Mac 版）
mac_openclaw_start() {
    local port=$(openclaw_get_port)

    # 检查是否已在运行
    local status=$(mac_openclaw_check_status)
    if [ "$status" = "running" ]; then
        echo -e "${gl_huang}⚠ 服务已在运行中${gl_bai}"
        return 0
    fi

    # 检查端口冲突
    if ! mac_openclaw_check_port "$port"; then
        local occupy_pid=$(lsof -i ":${port}" -sTCP:LISTEN -t 2>/dev/null | head -1)
        echo -e "${gl_huang}⚠ 端口 ${port} 被进程 ${occupy_pid} 占用${gl_bai}"
        read -e -p "是否终止该进程？(Y/N): " confirm
        case "$confirm" in
            [Yy])
                kill "$occupy_pid" 2>/dev/null
                sleep 2
                if ! mac_openclaw_check_port "$port"; then
                    kill -9 "$occupy_pid" 2>/dev/null
                    sleep 1
                fi
                ;;
            *)
                echo "已取消"
                return 1
                ;;
        esac
    fi

    # 日志轮转
    rotate_log_if_needed

    # 加载环境变量（关键！VPS 版通过 systemd EnvironmentFile 实现）
    if [ -f "$OPENCLAW_ENV_FILE" ]; then
        set -a
        source "$OPENCLAW_ENV_FILE"
        set +a
    fi

    # 确保目录存在
    mkdir -p "$(dirname "$OPENCLAW_LOG_FILE")"

    # 启动网关
    nohup openclaw gateway --port "$port" --verbose >> "$OPENCLAW_LOG_FILE" 2>&1 &
    echo $! > "$OPENCLAW_PID_FILE"

    echo "正在启动..."
    sleep 3

    # 验证
    if ! mac_openclaw_check_port "$port"; then
        echo -e "${gl_lv}✅ OpenClaw 网关已启动 (PID: $(cat "$OPENCLAW_PID_FILE"), 端口: ${port})${gl_bai}"
        return 0
    else
        echo -e "${gl_hong}❌ 启动失败，查看日志: tail -50 ${OPENCLAW_LOG_FILE}${gl_bai}"
        rm -f "$OPENCLAW_PID_FILE"
        return 1
    fi
}
```

**Step 2: 写入停止函数**

```bash
# 停止服务（Mac 版，优雅关闭 + SIGKILL 降级）
mac_openclaw_stop() {
    local port=$(openclaw_get_port)
    local pid=""

    # 从 PID 文件获取
    if [ -f "$OPENCLAW_PID_FILE" ]; then
        pid=$(cat "$OPENCLAW_PID_FILE")
    fi

    # 降级：从端口获取
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
        pid=$(lsof -i ":${port}" -sTCP:LISTEN -t 2>/dev/null | head -1)
    fi

    if [ -z "$pid" ]; then
        echo -e "${gl_huang}⚠ 服务未在运行${gl_bai}"
        rm -f "$OPENCLAW_PID_FILE"
        return 0
    fi

    echo "正在停止服务 (PID: ${pid})..."

    # SIGTERM 优雅关闭
    kill "$pid" 2>/dev/null
    local wait=0
    while kill -0 "$pid" 2>/dev/null && [ $wait -lt 10 ]; do
        sleep 1
        wait=$((wait + 1))
    done

    # 超时则 SIGKILL
    if kill -0 "$pid" 2>/dev/null; then
        echo "优雅关闭超时，强制终止..."
        kill -9 "$pid" 2>/dev/null
        sleep 1
    fi

    rm -f "$OPENCLAW_PID_FILE"

    if mac_openclaw_check_port "$port"; then
        echo -e "${gl_lv}✅ 服务已停止${gl_bai}"
        return 0
    else
        echo -e "${gl_hong}❌ 端口仍被占用，请手动检查${gl_bai}"
        return 1
    fi
}
```

**Step 3: 写入重启函数**

```bash
# 重启服务（Mac 版，含端口冲突检测，对应 VPS 版行 2289-2317）
mac_openclaw_restart() {
    local port=$(openclaw_get_port)

    # 检查端口上是否有孤儿进程（非 PID 文件记录的进程）
    local port_pid=$(lsof -i ":${port}" -sTCP:LISTEN -t 2>/dev/null | head -1)
    if [ -f "$OPENCLAW_PID_FILE" ]; then
        local file_pid=$(cat "$OPENCLAW_PID_FILE")
        if [ -n "$port_pid" ] && [ "$port_pid" != "$file_pid" ]; then
            echo -e "${gl_huang}⚠ 端口 ${port} 被非网关进程 ${port_pid} 占用，正在清理...${gl_bai}"
            kill "$port_pid" 2>/dev/null
            sleep 2
        fi
    fi

    mac_openclaw_stop
    echo ""
    mac_openclaw_start
}
```

**Step 4: 验证语法**

Run: `bash -n openclaw-deploy-mac.sh`

**Step 5: Commit**

```bash
git add openclaw-deploy-mac.sh
git commit -m "feat: add PID-based start/stop/restart service management"
```

---

## Task 7: Onboard 初始化与一键部署编排

**Files:**
- Modify: `openclaw-deploy-mac.sh`

**对应 VPS 版:** `openclaw_onboard()` 行 2052-2100, `openclaw_deploy()` 行 2103-2181
**Mac 适配:** 去掉 systemd 服务创建，改用 nohup 启动；部署完成信息改为 localhost

**Step 1: 写入 onboard 和 deploy 函数**

```bash
# 初始化并启动（Mac 版，对应 VPS 版行 2052-2100）
mac_openclaw_onboard() {
    local port=$(openclaw_get_port)
    echo -e "${gl_kjlan}[4/4] 初始化并启动网关...${gl_bai}"
    echo ""

    # 创建必要目录（VPS 版行 2058-2060）
    mkdir -p "${OPENCLAW_HOME_DIR}/agents/main/sessions"
    mkdir -p "${OPENCLAW_HOME_DIR}/credentials"
    mkdir -p "${OPENCLAW_HOME_DIR}/workspace"

    # 启动服务
    mac_openclaw_start

    return $?
}

# 一键部署（Mac 版，对应 VPS 版行 2103-2181）
mac_openclaw_deploy() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  OpenClaw Mac 一键部署${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    local status=$(mac_openclaw_check_status)
    if [ "$status" = "running" ] || [ "$status" = "running_no_pid" ]; then
        echo -e "${gl_huang}⚠ OpenClaw 已在运行中${gl_bai}"
        echo ""
        read -e -p "是否重新部署？(Y/N): " confirm
        case "$confirm" in
            [Yy]) ;;
            *) return ;;
        esac
        echo ""
        mac_openclaw_stop
    fi

    # 步骤1: Node.js
    mac_openclaw_install_nodejs || { break_end; return 1; }
    echo ""

    # 步骤2: 安装 OpenClaw
    mac_openclaw_install_pkg || { break_end; return 1; }
    echo ""

    # 步骤3: 交互式模型配置
    echo -e "${gl_kjlan}[3/4] 配置模型与 API...${gl_bai}"
    echo ""
    openclaw_config_model || { break_end; return 1; }
    echo ""

    # 步骤4: 初始化并启动
    mac_openclaw_onboard || { break_end; return 1; }

    # 部署完成信息（Mac 版，对应 VPS 版行 2140-2181，去掉 SSH 隧道提示）
    local port=$(openclaw_get_port)

    echo ""
    echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_lv}  ✅ OpenClaw 部署完成！${gl_bai}"
    echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    echo -e "控制面板: ${gl_huang}http://localhost:${port}/${gl_bai}"
    echo ""

    local gw_token=$(sed -nE 's/.*OPENCLAW_GATEWAY_TOKEN=(.*)/\1/p' "$OPENCLAW_ENV_FILE" 2>/dev/null)
    if [ -n "$gw_token" ]; then
        echo -e "网关 Token: ${gl_huang}${gw_token}${gl_bai}"
        echo ""
    fi

    echo -e "${gl_kjlan}【下一步】连接消息频道${gl_bai}"
    echo "  运行本脚本菜单选项「10. 频道管理」"
    echo "  支持: WhatsApp / Telegram / Discord / Slack"
    echo ""
    echo -e "${gl_kjlan}【聊天命令】（在消息平台中使用）${gl_bai}"
    echo "  /status  — 查看会话状态"
    echo "  /new     — 清空上下文"
    echo "  /think   — 调整推理级别"
    echo ""
    echo -e "${gl_kjlan}管理命令:${gl_bai}"
    echo "  PID 文件: ${OPENCLAW_PID_FILE}"
    echo "  日志文件: ${OPENCLAW_LOG_FILE}"
    echo "  安全检查: openclaw doctor"
    echo ""

    break_end
}
```

**Step 2: 验证语法**

Run: `bash -n openclaw-deploy-mac.sh`

**Step 3: Commit**

```bash
git add openclaw-deploy-mac.sh
git commit -m "feat: add onboard initialization and one-click deploy orchestration"
```

---

## Task 8: 更新、状态查看、日志查看

**Files:**
- Modify: `openclaw-deploy-mac.sh`

**对应 VPS 版:** `openclaw_update()` 行 2184-2225, `openclaw_status()` 行 2228-2245, `openclaw_logs()` 行 2248-2257
**Mac 适配:** systemctl → PID 重启, journalctl → tail 日志文件

**Step 1: 写入更新、状态、日志函数**

```bash
# 更新 OpenClaw（Mac 版，对应 VPS 版行 2184-2225）
mac_openclaw_update() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  更新 OpenClaw${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    if ! command -v openclaw &>/dev/null; then
        echo -e "${gl_hong}❌ OpenClaw 未安装，请先执行一键部署${gl_bai}"
        break_end
        return 1
    fi

    local old_ver=$(openclaw --version 2>/dev/null || echo "unknown")
    echo -e "当前版本: ${gl_huang}${old_ver}${gl_bai}"
    echo ""

    echo "正在更新..."
    npm install -g openclaw@latest 2>&1 | tail -10

    local new_ver=$(openclaw --version 2>/dev/null || echo "unknown")
    echo ""

    if [ "$old_ver" = "$new_ver" ]; then
        echo -e "${gl_lv}✅ 已是最新版本 (${new_ver})${gl_bai}"
    else
        echo -e "${gl_lv}✅ 已更新: ${old_ver} → ${new_ver}${gl_bai}"
    fi

    echo ""
    echo "正在重启服务..."
    local status=$(mac_openclaw_check_status)
    if [ "$status" = "running" ] || [ "$status" = "running_no_pid" ]; then
        mac_openclaw_restart
    else
        echo -e "${gl_huang}⚠ 服务未在运行，请手动启动${gl_bai}"
    fi

    break_end
}

# 查看状态（Mac 版，对应 VPS 版行 2228-2245）
mac_openclaw_status() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  OpenClaw 服务状态${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    if command -v openclaw &>/dev/null; then
        echo -e "版本: ${gl_huang}$(openclaw --version 2>/dev/null || echo 'unknown')${gl_bai}"
        echo ""
    fi

    local status=$(mac_openclaw_check_status)
    local port=$(openclaw_get_port)

    case "$status" in
        "not_installed")
            echo -e "状态: ${gl_hong}❌ 未安装${gl_bai}"
            ;;
        "running")
            local pid=$(cat "$OPENCLAW_PID_FILE" 2>/dev/null)
            echo -e "状态: ${gl_lv}✅ 运行中${gl_bai}"
            echo -e "PID:  ${gl_huang}${pid}${gl_bai}"
            echo -e "端口: ${gl_huang}${port}${gl_bai}"
            echo -e "面板: ${gl_huang}http://localhost:${port}/${gl_bai}"
            ;;
        "running_no_pid")
            echo -e "状态: ${gl_huang}⚠ 运行中（无 PID 文件）${gl_bai}"
            local port_pid=$(lsof -i ":${port}" -sTCP:LISTEN -t 2>/dev/null | head -1)
            echo -e "PID:  ${gl_huang}${port_pid}（从端口检测）${gl_bai}"
            echo -e "端口: ${gl_huang}${port}${gl_bai}"
            ;;
        "stopped")
            echo -e "状态: ${gl_hong}❌ 已停止${gl_bai}"
            ;;
    esac

    echo ""
    echo -e "${gl_kjlan}━━━ 配置信息 ━━━${gl_bai}"
    echo "  配置文件: ${OPENCLAW_CONFIG_FILE}"
    echo "  环境变量: ${OPENCLAW_ENV_FILE}"
    echo "  PID 文件: ${OPENCLAW_PID_FILE}"
    echo "  日志文件: ${OPENCLAW_LOG_FILE}"
    echo ""

    break_end
}

# 查看日志（Mac 版，对应 VPS 版行 2248-2257）
mac_openclaw_logs() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  OpenClaw 日志（按 Ctrl+C 退出）${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    if [ -f "$OPENCLAW_LOG_FILE" ]; then
        tail -100f "$OPENCLAW_LOG_FILE"
    else
        echo -e "${gl_huang}⚠ 日志文件不存在: ${OPENCLAW_LOG_FILE}${gl_bai}"
        break_end
    fi
}
```

**Step 2: 验证语法**

Run: `bash -n openclaw-deploy-mac.sh`

**Step 3: Commit**

```bash
git add openclaw-deploy-mac.sh
git commit -m "feat: add update, status, and log viewing functions"
```

---

## Task 9: 快速替换 API

**Files:**
- Modify: `openclaw-deploy-mac.sh`

**对应 VPS 版:** `openclaw_quick_api()` 行 2877-3221
**Mac 适配:**
- 行 3190: `sed -i` → `sed -i ''`
- 行 3200-3210: `systemctl restart/is-active` → `mac_openclaw_restart` / PID 检测

**Step 1: 从 VPS 版复制 openclaw_quick_api() 并做以下修改**

修改点（逐一列出，在复制后搜索替换）：

1. **行 3190** `sed -i "s|..."` → `sed -i '' "s|..."`
2. **行 3200-3210** 替换整个 systemctl 块为：
```bash
    # 重启服务（Mac 版）
    local status=$(mac_openclaw_check_status)
    if [ "$status" = "running" ] || [ "$status" = "running_no_pid" ]; then
        mac_openclaw_restart
        sleep 2
        local new_status=$(mac_openclaw_check_status)
        if [ "$new_status" = "running" ]; then
            echo -e "${gl_lv}✅ 服务已重启，API 已生效${gl_bai}"
        else
            echo -e "${gl_hong}❌ 服务重启失败，查看日志: tail -50 ${OPENCLAW_LOG_FILE}${gl_bai}"
        fi
    else
        echo -e "${gl_huang}⚠ 服务未运行，请手动启动${gl_bai}"
    fi
```

**Step 2: 验证语法**

Run: `bash -n openclaw-deploy-mac.sh`

**Step 3: Commit**

```bash
git add openclaw-deploy-mac.sh
git commit -m "feat: add quick API replacement with Mac-adapted sed and service management"
```

---

## Task 10: 频道管理完整子系统

**Files:**
- Modify: `openclaw-deploy-mac.sh`

**对应 VPS 版:** `openclaw_update_channel()` 行 2320-2366, `openclaw_remove_channel()` 行 2369-2410, `openclaw_channels()` 行 2413-2742
**Mac 适配:** 这三个函数中所有 `systemctl is-active/restart` 替换为 PID 检测和重启

**Step 1: 复制 openclaw_update_channel() 和 openclaw_remove_channel()**

这两个函数是纯 Node.js 脚本执行，**完全无平台依赖**，直接复制即可。

**Step 2: 复制 openclaw_channels() 并修改以下几处**

搜索替换所有（共 6 处）：
```bash
# VPS 版：
if systemctl is-active "$OPENCLAW_SERVICE_NAME" &>/dev/null; then
    systemctl restart "$OPENCLAW_SERVICE_NAME" 2>/dev/null
    sleep 2
    echo -e "${gl_lv}✅ 服务已重启，配置已生效${gl_bai}"
fi

# Mac 版替换为：
local svc_status=$(mac_openclaw_check_status)
if [ "$svc_status" = "running" ] || [ "$svc_status" = "running_no_pid" ]; then
    mac_openclaw_restart 2>/dev/null
    sleep 2
    echo -e "${gl_lv}✅ 服务已重启，配置已生效${gl_bai}"
fi
```

频道日志查看（选项 6）替换：
```bash
# VPS 版（行 2677）：
journalctl -u "$OPENCLAW_SERVICE_NAME" --no-pager -n 50

# Mac 版：
if [ -f "$OPENCLAW_LOG_FILE" ]; then
    tail -50 "$OPENCLAW_LOG_FILE"
else
    echo "日志文件不存在"
fi
```

**Step 3: 验证语法**

Run: `bash -n openclaw-deploy-mac.sh`

**Step 4: Commit**

```bash
git add openclaw-deploy-mac.sh
git commit -m "feat: add complete channel management subsystem (Telegram/WhatsApp/Discord/Slack)"
```

---

## Task 11: 查看配置、编辑配置、安全检查

**Files:**
- Modify: `openclaw-deploy-mac.sh`

**对应 VPS 版:** `openclaw_show_config()` 行 2745-2829, `openclaw_edit_config()` 行 2832-2874, `openclaw_doctor()` 行 3224-3249

**Step 1: 复制 openclaw_show_config() 并做以下修改**

1. **行 2760** `curl -s4 ip.sb` → `"localhost"`
2. **行 2799-2803** 控制面板和 SSH 隧道部分替换为：
```bash
    echo -e "控制面板:   ${gl_huang}http://localhost:${port}/${gl_bai}"
    echo ""
```
（删除 SSH 隧道提示）
3. **行 2807-2809** 管理命令替换为：
```bash
    echo -e "${gl_kjlan}━━━ 管理命令 ━━━${gl_bai}"
    echo "  状态: 本脚本菜单选项 3"
    echo "  日志: tail -f ${OPENCLAW_LOG_FILE}"
    echo "  重启: 本脚本菜单选项 7"
```

**Step 2: 复制 openclaw_edit_config() 并做以下修改**

1. **行 2847-2853** 编辑器选择改为：
```bash
    local editor="${EDITOR:-nano}"
```
2. **行 2858** 提示改为：
```bash
    echo -e "${gl_zi}提示: 修改配置后需重启服务生效${gl_bai}"
```
3. **行 2862-2870** systemctl 重启逻辑替换为 PID 重启

**Step 3: 复制 openclaw_doctor()（行 3224-3249）**

此函数直接调用 `openclaw doctor`，无平台依赖，直接复制即可。

**Step 4: 验证语法**

Run: `bash -n openclaw-deploy-mac.sh`

**Step 5: Commit**

```bash
git add openclaw-deploy-mac.sh
git commit -m "feat: add config viewing, editing, and doctor security check"
```

---

## Task 12: 卸载功能

**Files:**
- Modify: `openclaw-deploy-mac.sh`

**对应 VPS 版:** `openclaw_uninstall()` 行 3252-3302
**Mac 适配:** 删除 systemd 服务清理，改为 PID 清理

**Step 1: 写入卸载函数**

```bash
# 卸载 OpenClaw（Mac 版，对应 VPS 版行 3252-3302）
mac_openclaw_uninstall() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_hong}  卸载 OpenClaw${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    echo -e "${gl_huang}警告: 此操作将删除 OpenClaw 及其所有配置！${gl_bai}"
    echo ""
    echo "将删除以下内容:"
    echo "  - OpenClaw 全局包 (npm)"
    echo "  - PID 文件和日志"
    echo "  - 配置目录 ${OPENCLAW_HOME_DIR}"
    echo ""

    read -e -p "确认卸载？(输入 yes 确认): " confirm

    if [ "$confirm" != "yes" ]; then
        echo "已取消"
        break_end
        return 0
    fi

    echo ""
    echo "正在停止服务..."
    mac_openclaw_stop 2>/dev/null

    echo "正在卸载 OpenClaw..."
    npm uninstall -g openclaw 2>/dev/null

    echo ""
    read -e -p "是否同时删除配置目录 ${OPENCLAW_HOME_DIR}？(Y/N): " del_config
    case "$del_config" in
        [Yy])
            rm -rf "$OPENCLAW_HOME_DIR"
            echo -e "${gl_lv}✅ 配置目录已删除${gl_bai}"
            ;;
        *)
            # 只清理 PID 和日志
            rm -f "$OPENCLAW_PID_FILE" "$OPENCLAW_LOG_FILE"
            echo -e "${gl_zi}配置目录已保留，下次安装可复用${gl_bai}"
            ;;
    esac

    echo ""
    echo -e "${gl_lv}✅ OpenClaw 卸载完成${gl_bai}"

    break_end
}
```

**Step 2: 验证语法**

Run: `bash -n openclaw-deploy-mac.sh`

**Step 3: Commit**

```bash
git add openclaw-deploy-mac.sh
git commit -m "feat: add uninstall function with PID cleanup"
```

---

## Task 13: 主菜单与脚本入口

**Files:**
- Modify: `openclaw-deploy-mac.sh`

**对应 VPS 版:** `manage_openclaw()` 行 3305-3431, `ai_toolkit_main()` 行 4037-4077, 入口行 4082-4083
**Mac 适配:** 合并为单一菜单（无需 VPS 版的多服务主菜单）；去掉 root 检查，改为 macOS 检查；菜单 8 的 post-config 重启逻辑适配

**Step 1: 写入主菜单和入口**

```bash
#=============================================================================
# Mac 主菜单（对应 VPS 版 manage_openclaw 行 3305-3431）
#=============================================================================
mac_main_menu() {
    while true; do
        clear
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_kjlan}  OpenClaw Mac 本地部署工具 v${MAC_TOOLKIT_VERSION}${gl_bai}"
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""

        # 显示当前状态
        local status=$(mac_openclaw_check_status)
        local port=$(openclaw_get_port)

        case "$status" in
            "not_installed")
                echo -e "当前状态: ${gl_huang}⚠ 未安装${gl_bai}"
                ;;
            "running")
                echo -e "当前状态: ${gl_lv}✅ 运行中${gl_bai} (端口: ${port})"
                ;;
            "running_no_pid")
                echo -e "当前状态: ${gl_lv}✅ 运行中${gl_bai} (端口: ${port}, 无PID文件)"
                ;;
            "stopped")
                echo -e "当前状态: ${gl_hong}❌ 已停止${gl_bai}"
                ;;
        esac

        echo ""
        echo -e "${gl_kjlan}[部署与更新]${gl_bai}"
        echo "1. 一键部署（首次安装）"
        echo "2. 更新版本"
        echo ""
        echo -e "${gl_kjlan}[服务管理]${gl_bai}"
        echo "3. 查看状态"
        echo "4. 查看日志"
        echo "5. 启动服务"
        echo "6. 停止服务"
        echo "7. 重启服务"
        echo ""
        echo -e "${gl_kjlan}[配置管理]${gl_bai}"
        echo "8. 模型配置（完整配置/首次部署）"
        echo "9. 快速替换 API（保留现有设置）"
        echo "10. 频道管理（登录/配置）"
        echo "11. 查看当前配置"
        echo "12. 编辑配置文件"
        echo "13. 安全检查（doctor）"
        echo ""
        echo -e "${gl_hong}14. 卸载 OpenClaw${gl_bai}"
        echo ""
        echo "0. 退出"
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"

        read -e -p "请选择操作 [0-14]: " choice

        case $choice in
            1)  mac_openclaw_deploy ;;
            2)  mac_openclaw_update ;;
            3)  mac_openclaw_status ;;
            4)  mac_openclaw_logs ;;
            5)
                mac_openclaw_start
                break_end
                ;;
            6)
                mac_openclaw_stop
                break_end
                ;;
            7)
                mac_openclaw_restart
                break_end
                ;;
            8)
                openclaw_config_model
                echo ""
                # 模型配置后提示重启（Mac 版，对应 VPS 版行 3384-3401）
                local svc_status=$(mac_openclaw_check_status)
                if [ "$svc_status" = "running" ] || [ "$svc_status" = "running_no_pid" ]; then
                    read -e -p "是否重启服务使配置生效？(Y/N): " confirm
                    case "$confirm" in
                        [Yy])
                            mac_openclaw_restart
                            sleep 2
                            local new_status=$(mac_openclaw_check_status)
                            if [ "$new_status" = "running" ]; then
                                echo -e "${gl_lv}✅ 服务已重启${gl_bai}"
                            else
                                echo -e "${gl_hong}❌ 服务重启失败，查看日志: tail -50 ${OPENCLAW_LOG_FILE}${gl_bai}"
                            fi
                            ;;
                    esac
                else
                    echo -e "${gl_huang}⚠ 服务未运行，请先启动服务${gl_bai}"
                fi
                break_end
                ;;
            9)  openclaw_quick_api ;;
            10) openclaw_channels ;;
            11) openclaw_show_config ;;
            12) openclaw_edit_config ;;
            13) openclaw_doctor ;;
            14) mac_openclaw_uninstall ;;
            0)
                echo -e "${gl_lv}再见！${gl_bai}"
                exit 0
                ;;
            *)
                echo "无效选择"
                sleep 1
                ;;
        esac
    done
}

#=============================================================================
# 脚本入口
#=============================================================================
check_macos
mac_main_menu
```

**Step 2: 添加执行权限并验证语法**

Run: `chmod +x openclaw-deploy-mac.sh && bash -n openclaw-deploy-mac.sh`

**Step 3: Commit**

```bash
git add openclaw-deploy-mac.sh
git commit -m "feat: add main menu and script entry point"
```

---

## Task 14: 集成验证与文档

**Files:**
- Modify: `openclaw-deploy-mac.sh` (最终调整)
- Modify: `README.md` (添加 Mac 使用说明)

**Step 1: 完整语法检查**

Run: `bash -n openclaw-deploy-mac.sh`
Expected: 无输出

**Step 2: 检查所有 Mac 适配点**

逐项验证：
- [ ] 无 `systemctl` 残留: `grep -n 'systemctl' openclaw-deploy-mac.sh`（应为 0 结果）
- [ ] 无 `ss -lntp` 残留: `grep -n 'ss -lntp' openclaw-deploy-mac.sh`（应为 0 结果）
- [ ] 无 `journalctl` 残留: `grep -n 'journalctl' openclaw-deploy-mac.sh`（应为 0 结果）
- [ ] 无 Linux `sed -i` 用法: `grep -n "sed -i \"" openclaw-deploy-mac.sh`（应只有 `sed -i ''` 形式）
- [ ] 无 `/root/` 路径: `grep -n '/root/' openclaw-deploy-mac.sh`（应为 0 结果）
- [ ] 无 `apt-get\|yum\|dnf` 残留: `grep -n 'apt-get\|yum\|dnf' openclaw-deploy-mac.sh`（应为 0 结果）

**Step 3: 在 README.md 中添加 Mac 使用说明**

```markdown
## Mac 本地部署

```bash
# 下载脚本
curl -fsSL <script-url> -o openclaw-deploy-mac.sh
chmod +x openclaw-deploy-mac.sh

# 运行
bash openclaw-deploy-mac.sh
```

**Step 4: Final commit**

```bash
git add openclaw-deploy-mac.sh README.md
git commit -m "feat: complete Mac deploy script with integration verification"
```

---

## 函数来源对照表

| Mac 脚本函数名 | VPS 源函数 | VPS 行号 | 适配内容 |
|---|---|---|---|
| `check_macos()` | `check_root()` | 29-35 | root → macOS 检测 |
| `break_end()` | `break_end()` | 38-44 | 无变化 |
| `ensure_homebrew()` | 新增 | - | Mac 专有 |
| `mac_openclaw_install_nodejs()` | `openclaw_install_nodejs()` | 1540-1615 | nodesource → brew |
| `fix_npm_permissions()` | 新增 | - | Mac 专有 |
| `mac_openclaw_install_pkg()` | `openclaw_install_pkg()` | 1618-1633 | 增加权限修复 |
| `openclaw_get_port()` | `openclaw_get_port()` | 1518-1528 | 无变化 |
| `openclaw_config_model()` | `openclaw_config_model()` | 1636-2049 | 无变化（直接复制） |
| `mac_openclaw_check_port()` | `openclaw_check_port()` | 1531-1537 | ss → lsof |
| `mac_openclaw_check_status()` | `openclaw_check_status()` | 1505-1515 | systemctl → PID 三重检测 |
| `rotate_log_if_needed()` | 新增 | - | Mac 专有（>10MB 轮转） |
| `mac_openclaw_start()` | `openclaw_start()` | 2260-2272 | systemctl → nohup+PID+.env |
| `mac_openclaw_stop()` | `openclaw_stop()` | 2275-2286 | systemctl → 优雅 kill |
| `mac_openclaw_restart()` | `openclaw_restart()` | 2289-2317 | systemctl → PID+端口冲突 |
| `mac_openclaw_onboard()` | `openclaw_onboard()` | 2052-2100 | systemd 服务 → nohup |
| `mac_openclaw_deploy()` | `openclaw_deploy()` | 2103-2181 | 整合 Mac 适配 |
| `mac_openclaw_update()` | `openclaw_update()` | 2184-2225 | systemctl → PID |
| `mac_openclaw_status()` | `openclaw_status()` | 2228-2245 | systemctl → PID |
| `mac_openclaw_logs()` | `openclaw_logs()` | 2248-2257 | journalctl → tail |
| `openclaw_update_channel()` | `openclaw_update_channel()` | 2320-2366 | 无变化 |
| `openclaw_remove_channel()` | `openclaw_remove_channel()` | 2369-2410 | 无变化 |
| `openclaw_channels()` | `openclaw_channels()` | 2413-2742 | systemctl → PID（6处） |
| `openclaw_show_config()` | `openclaw_show_config()` | 2745-2829 | IP → localhost, 去 SSH 隧道 |
| `openclaw_edit_config()` | `openclaw_edit_config()` | 2832-2874 | editor → $EDITOR, systemctl → PID |
| `openclaw_quick_api()` | `openclaw_quick_api()` | 2877-3221 | sed -i → sed -i '', systemctl → PID |
| `openclaw_doctor()` | `openclaw_doctor()` | 3224-3249 | 无变化 |
| `mac_openclaw_uninstall()` | `openclaw_uninstall()` | 3252-3302 | systemd 清理 → PID 清理 |
| `mac_main_menu()` | `manage_openclaw()` | 3305-3431 | systemctl → PID, 合并入口 |

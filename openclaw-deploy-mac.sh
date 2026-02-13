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
            # 检测 shell 配置文件
            local shell_rc="${HOME}/.zshrc"
            if [[ "$SHELL" == */bash ]]; then
                shell_rc="${HOME}/.bash_profile"
            fi

            if [[ "$(uname -m)" == "arm64" ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
                # 写入 shell 配置
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
    if [[ "$SHELL" == */bash ]]; then
        shell_rc="${HOME}/.bash_profile"
    fi
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

# 启动服务（Mac 版）
mac_openclaw_start() {
    local port=$(openclaw_get_port)

    # 检查是否已在运行
    local status=$(mac_openclaw_check_status)
    if [ "$status" = "running" ] || [ "$status" = "running_no_pid" ]; then
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

#=============================================================================
# 模型配置（与 VPS 版一致，行 1636-2049，纯 bash + 文件写入，无平台依赖）
#=============================================================================

openclaw_config_model() {
    # 仅在独立调用时 clear（部署流程中由 mac_openclaw_deploy 已 clear）
    if [ "${OPENCLAW_DEPLOYING:-}" != "1" ]; then
        clear
    fi
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  OpenClaw 模型配置${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    # 步骤1: 选择 API 来源
    echo -e "${gl_kjlan}[步骤1] 选择你的 API 来源${gl_bai}"
    echo ""
    echo -e "${gl_lv}── 已验证可用的反代 ──${gl_bai}"
    echo "1. CRS 反代 (Claude)         — anthropic-messages 协议"
    echo "2. sub2api 反代 (Gemini)      — google-generative-ai 协议"
    echo "3. sub2api 反代 (GPT)         — openai-responses 协议"
    echo "4. sub2api Antigravity (Claude) — anthropic-messages 协议"
    echo ""
    echo -e "${gl_huang}── 通用配置 ──${gl_bai}"
    echo "5. Anthropic 直连反代（自建 Nginx/Caddy 反代）"
    echo "6. OpenAI 兼容中转（new-api / one-api / LiteLLM 等）"
    echo "7. OpenRouter"
    echo "8. Google Gemini 反代（其他 Gemini 代理）"
    echo ""
    echo -e "${gl_zi}── 官方直连 ──${gl_bai}"
    echo "9. Anthropic 官方 API Key"
    echo "10. Google Gemini 官方 API Key"
    echo "11. OpenAI 官方 API Key"
    echo ""
    read -e -p "请选择 [1-11]: " api_choice

    local api_type=""
    local base_url=""
    local provider_name="my-proxy"
    local need_base_url=true
    local need_api_key=true
    local preset_mode=""  # crs / sub2api-gemini / sub2api-gpt / sub2api-antigravity / 空=手动

    case "$api_choice" in
        1)
            # CRS 反代 (Claude) - 已验证
            preset_mode="crs"
            api_type="anthropic-messages"
            provider_name="crs-claude"
            echo ""
            echo -e "${gl_lv}已选择: CRS 反代 (Claude)${gl_bai}"
            echo -e "${gl_zi}协议: anthropic-messages | 只需输入 CRS 地址和 API Key${gl_bai}"
            echo ""
            echo -e "${gl_zi}地址格式示例: http://IP:端口/api${gl_bai}"
            echo -e "${gl_zi}Key 格式示例: cr_xxxx...${gl_bai}"
            ;;
        2)
            # sub2api 反代 (Gemini) - 已验证
            preset_mode="sub2api-gemini"
            api_type="google-generative-ai"
            provider_name="sub2api-gemini"
            echo ""
            echo -e "${gl_lv}已选择: sub2api 反代 (Gemini)${gl_bai}"
            echo -e "${gl_zi}协议: google-generative-ai | 只需输入 sub2api 地址和 API Key${gl_bai}"
            echo ""
            echo -e "${gl_zi}地址格式示例: https://你的sub2api域名${gl_bai}"
            echo -e "${gl_zi}Key 格式示例: sk-xxxx...（Gemini 专用 Key）${gl_bai}"
            echo -e "${gl_huang}注意: sub2api 的 Claude Key 因凭证限制无法用于 OpenClaw，只有 Gemini Key 可用${gl_bai}"
            ;;
        3)
            # sub2api 反代 (GPT) - 已验证
            preset_mode="sub2api-gpt"
            api_type="openai-responses"
            provider_name="sub2api-gpt"
            echo ""
            echo -e "${gl_lv}已选择: sub2api 反代 (GPT)${gl_bai}"
            echo -e "${gl_zi}协议: openai-responses | 只需输入 sub2api 地址和 API Key${gl_bai}"
            echo ""
            echo -e "${gl_zi}地址格式示例: https://你的sub2api域名${gl_bai}"
            echo -e "${gl_zi}Key 格式示例: sk-xxxx...（GPT 专用 Key）${gl_bai}"
            ;;
        4)
            # sub2api Antigravity (Claude) - 已验证
            preset_mode="sub2api-antigravity"
            api_type="anthropic-messages"
            provider_name="sub2api-antigravity"
            echo ""
            echo -e "${gl_lv}已选择: sub2api Antigravity (Claude)${gl_bai}"
            echo -e "${gl_zi}协议: anthropic-messages | 支持 tools，OpenClaw 完全兼容${gl_bai}"
            echo ""
            echo -e "${gl_zi}地址格式示例: https://你的sub2api域名/antigravity${gl_bai}"
            echo -e "${gl_zi}Key 格式示例: sk-xxxx...（Antigravity 专用 Key）${gl_bai}"
            echo -e "${gl_huang}注意: 高峰期偶尔返回 503，重试即可；账户池较小${gl_bai}"
            ;;
        5)
            api_type="anthropic-messages"
            echo ""
            echo -e "${gl_zi}提示: 反代地址一般不需要 /v1 后缀${gl_bai}"
            echo -e "${gl_huang}注意: 使用 Claude Code 凭证的反代（如 sub2api Claude）无法用于 OpenClaw${gl_bai}"
            ;;
        6)
            api_type="openai-completions"
            echo ""
            echo -e "${gl_zi}提示: 中转地址一般需要 /v1 后缀${gl_bai}"
            ;;
        7)
            api_type="openai-completions"
            base_url="https://openrouter.ai/api/v1"
            provider_name="openrouter"
            need_base_url=false
            echo ""
            echo -e "${gl_lv}已预填 OpenRouter 地址: ${base_url}${gl_bai}"
            ;;
        8)
            api_type="google-generative-ai"
            echo ""
            echo -e "${gl_zi}提示: Gemini 反代地址会自动添加 /v1beta 后缀${gl_bai}"
            ;;
        9)
            api_type="anthropic-messages"
            base_url="https://api.anthropic.com"
            provider_name="anthropic"
            need_base_url=false
            echo ""
            echo -e "${gl_lv}使用 Anthropic 官方 API${gl_bai}"
            ;;
        10)
            api_type="google-generative-ai"
            base_url="https://generativelanguage.googleapis.com/v1beta"
            provider_name="google"
            need_base_url=false
            echo ""
            echo -e "${gl_lv}使用 Google Gemini 官方 API${gl_bai}"
            ;;
        11)
            api_type="openai-responses"
            base_url="https://api.openai.com/v1"
            provider_name="openai"
            need_base_url=false
            echo ""
            echo -e "${gl_lv}使用 OpenAI 官方 API${gl_bai}"
            ;;
        *)
            echo -e "${gl_hong}无效选择${gl_bai}"
            break_end
            return 1
            ;;
    esac

    # 步骤2: 输入反代地址
    if [ "$need_base_url" = true ]; then
        echo ""
        echo -e "${gl_kjlan}[步骤2] 输入反代地址${gl_bai}"
        if [ "$preset_mode" = "crs" ]; then
            echo -e "${gl_zi}示例: http://IP:端口/api（CRS 默认格式）${gl_bai}"
        elif [ "$preset_mode" = "sub2api-gemini" ]; then
            echo -e "${gl_zi}示例: https://你的sub2api域名（/v1beta 会自动添加）${gl_bai}"
        elif [ "$preset_mode" = "sub2api-gpt" ]; then
            echo -e "${gl_zi}示例: https://你的sub2api域名（/v1 会自动添加）${gl_bai}"
        elif [ "$preset_mode" = "sub2api-antigravity" ]; then
            echo -e "${gl_zi}示例: https://你的sub2api域名/antigravity（路径需包含 /antigravity）${gl_bai}"
        elif [ "$api_type" = "google-generative-ai" ]; then
            echo -e "${gl_zi}示例: https://your-proxy.com（/v1beta 会自动添加）${gl_bai}"
        else
            echo -e "${gl_zi}示例: https://your-proxy.com 或 https://your-proxy.com/v1${gl_bai}"
        fi
        echo ""
        read -e -p "反代地址: " base_url
        if [ -z "$base_url" ]; then
            echo -e "${gl_hong}❌ 反代地址不能为空${gl_bai}"
            break_end
            return 1
        fi
        # 去除末尾的 /
        base_url="${base_url%/}"
        # 自动添加 API 路径后缀
        if [ "$api_type" = "google-generative-ai" ]; then
            if [[ ! "$base_url" =~ /v1beta$ ]] && [[ ! "$base_url" =~ /v1$ ]]; then
                base_url="${base_url}/v1beta"
                echo -e "${gl_lv}已自动添加后缀: ${base_url}${gl_bai}"
            fi
        elif [ "$preset_mode" = "sub2api-gpt" ]; then
            if [[ ! "$base_url" =~ /v1$ ]]; then
                base_url="${base_url}/v1"
                echo -e "${gl_lv}已自动添加后缀: ${base_url}${gl_bai}"
            fi
        fi
    fi

    # 步骤3: 输入 API Key
    echo ""
    echo -e "${gl_kjlan}[步骤3] 输入 API Key${gl_bai}"
    if [ "$preset_mode" = "crs" ]; then
        echo -e "${gl_zi}CRS Key 格式: cr_xxxx...${gl_bai}"
    elif [ "$preset_mode" = "sub2api-gemini" ]; then
        echo -e "${gl_zi}sub2api Gemini Key 格式: sk-xxxx...${gl_bai}"
    elif [ "$preset_mode" = "sub2api-gpt" ]; then
        echo -e "${gl_zi}sub2api GPT Key 格式: sk-xxxx...${gl_bai}"
    elif [ "$preset_mode" = "sub2api-antigravity" ]; then
        echo -e "${gl_zi}sub2api Antigravity Key 格式: sk-xxxx...${gl_bai}"
    fi
    echo ""
    read -e -p "API Key: " api_key
    if [ -z "$api_key" ]; then
        echo -e "${gl_hong}❌ API Key 不能为空${gl_bai}"
        break_end
        return 1
    fi

    # 步骤4: 选择模型
    echo ""
    echo -e "${gl_kjlan}[步骤4] 选择主力模型${gl_bai}"
    echo ""

    local model_id=""
    local model_name=""
    local model_reasoning="false"
    local model_input='["text"]'
    local model_cost_input="3"
    local model_cost_output="15"
    local model_cost_cache_read="0.3"
    local model_cost_cache_write="3.75"
    local model_context="200000"
    local model_max_tokens="16384"

    if [ "$preset_mode" = "sub2api-antigravity" ]; then
        echo "1. claude-sonnet-4-5 (推荐)"
        echo "2. claude-sonnet-4-5-thinking (扩展思考)"
        echo "3. claude-opus-4-5-thinking (最强思考)"
        echo "4. 自定义模型 ID"
        echo ""
        read -e -p "请选择 [1-4]: " model_choice
        case "$model_choice" in
            1) model_id="claude-sonnet-4-5"; model_name="Claude Sonnet 4.5" ;;
            2) model_id="claude-sonnet-4-5-thinking"; model_name="Claude Sonnet 4.5 Thinking"; model_reasoning="true"; model_input='["text", "image"]' ;;
            3) model_id="claude-opus-4-5-thinking"; model_name="Claude Opus 4.5 Thinking"; model_reasoning="true"; model_input='["text", "image"]'; model_cost_input="15"; model_cost_output="75"; model_cost_cache_read="1.5"; model_cost_cache_write="18.75"; model_max_tokens="32768" ;;
            4)
                read -e -p "输入模型 ID: " model_id
                read -e -p "输入模型显示名称: " model_name
                ;;
            *) model_id="claude-sonnet-4-5"; model_name="Claude Sonnet 4.5" ;;
        esac
    elif [ "$api_type" = "anthropic-messages" ]; then
        echo "1. claude-opus-4-6 (Opus 4.6 最强)"
        echo "2. claude-sonnet-4-5 (Sonnet 4.5 均衡)"
        echo "3. claude-haiku-4-5 (Haiku 4.5 快速)"
        echo "4. 自定义模型 ID"
        echo ""
        read -e -p "请选择 [1-4]: " model_choice
        case "$model_choice" in
            1) model_id="claude-opus-4-6"; model_name="Claude Opus 4.6"; model_reasoning="true"; model_input='["text", "image"]'; model_cost_input="15"; model_cost_output="75"; model_cost_cache_read="1.5"; model_cost_cache_write="18.75"; model_max_tokens="32768" ;;
            2) model_id="claude-sonnet-4-5"; model_name="Claude Sonnet 4.5" ;;
            3) model_id="claude-haiku-4-5"; model_name="Claude Haiku 4.5"; model_cost_input="0.8"; model_cost_output="4"; model_cost_cache_read="0.08"; model_cost_cache_write="1" ;;
            4)
                read -e -p "输入模型 ID: " model_id
                read -e -p "输入模型显示名称: " model_name
                ;;
            *) model_id="claude-sonnet-4-5"; model_name="Claude Sonnet 4.5" ;;
        esac
    elif [ "$api_type" = "google-generative-ai" ]; then
        echo "1. gemini-3-pro-preview (最新旗舰)"
        echo "2. gemini-3-flash-preview (最新快速)"
        echo "3. gemini-2.5-pro (推理增强)"
        echo "4. gemini-2.5-flash (快速均衡)"
        echo "5. 自定义模型 ID"
        echo ""
        read -e -p "请选择 [1-5]: " model_choice
        case "$model_choice" in
            1) model_id="gemini-3-pro-preview"; model_name="Gemini 3 Pro Preview"; model_reasoning="true"; model_input='["text", "image"]'; model_cost_input="2.5"; model_cost_output="15"; model_cost_cache_read="0.625"; model_cost_cache_write="7.5"; model_context="1000000"; model_max_tokens="65536" ;;
            2) model_id="gemini-3-flash-preview"; model_name="Gemini 3 Flash Preview"; model_reasoning="true"; model_input='["text", "image"]'; model_cost_input="0.15"; model_cost_output="0.6"; model_cost_cache_read="0.0375"; model_cost_cache_write="1"; model_context="1000000"; model_max_tokens="65536" ;;
            3) model_id="gemini-2.5-pro"; model_name="Gemini 2.5 Pro"; model_reasoning="true"; model_input='["text", "image"]'; model_cost_input="1.25"; model_cost_output="10"; model_cost_cache_read="0.315"; model_cost_cache_write="4.5"; model_context="1000000"; model_max_tokens="65536" ;;
            4) model_id="gemini-2.5-flash"; model_name="Gemini 2.5 Flash"; model_reasoning="true"; model_input='["text", "image"]'; model_cost_input="0.15"; model_cost_output="0.6"; model_cost_cache_read="0.0375"; model_cost_cache_write="1"; model_context="1000000"; model_max_tokens="65536" ;;
            5)
                read -e -p "输入模型 ID: " model_id
                read -e -p "输入模型显示名称: " model_name
                model_reasoning="true"; model_input='["text", "image"]'; model_context="1000000"; model_max_tokens="65536"
                ;;
            *) model_id="gemini-3-pro-preview"; model_name="Gemini 3 Pro Preview"; model_reasoning="true"; model_input='["text", "image"]'; model_cost_input="2.5"; model_cost_output="15"; model_cost_cache_read="0.625"; model_cost_cache_write="7.5"; model_context="1000000"; model_max_tokens="65536" ;;
        esac
    elif [ "$api_type" = "openai-responses" ]; then
        echo "1. gpt-5.3 (最新旗舰)"
        echo "2. gpt-5.3-codex (Codex 最强)"
        echo "3. gpt-5.2"
        echo "4. gpt-5.2-codex"
        echo "5. gpt-5.1"
        echo "6. gpt-5.1-codex"
        echo "7. gpt-5.1-codex-max"
        echo "8. 自定义模型 ID"
        echo ""
        read -e -p "请选择 [1-8]: " model_choice
        case "$model_choice" in
            1) model_id="gpt-5.3"; model_name="GPT 5.3"; model_reasoning="true"; model_input='["text", "image"]'; model_cost_input="2"; model_cost_output="8"; model_cost_cache_read="0.5"; model_cost_cache_write="2"; model_max_tokens="32768" ;;
            2) model_id="gpt-5.3-codex"; model_name="GPT 5.3 Codex"; model_reasoning="true"; model_input='["text", "image"]'; model_cost_input="2"; model_cost_output="8"; model_cost_cache_read="0.5"; model_cost_cache_write="2"; model_max_tokens="32768" ;;
            3) model_id="gpt-5.2"; model_name="GPT 5.2"; model_reasoning="true"; model_input='["text", "image"]'; model_cost_input="2"; model_cost_output="8"; model_cost_cache_read="0.5"; model_cost_cache_write="2"; model_max_tokens="32768" ;;
            4) model_id="gpt-5.2-codex"; model_name="GPT 5.2 Codex"; model_reasoning="true"; model_input='["text", "image"]'; model_cost_input="2"; model_cost_output="8"; model_cost_cache_read="0.5"; model_cost_cache_write="2"; model_max_tokens="32768" ;;
            5) model_id="gpt-5.1"; model_name="GPT 5.1"; model_reasoning="true"; model_input='["text", "image"]'; model_cost_input="2"; model_cost_output="8"; model_cost_cache_read="0.5"; model_cost_cache_write="2"; model_max_tokens="32768" ;;
            6) model_id="gpt-5.1-codex"; model_name="GPT 5.1 Codex"; model_reasoning="true"; model_input='["text", "image"]'; model_cost_input="2"; model_cost_output="8"; model_cost_cache_read="0.5"; model_cost_cache_write="2"; model_max_tokens="32768" ;;
            7) model_id="gpt-5.1-codex-max"; model_name="GPT 5.1 Codex Max"; model_reasoning="true"; model_input='["text", "image"]'; model_cost_input="2"; model_cost_output="8"; model_cost_cache_read="0.5"; model_cost_cache_write="2"; model_max_tokens="32768" ;;
            8)
                read -e -p "输入模型 ID: " model_id
                read -e -p "输入模型显示名称: " model_name
                model_reasoning="true"; model_input='["text", "image"]'; model_max_tokens="32768"
                ;;
            *) model_id="gpt-5.3"; model_name="GPT 5.3"; model_reasoning="true"; model_input='["text", "image"]'; model_cost_input="2"; model_cost_output="8"; model_cost_cache_read="0.5"; model_cost_cache_write="2"; model_max_tokens="32768" ;;
        esac
    elif [ "$api_type" = "openai-completions" ]; then
        echo "1. claude-opus-4-6 (通过中转)"
        echo "2. claude-sonnet-4-5 (通过中转)"
        echo "3. gpt-4o"
        echo "4. gpt-4o-mini"
        echo "5. 自定义模型 ID"
        echo ""
        read -e -p "请选择 [1-5]: " model_choice
        case "$model_choice" in
            1) model_id="claude-opus-4-6"; model_name="Claude Opus 4.6"; model_reasoning="true"; model_input='["text", "image"]'; model_cost_input="15"; model_cost_output="75"; model_cost_cache_read="1.5"; model_cost_cache_write="18.75"; model_max_tokens="32768" ;;
            2) model_id="claude-sonnet-4-5"; model_name="Claude Sonnet 4.5" ;;
            3) model_id="gpt-4o"; model_name="GPT-4o"; model_input='["text", "image"]'; model_cost_input="2.5"; model_cost_output="10"; model_cost_cache_read="1.25"; model_cost_cache_write="2.5"; model_context="128000"; model_max_tokens="16384" ;;
            4) model_id="gpt-4o-mini"; model_name="GPT-4o Mini"; model_input='["text", "image"]'; model_cost_input="0.15"; model_cost_output="0.6"; model_cost_cache_read="0.075"; model_cost_cache_write="0.15"; model_context="128000"; model_max_tokens="16384" ;;
            5)
                read -e -p "输入模型 ID: " model_id
                read -e -p "输入模型显示名称: " model_name
                ;;
            *) model_id="claude-sonnet-4-5"; model_name="Claude Sonnet 4.5" ;;
        esac
    fi

    if [ -z "$model_id" ]; then
        echo -e "${gl_hong}❌ 模型 ID 不能为空${gl_bai}"
        break_end
        return 1
    fi

    # 步骤5: 选择端口
    echo ""
    echo -e "${gl_kjlan}[步骤5] 设置网关端口${gl_bai}"
    local port="$OPENCLAW_DEFAULT_PORT"
    read -e -p "网关端口 [${OPENCLAW_DEFAULT_PORT}]: " input_port
    if [ -n "$input_port" ]; then
        port="$input_port"
    fi

    # 生成配置
    echo ""
    echo -e "${gl_kjlan}正在生成配置...${gl_bai}"

    mkdir -p "$OPENCLAW_HOME_DIR"

    # 生成网关 token
    local gateway_token=$(openssl rand -hex 16 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')

    # 写入环境变量
    cat > "$OPENCLAW_ENV_FILE" <<EOF
# OpenClaw 环境变量 - 由部署脚本自动生成
OPENCLAW_API_KEY=${api_key}
OPENCLAW_GATEWAY_TOKEN=${gateway_token}
EOF
    chmod 600 "$OPENCLAW_ENV_FILE"

    # 生成 openclaw.json 配置（JSON5 格式）
    cat > "$OPENCLAW_CONFIG_FILE" <<EOF
// OpenClaw 配置 - 由部署脚本自动生成
// 文档: https://docs.openclaw.ai/gateway/configuration
{
  // 网关设置
  gateway: {
    port: ${port},
    mode: "local",
    auth: {
      token: "${gateway_token}"
    }
  },

  // 模型配置
  models: {
    mode: "merge",
    providers: {
      "${provider_name}": {
        baseUrl: "${base_url}",
        apiKey: "\${OPENCLAW_API_KEY}",
        api: "${api_type}",
        models: [
          { id: "${model_id}", name: "${model_name}", reasoning: ${model_reasoning}, input: ${model_input}, cost: { input: ${model_cost_input}, output: ${model_cost_output}, cacheRead: ${model_cost_cache_read}, cacheWrite: ${model_cost_cache_write} }, contextWindow: ${model_context}, maxTokens: ${model_max_tokens} }
        ]
      }
    }
  },

  // Agent 默认配置
  agents: {
    defaults: {
      model: {
        primary: "${provider_name}/${model_id}"
      }
    }
  }
}
EOF
    chmod 600 "$OPENCLAW_CONFIG_FILE"
    chmod 700 "$OPENCLAW_HOME_DIR"

    echo -e "${gl_lv}✅ 配置文件已生成${gl_bai}"
    echo ""
    echo -e "${gl_zi}配置文件: ${OPENCLAW_CONFIG_FILE}${gl_bai}"
    echo -e "${gl_zi}环境变量: ${OPENCLAW_ENV_FILE}${gl_bai}"
    echo ""

    # 显示配置摘要
    echo -e "${gl_kjlan}━━━ 配置摘要 ━━━${gl_bai}"
    if [ -n "$preset_mode" ]; then
        echo -e "配置预设:   ${gl_lv}${preset_mode}（已验证可用）${gl_bai}"
    fi
    echo -e "API 类型:   ${gl_huang}${api_type}${gl_bai}"
    echo -e "反代地址:   ${gl_huang}${base_url}${gl_bai}"
    echo -e "主力模型:   ${gl_huang}${provider_name}/${model_id}${gl_bai}"
    echo -e "模型名称:   ${gl_huang}${model_name}${gl_bai}"
    echo -e "网关端口:   ${gl_huang}${port}${gl_bai}"
    echo -e "网关Token:  ${gl_huang}${gateway_token}${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━${gl_bai}"

    return 0
}

#=============================================================================
# Task 7: Onboard 初始化与一键部署编排
#=============================================================================

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
    OPENCLAW_DEPLOYING=1 openclaw_config_model || { break_end; return 1; }
    echo ""

    # 步骤4: 初始化并启动
    mac_openclaw_onboard || { break_end; return 1; }

    # 部署完成信息（Mac 版，去掉 SSH 隧道提示）
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

#=============================================================================
# Task 8: 更新、状态查看、日志查看
#=============================================================================

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

#=============================================================================
# Task 9: 快速替换 API（Mac 版，对应 VPS 版行 2877-3221）
# 适配: sed -i → sed -i '', systemctl → PID
#=============================================================================

openclaw_quick_api() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  快速替换 API（保留端口/频道等现有设置）${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    if ! command -v openclaw &>/dev/null; then
        echo -e "${gl_hong}❌ OpenClaw 未安装${gl_bai}"
        break_end
        return 1
    fi

    if [ ! -f "$OPENCLAW_CONFIG_FILE" ]; then
        echo -e "${gl_hong}❌ 配置文件不存在，请先执行「一键部署」${gl_bai}"
        break_end
        return 1
    fi

    # 显示当前 API 配置
    echo -e "${gl_lv}── 当前 API 配置 ──${gl_bai}"
    node -e "
        const fs = require('fs');
        const content = fs.readFileSync('${OPENCLAW_CONFIG_FILE}', 'utf-8');
        try {
            const config = new Function('return (' + content + ')')();
            const providers = config.models && config.models.providers || {};
            const keys = Object.keys(providers);
            if (keys.length === 0) { console.log('  暂无 API 配置'); }
            for (const name of keys) {
                const p = providers[name];
                console.log('  Provider:  ' + name);
                console.log('  API 类型:  ' + (p.api || 'unknown'));
                console.log('  地址:      ' + (p.baseUrl || 'unknown'));
                const models = p.models || [];
                if (models.length > 0) {
                    console.log('  模型:      ' + models.map(m => m.id).join(', '));
                }
            }
        } catch(e) { console.log('  无法解析当前配置'); }
    " 2>/dev/null || echo "  无法读取当前配置"
    echo ""

    # 选择新的 API
    echo -e "${gl_huang}选择要配置的 API:${gl_bai}"
    echo ""
    echo -e "${gl_lv}── 已验证可用的反代 ──${gl_bai}"
    echo "1. CRS 反代 (Claude)         — anthropic-messages"
    echo "2. sub2api 反代 (Gemini)      — google-generative-ai"
    echo "3. sub2api 反代 (GPT)         — openai-responses"
    echo "4. sub2api Antigravity (Claude) — anthropic-messages"
    echo ""
    echo -e "${gl_huang}── 通用配置 ──${gl_bai}"
    echo "5. 自定义 Anthropic 反代"
    echo "6. 自定义 OpenAI 兼容"
    echo ""

    read -e -p "请选择 [1-6]: " api_choice

    local api_type="" provider_name="" preset_mode=""
    local base_url="" api_key="" model_id="" model_name=""
    local model_reasoning="false" model_input='["text"]' model_cost_input="3" model_cost_output="15"
    local model_cost_cache_read="0.3" model_cost_cache_write="3.75"
    local model_context="200000" model_max_tokens="16384"

    case $api_choice in
        1)
            preset_mode="crs"
            api_type="anthropic-messages"
            provider_name="crs-claude"
            echo ""
            echo -e "${gl_lv}已选择: CRS 反代 (Claude)${gl_bai}"
            echo -e "${gl_zi}地址格式: http://IP:端口/api${gl_bai}"
            ;;
        2)
            preset_mode="sub2api-gemini"
            api_type="google-generative-ai"
            provider_name="sub2api-gemini"
            echo ""
            echo -e "${gl_lv}已选择: sub2api 反代 (Gemini)${gl_bai}"
            echo -e "${gl_zi}地址格式: https://你的sub2api域名${gl_bai}"
            ;;
        3)
            preset_mode="sub2api-gpt"
            api_type="openai-responses"
            provider_name="sub2api-gpt"
            echo ""
            echo -e "${gl_lv}已选择: sub2api 反代 (GPT)${gl_bai}"
            echo -e "${gl_zi}地址格式: https://你的sub2api域名${gl_bai}"
            ;;
        4)
            preset_mode="sub2api-antigravity"
            api_type="anthropic-messages"
            provider_name="sub2api-antigravity"
            echo ""
            echo -e "${gl_lv}已选择: sub2api Antigravity (Claude)${gl_bai}"
            echo -e "${gl_zi}地址格式: https://你的sub2api域名/antigravity${gl_bai}"
            echo -e "${gl_huang}注意: 高峰期偶尔返回 503，重试即可${gl_bai}"
            ;;
        5)
            api_type="anthropic-messages"
            provider_name="custom-anthropic"
            echo ""
            echo -e "${gl_zi}地址格式: https://your-proxy.com${gl_bai}"
            ;;
        6)
            api_type="openai-completions"
            provider_name="custom-openai"
            echo ""
            echo -e "${gl_zi}地址格式: https://your-proxy.com/v1${gl_bai}"
            ;;
        *)
            echo "无效选择"
            break_end
            return
            ;;
    esac

    # 输入地址
    echo ""
    read -e -p "反代地址: " base_url
    if [ -z "$base_url" ]; then
        echo -e "${gl_hong}❌ 地址不能为空${gl_bai}"
        break_end
        return
    fi
    base_url="${base_url%/}"

    # 自动添加后缀
    if [ "$api_type" = "google-generative-ai" ]; then
        if [[ ! "$base_url" =~ /v1beta$ ]] && [[ ! "$base_url" =~ /v1$ ]]; then
            base_url="${base_url}/v1beta"
            echo -e "${gl_lv}已自动添加后缀: ${base_url}${gl_bai}"
        fi
    elif [ "$preset_mode" = "sub2api-gpt" ]; then
        if [[ ! "$base_url" =~ /v1$ ]]; then
            base_url="${base_url}/v1"
            echo -e "${gl_lv}已自动添加后缀: ${base_url}${gl_bai}"
        fi
    fi

    # 输入 Key
    echo ""
    read -e -p "API Key: " api_key
    if [ -z "$api_key" ]; then
        echo -e "${gl_hong}❌ Key 不能为空${gl_bai}"
        break_end
        return
    fi

    # 快速模型选择
    echo ""
    echo -e "${gl_kjlan}选择模型:${gl_bai}"
    if [ "$preset_mode" = "crs" ]; then
        echo "1. claude-opus-4-6 (推荐)"
        echo "2. claude-sonnet-4-5"
        echo "3. claude-haiku-4-5"
        echo "4. 自定义"
        read -e -p "请选择 [1-4]: " m_choice
        case $m_choice in
            1) model_id="claude-opus-4-6"; model_name="Claude Opus 4.6" ;;
            2) model_id="claude-sonnet-4-5"; model_name="Claude Sonnet 4.5" ;;
            3) model_id="claude-haiku-4-5"; model_name="Claude Haiku 4.5" ;;
            4) read -e -p "模型 ID: " model_id; model_name="$model_id" ;;
            *) model_id="claude-opus-4-6"; model_name="Claude Opus 4.6" ;;
        esac
    elif [ "$preset_mode" = "sub2api-antigravity" ]; then
        echo "1. claude-sonnet-4-5 (推荐)"
        echo "2. claude-sonnet-4-5-thinking (扩展思考)"
        echo "3. claude-opus-4-5-thinking (最强思考)"
        echo "4. 自定义"
        read -e -p "请选择 [1-4]: " m_choice
        case $m_choice in
            1) model_id="claude-sonnet-4-5"; model_name="Claude Sonnet 4.5" ;;
            2) model_id="claude-sonnet-4-5-thinking"; model_name="Claude Sonnet 4.5 Thinking" ;;
            3) model_id="claude-opus-4-5-thinking"; model_name="Claude Opus 4.5 Thinking" ;;
            4) read -e -p "模型 ID: " model_id; model_name="$model_id" ;;
            *) model_id="claude-sonnet-4-5"; model_name="Claude Sonnet 4.5" ;;
        esac
    elif [ "$preset_mode" = "sub2api-gemini" ]; then
        echo "1. gemini-3-pro-preview (推荐)"
        echo "2. gemini-3-flash-preview"
        echo "3. gemini-2.5-pro"
        echo "4. gemini-2.5-flash"
        echo "5. 自定义"
        read -e -p "请选择 [1-5]: " m_choice
        case $m_choice in
            1) model_id="gemini-3-pro-preview"; model_name="Gemini 3 Pro Preview" ;;
            2) model_id="gemini-3-flash-preview"; model_name="Gemini 3 Flash Preview" ;;
            3) model_id="gemini-2.5-pro"; model_name="Gemini 2.5 Pro" ;;
            4) model_id="gemini-2.5-flash"; model_name="Gemini 2.5 Flash" ;;
            5) read -e -p "模型 ID: " model_id; model_name="$model_id" ;;
            *) model_id="gemini-3-pro-preview"; model_name="Gemini 3 Pro Preview" ;;
        esac
    elif [ "$preset_mode" = "sub2api-gpt" ]; then
        echo "1. gpt-5.3 (推荐)"
        echo "2. gpt-5.3-codex"
        echo "3. gpt-5.2"
        echo "4. gpt-5.2-codex"
        echo "5. gpt-5.1"
        echo "6. gpt-5.1-codex"
        echo "7. gpt-5.1-codex-max"
        echo "8. 自定义"
        read -e -p "请选择 [1-8]: " m_choice
        case $m_choice in
            1) model_id="gpt-5.3"; model_name="GPT 5.3" ;;
            2) model_id="gpt-5.3-codex"; model_name="GPT 5.3 Codex" ;;
            3) model_id="gpt-5.2"; model_name="GPT 5.2" ;;
            4) model_id="gpt-5.2-codex"; model_name="GPT 5.2 Codex" ;;
            5) model_id="gpt-5.1"; model_name="GPT 5.1" ;;
            6) model_id="gpt-5.1-codex"; model_name="GPT 5.1 Codex" ;;
            7) model_id="gpt-5.1-codex-max"; model_name="GPT 5.1 Codex Max" ;;
            8) read -e -p "模型 ID: " model_id; model_name="$model_id" ;;
            *) model_id="gpt-5.3"; model_name="GPT 5.3" ;;
        esac
    else
        read -e -p "模型 ID: " model_id
        model_name="$model_id"
    fi

    if [ -z "$model_id" ]; then
        echo -e "${gl_hong}❌ 模型不能为空${gl_bai}"
        break_end
        return
    fi

    echo ""
    echo -e "${gl_kjlan}━━━ 确认配置 ━━━${gl_bai}"
    echo -e "API 类型:   ${gl_huang}${api_type}${gl_bai}"
    echo -e "反代地址:   ${gl_huang}${base_url}${gl_bai}"
    echo -e "模型:       ${gl_huang}${model_id}${gl_bai}"
    echo ""

    read -e -p "确认替换 API 配置？(Y/N): " confirm
    if [[ ! "$confirm" =~ [Yy] ]]; then
        echo "已取消"
        break_end
        return
    fi

    # 写入新 provider 数据到临时 JSON 文件
    local tmp_json=$(mktemp /tmp/openclaw_api_XXXXXX.json)
    cat > "$tmp_json" <<APIJSON
{
    "providers": {
        "${provider_name}": {
            "baseUrl": "${base_url}",
            "apiKey": "\${OPENCLAW_API_KEY}",
            "api": "${api_type}",
            "models": [
                {
                    "id": "${model_id}",
                    "name": "${model_name}",
                    "reasoning": ${model_reasoning},
                    "input": ${model_input},
                    "cost": { "input": ${model_cost_input}, "output": ${model_cost_output}, "cacheRead": ${model_cost_cache_read}, "cacheWrite": ${model_cost_cache_write} },
                    "contextWindow": ${model_context},
                    "maxTokens": ${model_max_tokens}
                }
            ]
        }
    },
    "primaryModel": "${provider_name}/${model_id}"
}
APIJSON

    # 用 Node.js 合并配置（只替换 models + agents.defaults.model，保留其他一切）
    echo ""
    echo "正在更新配置..."
    node -e "
        const fs = require('fs');
        const configPath = '${OPENCLAW_CONFIG_FILE}';
        const newDataPath = '${tmp_json}';

        // 读取现有配置（JSON5: 用 Function 解析，JS 引擎原生支持注释）
        const content = fs.readFileSync(configPath, 'utf-8');
        let config;
        try {
            config = new Function('return (' + content + ')')();
        } catch(e) {
            console.error('❌ 无法解析现有配置: ' + e.message);
            process.exit(1);
        }

        // 读取新 provider 数据
        const newData = JSON.parse(fs.readFileSync(newDataPath, 'utf-8'));

        // 只替换 models.providers 和 agents.defaults.model
        config.models = config.models || {};
        config.models.mode = 'merge';
        config.models.providers = newData.providers;

        config.agents = config.agents || {};
        config.agents.defaults = config.agents.defaults || {};
        config.agents.defaults.model = { primary: newData.primaryModel };

        // 写回（保留 gateway/channels 等所有其他配置）
        const header = '// OpenClaw 配置 - API 由脚本快速配置\n// 文档: https://docs.openclaw.ai/gateway/configuration\n';
        fs.writeFileSync(configPath, header + JSON.stringify(config, null, 2) + '\n');
        console.log('✅ 配置文件已更新');
    " 2>&1

    local node_exit=$?
    rm -f "$tmp_json"

    if [ $node_exit -ne 0 ]; then
        echo -e "${gl_hong}❌ 配置更新失败${gl_bai}"
        break_end
        return
    fi

    # 更新 .env 中的 API Key（Mac 版: sed -i ''）
    if [ -f "$OPENCLAW_ENV_FILE" ]; then
        sed -i '' "s|^OPENCLAW_API_KEY=.*|OPENCLAW_API_KEY=${api_key}|" "$OPENCLAW_ENV_FILE"
        echo "✅ API Key 已更新"
    else
        mkdir -p "$OPENCLAW_HOME_DIR"
        echo "OPENCLAW_API_KEY=${api_key}" > "$OPENCLAW_ENV_FILE"
        chmod 600 "$OPENCLAW_ENV_FILE"
        echo "✅ 环境变量文件已创建"
    fi

    # 重启服务（Mac 版: PID 模式）
    local svc_status=$(mac_openclaw_check_status)
    if [ "$svc_status" = "running" ] || [ "$svc_status" = "running_no_pid" ]; then
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

    echo ""
    echo -e "${gl_kjlan}━━━ 替换完成 ━━━${gl_bai}"
    echo -e "API 类型:   ${gl_huang}${api_type}${gl_bai}"
    echo -e "反代地址:   ${gl_huang}${base_url}${gl_bai}"
    echo -e "主力模型:   ${gl_huang}${provider_name}/${model_id}${gl_bai}"
    echo ""
    echo -e "${gl_zi}原有的端口、频道、网关 Token 等设置均已保留${gl_bai}"

    break_end
}

#=============================================================================
# Task 10: 频道管理完整子系统
# 对应 VPS 版行 2320-2742
# 适配: systemctl → PID, journalctl → tail
#=============================================================================

# 更新频道配置（与 VPS 版一致，纯 Node.js，无平台依赖）
openclaw_update_channel() {
    local channel_name="$1"
    local channel_config_json="$2"

    if [ ! -f "$OPENCLAW_CONFIG_FILE" ]; then
        echo -e "${gl_hong}❌ 配置文件不存在，请先部署 OpenClaw${gl_bai}"
        return 1
    fi

    local tmp_channel=$(mktemp)
    local tmp_script=$(mktemp)
    echo "$channel_config_json" > "$tmp_channel"

    cat > "$tmp_script" << 'NODESCRIPT'
const fs = require('fs');
const configPath = process.argv[2];
const channelName = process.argv[3];
const channelFile = process.argv[4];
const newChannelConfig = JSON.parse(fs.readFileSync(channelFile, 'utf-8'));

const content = fs.readFileSync(configPath, 'utf-8');
let config;
try {
    config = new Function('return (' + content + ')')();
} catch(e) {
    console.error('无法解析配置文件: ' + e.message);
    process.exit(1);
}

if (!config.channels) config.channels = {};
config.channels[channelName] = newChannelConfig;

// 同时启用对应插件（防止 doctor --fix 禁用后无法自动恢复）
if (!config.plugins) config.plugins = {};
if (!config.plugins.entries) config.plugins.entries = {};
if (!config.plugins.entries[channelName]) config.plugins.entries[channelName] = {};
config.plugins.entries[channelName].enabled = true;

const output = '// OpenClaw 配置 - 由部署脚本自动生成\n// 文档: https://docs.openclaw.ai/gateway/configuration\n' + JSON.stringify(config, null, 2) + '\n';
fs.writeFileSync(configPath, output);
NODESCRIPT

    node "$tmp_script" "$OPENCLAW_CONFIG_FILE" "$channel_name" "$tmp_channel" 2>&1
    local result=$?
    rm -f "$tmp_channel" "$tmp_script"
    return $result
}

# 从 openclaw.json 移除频道配置（与 VPS 版一致，纯 Node.js）
openclaw_remove_channel() {
    local channel_name="$1"

    if [ ! -f "$OPENCLAW_CONFIG_FILE" ]; then
        echo "配置文件不存在"
        return 1
    fi

    local tmp_script=$(mktemp)
    cat > "$tmp_script" << 'NODESCRIPT'
const fs = require('fs');
const configPath = process.argv[2];
const channelName = process.argv[3];

const content = fs.readFileSync(configPath, 'utf-8');
let config;
try {
    config = new Function('return (' + content + ')')();
} catch(e) {
    console.error('无法解析配置文件');
    process.exit(1);
}

if (config.channels && config.channels[channelName]) {
    delete config.channels[channelName];
    // 同时禁用对应插件
    if (config.plugins && config.plugins.entries && config.plugins.entries[channelName]) {
        config.plugins.entries[channelName].enabled = false;
    }
    const output = '// OpenClaw 配置 - 由部署脚本自动生成\n// 文档: https://docs.openclaw.ai/gateway/configuration\n' + JSON.stringify(config, null, 2) + '\n';
    fs.writeFileSync(configPath, output);
    console.log('已移除 ' + channelName + ' 频道配置');
} else {
    console.log('频道 ' + channelName + ' 未在配置中找到');
}
NODESCRIPT

    node "$tmp_script" "$OPENCLAW_CONFIG_FILE" "$channel_name" 2>&1
    local result=$?
    rm -f "$tmp_script"
    return $result
}

# Mac 版服务重启辅助（频道操作后调用）
mac_channel_restart_if_running() {
    local svc_status=$(mac_openclaw_check_status)
    if [ "$svc_status" = "running" ] || [ "$svc_status" = "running_no_pid" ]; then
        mac_openclaw_restart 2>/dev/null
        sleep 2
        echo -e "${gl_lv}✅ 服务已重启，配置已生效${gl_bai}"
    fi
}

# 频道管理菜单（Mac 版，对应 VPS 版行 2413-2742）
openclaw_channels() {
    if ! command -v openclaw &>/dev/null; then
        echo -e "${gl_hong}❌ OpenClaw 未安装，请先执行「一键部署」${gl_bai}"
        break_end
        return 1
    fi

    while true; do
        clear
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_kjlan}  OpenClaw 频道管理${gl_bai}"
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""

        # 显示已配置的频道（从配置文件读取）
        echo -e "${gl_lv}── 已配置的频道 ──${gl_bai}"
        if [ -f "$OPENCLAW_CONFIG_FILE" ]; then
            node -e '
                const fs = require("fs");
                const content = fs.readFileSync(process.argv[1], "utf-8");
                try {
                    const config = new Function("return (" + content + ")")();
                    const ch = config.channels || {};
                    const names = Object.keys(ch);
                    if (names.length === 0) { console.log("  暂无已配置的频道"); }
                    else {
                        for (const n of names) {
                            const enabled = ch[n].enabled !== false ? "✅" : "❌";
                            console.log("  " + enabled + " " + n);
                        }
                    }
                } catch(e) { console.log("  暂无已配置的频道"); }
            ' "$OPENCLAW_CONFIG_FILE" 2>/dev/null || echo "  暂无已配置的频道"
        else
            echo "  暂无已配置的频道"
        fi
        echo ""

        echo -e "${gl_kjlan}[配置频道]${gl_bai}"
        echo "1. Telegram Bot      — 输入 Bot Token"
        echo "2. WhatsApp          — 终端扫码登录"
        echo "3. Discord Bot       — 输入 Bot Token"
        echo "4. Slack             — 输入 App Token + Bot Token"
        echo ""
        echo -e "${gl_kjlan}[频道管理]${gl_bai}"
        echo "5. 查看频道状态"
        echo "6. 查看频道日志"
        echo "7. 断开/删除频道"
        echo ""
        echo "0. 返回"
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"

        read -e -p "请选择 [0-7]: " ch_choice

        case $ch_choice in
            1)
                # Telegram
                clear
                echo -e "${gl_kjlan}━━━ 配置 Telegram Bot ━━━${gl_bai}"
                echo ""
                echo -e "${gl_zi}📋 获取 Bot Token 步骤:${gl_bai}"
                echo -e "  1. 打开 Telegram，搜索 ${gl_huang}@BotFather${gl_bai}"
                echo "  2. 发送 /newbot 创建新 Bot"
                echo "  3. 按提示设置 Bot 名称和用户名（用户名必须以 bot 结尾）"
                echo "  4. 复制 BotFather 给的 Token"
                echo ""
                echo -e "${gl_zi}Token 格式: 123456789:ABCdefGHIjklMNOpqrsTUVwxyz${gl_bai}"
                echo ""

                read -e -p "请输入 Telegram Bot Token: " tg_token
                if [ -z "$tg_token" ]; then
                    echo -e "${gl_hong}❌ Token 不能为空${gl_bai}"
                    break_end
                    continue
                fi

                echo ""
                echo "正在写入 Telegram 配置..."
                local tg_json="{\"botToken\":\"${tg_token}\",\"enabled\":true,\"dmPolicy\":\"pairing\",\"groupPolicy\":\"allowlist\",\"streamMode\":\"partial\",\"textChunkLimit\":4000,\"dmHistoryLimit\":50,\"historyLimit\":50}"
                openclaw_update_channel "telegram" "$tg_json"

                if [ $? -eq 0 ]; then
                    echo ""
                    echo -e "${gl_lv}✅ Telegram Bot 配置成功${gl_bai}"
                    echo ""
                    echo -e "${gl_zi}下一步:${gl_bai}"
                    echo "  1. 在 Telegram 中搜索你的 Bot 并发送一条消息"
                    echo "  2. Bot 会回复一个配对码（pairing code）"
                    echo -e "  3. 运行: ${gl_huang}openclaw pairing approve telegram <配对码>${gl_bai}"

                    mac_channel_restart_if_running
                else
                    echo ""
                    echo -e "${gl_hong}❌ 配置写入失败${gl_bai}"
                fi
                break_end
                ;;
            2)
                # WhatsApp
                clear
                echo -e "${gl_kjlan}━━━ 配置 WhatsApp ━━━${gl_bai}"
                echo ""
                echo -e "${gl_zi}📋 登录步骤:${gl_bai}"
                echo "  1. 先写入 WhatsApp 频道配置"
                echo "  2. 终端会显示 QR 二维码"
                echo "  3. 打开手机 WhatsApp → 设置 → 已关联设备 → 关联设备"
                echo "  4. 扫描终端中的 QR 码（60秒内有效，超时重新运行）"
                echo ""
                echo -e "${gl_huang}⚠ 注意事项:${gl_bai}"
                echo "  • 需要使用真实手机号，虚拟号码可能被封禁"
                echo "  • 一个 WhatsApp 号码只能绑定一个 OpenClaw 网关"
                echo ""

                read -e -p "准备好了吗？(Y/N): " confirm
                case "$confirm" in
                    [Yy])
                        echo ""
                        echo "正在写入 WhatsApp 配置..."
                        local wa_json='{"enabled":true,"dmPolicy":"pairing","groupPolicy":"allowlist","streamMode":"partial","historyLimit":50,"dmHistoryLimit":50}'
                        openclaw_update_channel "whatsapp" "$wa_json"

                        if [ $? -eq 0 ]; then
                            echo -e "${gl_lv}✅ WhatsApp 配置已写入${gl_bai}"
                            echo ""

                            mac_channel_restart_if_running

                            echo "正在启动 WhatsApp 登录（显示 QR 码）..."
                            echo ""
                            openclaw channels login 2>&1
                        else
                            echo -e "${gl_hong}❌ 配置写入失败${gl_bai}"
                        fi
                        ;;
                    *)
                        echo "已取消"
                        ;;
                esac
                break_end
                ;;
            3)
                # Discord
                clear
                echo -e "${gl_kjlan}━━━ 配置 Discord Bot ━━━${gl_bai}"
                echo ""
                echo -e "${gl_zi}📋 获取 Bot Token 步骤:${gl_bai}"
                echo -e "  1. 打开 ${gl_huang}https://discord.com/developers/applications${gl_bai}"
                echo "  2. 点击 New Application → 输入名称 → 创建"
                echo "  3. 左侧 Bot 页面 → Reset Token → 复制 Token"
                echo -e "  4. 开启 ${gl_huang}Privileged Gateway Intents${gl_bai}:"
                echo "     • Message Content Intent（必须开启）"
                echo "     • Server Members Intent（推荐开启）"
                echo "  5. OAuth2 → URL Generator → 勾选 bot + applications.commands"
                echo "     权限: View Channels / Send Messages / Read Message History"
                echo "  6. 用生成的邀请链接把 Bot 添加到你的服务器"
                echo ""

                read -e -p "请输入 Discord Bot Token: " dc_token
                if [ -z "$dc_token" ]; then
                    echo -e "${gl_hong}❌ Token 不能为空${gl_bai}"
                    break_end
                    continue
                fi

                echo ""
                echo "正在写入 Discord 配置..."
                local dc_json="{\"token\":\"${dc_token}\",\"enabled\":true,\"dm\":{\"enabled\":true,\"policy\":\"pairing\"},\"groupPolicy\":\"allowlist\",\"textChunkLimit\":2000,\"historyLimit\":20}"
                openclaw_update_channel "discord" "$dc_json"

                if [ $? -eq 0 ]; then
                    echo ""
                    echo -e "${gl_lv}✅ Discord Bot 配置成功${gl_bai}"
                    echo ""
                    echo -e "${gl_zi}确保已用邀请链接将 Bot 添加到你的 Discord 服务器${gl_bai}"

                    mac_channel_restart_if_running
                else
                    echo ""
                    echo -e "${gl_hong}❌ 配置写入失败${gl_bai}"
                fi
                break_end
                ;;
            4)
                # Slack
                clear
                echo -e "${gl_kjlan}━━━ 配置 Slack ━━━${gl_bai}"
                echo ""
                echo -e "${gl_zi}📋 获取 Token 步骤:${gl_bai}"
                echo -e "  1. 打开 ${gl_huang}https://api.slack.com/apps${gl_bai} → Create New App → From Scratch"
                echo -e "  2. 开启 ${gl_huang}Socket Mode${gl_bai}"
                echo "  3. Basic Information → App-Level Tokens → Generate Token"
                echo -e "     Scope: connections:write → 复制 App Token（${gl_huang}xapp-${gl_bai} 开头）"
                echo "  4. OAuth & Permissions → 添加 Bot Token Scopes:"
                echo "     chat:write / channels:history / groups:history"
                echo "     im:history / channels:read / users:read"
                echo -e "  5. Install to Workspace → 复制 Bot Token（${gl_huang}xoxb-${gl_bai} 开头）"
                echo "  6. Event Subscriptions → Enable → Subscribe to message.* events"
                echo ""
                echo -e "${gl_huang}Slack 需要两个 Token:${gl_bai}"
                echo ""

                read -e -p "App Token (xapp-开头): " slack_app_token
                if [ -z "$slack_app_token" ]; then
                    echo -e "${gl_hong}❌ App Token 不能为空${gl_bai}"
                    break_end
                    continue
                fi

                read -e -p "Bot Token (xoxb-开头): " slack_bot_token
                if [ -z "$slack_bot_token" ]; then
                    echo -e "${gl_hong}❌ Bot Token 不能为空${gl_bai}"
                    break_end
                    continue
                fi

                echo ""
                echo "正在写入 Slack 配置..."
                local slack_json="{\"appToken\":\"${slack_app_token}\",\"botToken\":\"${slack_bot_token}\",\"enabled\":true,\"dmPolicy\":\"pairing\",\"groupPolicy\":\"allowlist\",\"streamMode\":\"partial\",\"historyLimit\":50}"
                openclaw_update_channel "slack" "$slack_json"

                if [ $? -eq 0 ]; then
                    echo ""
                    echo -e "${gl_lv}✅ Slack 配置已保存${gl_bai}"

                    mac_channel_restart_if_running
                else
                    echo ""
                    echo -e "${gl_hong}❌ 配置写入失败${gl_bai}"
                fi
                break_end
                ;;
            5)
                # 查看频道状态
                clear
                echo -e "${gl_kjlan}━━━ 频道状态 ━━━${gl_bai}"
                echo ""
                openclaw channels status --probe 2>&1 || \
                openclaw channels status 2>&1 || \
                openclaw gateway status 2>&1 || \
                echo "无法获取频道状态"
                echo ""
                break_end
                ;;
            6)
                # 查看频道日志（Mac 版: tail 替代 journalctl）
                clear
                echo -e "${gl_kjlan}━━━ 频道日志（最近 50 行）━━━${gl_bai}"
                echo ""
                if [ -f "$OPENCLAW_LOG_FILE" ]; then
                    tail -50 "$OPENCLAW_LOG_FILE"
                else
                    echo "日志文件不存在"
                fi
                echo ""
                break_end
                ;;
            7)
                # 断开/删除频道
                clear
                echo -e "${gl_kjlan}━━━ 断开频道 ━━━${gl_bai}"
                echo ""
                echo "选择要断开的频道:"
                echo "1. Telegram"
                echo "2. WhatsApp"
                echo "3. Discord"
                echo "4. Slack"
                echo ""
                echo "0. 取消"
                echo ""

                read -e -p "请选择 [0-4]: " rm_choice
                local channel_name=""
                case $rm_choice in
                    1) channel_name="telegram" ;;
                    2) channel_name="whatsapp" ;;
                    3) channel_name="discord" ;;
                    4) channel_name="slack" ;;
                    0) continue ;;
                    *)
                        echo "无效选择"
                        break_end
                        continue
                        ;;
                esac

                echo ""
                read -e -p "确认断开 ${channel_name}？(Y/N): " confirm
                case "$confirm" in
                    [Yy])
                        echo ""
                        openclaw_remove_channel "$channel_name"
                        echo ""
                        echo -e "${gl_lv}✅ 已断开 ${channel_name}${gl_bai}"

                        mac_channel_restart_if_running
                        ;;
                    *)
                        echo "已取消"
                        ;;
                esac
                break_end
                ;;
            0)
                return
                ;;
            *)
                echo "无效的选择"
                sleep 2
                ;;
        esac
    done
}

#=============================================================================
# Task 11: 查看配置、编辑配置、安全检查
#=============================================================================

# 查看当前配置（Mac 版，对应 VPS 版行 2745-2829）
# 适配: IP → localhost, 去掉 SSH 隧道提示
openclaw_show_config() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  OpenClaw 当前配置${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    if [ ! -f "$OPENCLAW_CONFIG_FILE" ]; then
        echo -e "${gl_huang}⚠ 配置文件不存在: ${OPENCLAW_CONFIG_FILE}${gl_bai}"
        echo ""
        break_end
        return
    fi

    # 格式化摘要
    local port=$(openclaw_get_port)
    local gw_token=$(sed -nE 's/.*OPENCLAW_GATEWAY_TOKEN=(.*)/\1/p' "$OPENCLAW_ENV_FILE" 2>/dev/null)

    node -e "
        const fs = require('fs');
        const content = fs.readFileSync('${OPENCLAW_CONFIG_FILE}', 'utf-8');
        try {
            const config = new Function('return (' + content + ')')();
            const providers = config.models && config.models.providers || {};
            const keys = Object.keys(providers);
            const defaults = config.agents && config.agents.defaults && config.agents.defaults.model || {};
            for (const name of keys) {
                const p = providers[name];
                console.log('  Provider:  ' + name);
                console.log('  API 类型:  ' + (p.api || 'unknown'));
                console.log('  反代地址:  ' + (p.baseUrl || 'unknown'));
                const models = p.models || [];
                if (models.length > 0) {
                    console.log('  可用模型:  ' + models.map(m => m.id).join(', '));
                }
            }
            if (defaults.primary) console.log('  主力模型:  ' + defaults.primary);

            const ch = config.channels || {};
            const chNames = Object.keys(ch);
            if (chNames.length > 0) {
                console.log('');
                console.log('  已配置频道: ' + chNames.map(n => { const e = ch[n].enabled !== false; return (e ? '✅' : '❌') + ' ' + n; }).join('  |  '));
            }
        } catch(e) { console.log('  无法解析配置'); }
    " 2>/dev/null

    echo ""
    echo -e "${gl_kjlan}━━━ 部署信息 ━━━${gl_bai}"
    echo -e "网关端口:   ${gl_huang}${port}${gl_bai}"
    if [ -n "$gw_token" ]; then
        echo -e "网关 Token: ${gl_huang}${gw_token}${gl_bai}"
    fi
    echo -e "控制面板:   ${gl_huang}http://localhost:${port}/${gl_bai}"
    echo ""

    echo -e "${gl_kjlan}━━━ 管理命令 ━━━${gl_bai}"
    echo "  状态: 本脚本菜单选项 3"
    echo "  日志: tail -f ${OPENCLAW_LOG_FILE}"
    echo "  重启: 本脚本菜单选项 7"
    echo ""

    # 查看原始文件
    read -e -p "是否查看原始配置文件？(Y/N): " show_raw
    case "$show_raw" in
        [Yy])
            echo ""
            echo -e "${gl_zi}── ${OPENCLAW_CONFIG_FILE} ──${gl_bai}"
            cat "$OPENCLAW_CONFIG_FILE"
            echo ""
            if [ -f "$OPENCLAW_ENV_FILE" ]; then
                echo -e "${gl_zi}── ${OPENCLAW_ENV_FILE}（脱敏）──${gl_bai}"
                sed 's/\(=\).*/\1****（已隐藏）/' "$OPENCLAW_ENV_FILE"
            fi
            ;;
    esac

    echo ""
    break_end
}

# 编辑配置文件（Mac 版，对应 VPS 版行 2832-2874）
# 适配: editor → $EDITOR, systemctl → PID
openclaw_edit_config() {
    if [ ! -f "$OPENCLAW_CONFIG_FILE" ]; then
        echo -e "${gl_huang}⚠ 配置文件不存在，是否创建默认配置？${gl_bai}"
        read -e -p "(Y/N): " confirm
        case "$confirm" in
            [Yy])
                mkdir -p "$OPENCLAW_HOME_DIR"
                echo '{}' > "$OPENCLAW_CONFIG_FILE"
                ;;
            *)
                return
                ;;
        esac
    fi

    local editor="${EDITOR:-nano}"

    $editor "$OPENCLAW_CONFIG_FILE"

    echo ""
    echo -e "${gl_zi}提示: 修改配置后需重启服务生效${gl_bai}"

    read -e -p "是否现在重启服务？(Y/N): " confirm
    case "$confirm" in
        [Yy])
            local svc_status=$(mac_openclaw_check_status)
            if [ "$svc_status" = "running" ] || [ "$svc_status" = "running_no_pid" ]; then
                mac_openclaw_restart
                sleep 2
                local new_status=$(mac_openclaw_check_status)
                if [ "$new_status" = "running" ]; then
                    echo -e "${gl_lv}✅ 服务已重启${gl_bai}"
                else
                    echo -e "${gl_hong}❌ 服务重启失败，请检查配置是否正确${gl_bai}"
                fi
            else
                echo -e "${gl_huang}⚠ 服务未在运行${gl_bai}"
            fi
            ;;
    esac

    break_end
}

# 安全检查（与 VPS 版一致，行 3224-3249，纯 CLI 调用，无平台依赖）
openclaw_doctor() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  OpenClaw 安全检查${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    if ! command -v openclaw &>/dev/null; then
        echo -e "${gl_hong}❌ OpenClaw 未安装${gl_bai}"
        break_end
        return 1
    fi

    openclaw doctor
    echo ""

    read -e -p "是否自动修复发现的问题？(Y/N): " confirm
    case "$confirm" in
        [Yy])
            echo ""
            openclaw doctor --fix
            ;;
    esac

    break_end
}

#=============================================================================
# Task 12: 卸载功能
#=============================================================================

# 卸载 OpenClaw（Mac 版，对应 VPS 版行 3252-3302）
# 适配: systemd 清理 → PID 清理
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

#=============================================================================
# Task 13: 主菜单与脚本入口
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
                # 模型配置后提示重启
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

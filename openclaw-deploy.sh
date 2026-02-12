#!/bin/bash
#=============================================================================
# OpenClaw Deploy - OpenClaw 一键部署工具箱
# 功能：一键部署和管理 OpenClaw 及相关 AI 代理服务
# 包含：OpenClaw (AI多渠道消息网关)、CRS (Claude中转)、Sub2API
#=============================================================================
# 从 BBR v3 终极优化脚本 (net-tcp-tune.sh) v4.9.0 独立提取
#=============================================================================

TOOLKIT_VERSION="1.0.0"
TOOLKIT_LAST_UPDATE="从 net-tcp-tune.sh v4.9.0 独立提取三大AI服务模块"

#=============================================================================
# 颜色定义
#=============================================================================
gl_hong='\033[31m'      # 红色
gl_lv='\033[32m'        # 绿色
gl_huang='\033[33m'     # 黄色
gl_bai='\033[0m'        # 重置
gl_kjlan='\033[96m'     # 亮青色
gl_zi='\033[35m'        # 紫色
gl_hui='\033[90m'       # 灰色

#=============================================================================
# 共享工具函数
#=============================================================================

# Root 权限检查
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${gl_hong}错误: ${gl_bai}此脚本需要 root 权限运行！"
        echo "请使用: sudo bash $0"
        exit 1
    fi
}

# 操作完成暂停
break_end() {
    [ "$AUTO_MODE" = "1" ] && return
    echo -e "${gl_lv}操作完成${gl_bai}"
    echo "按任意键继续..."
    read -n 1 -s -r -p ""
    echo ""
}

# =====================================================
# Claude Relay Service (CRS) 部署管理 (菜单41)
# =====================================================

# 常量定义
CRS_DEFAULT_PORT="3000"
CRS_PORT_FILE="/etc/crs-port"
CRS_INSTALL_DIR_FILE="/etc/crs-install-dir"
CRS_DEFAULT_INSTALL_DIR="/root/claude-relay-service"
CRS_MANAGE_SCRIPT_URL="https://pincc.ai/manage.sh"

# 获取安装目录
crs_get_install_dir() {
    if [ -f "$CRS_INSTALL_DIR_FILE" ]; then
        cat "$CRS_INSTALL_DIR_FILE"
    else
        echo "$CRS_DEFAULT_INSTALL_DIR"
    fi
}

# 获取当前配置的端口
crs_get_port() {
    if [ -f "$CRS_PORT_FILE" ]; then
        cat "$CRS_PORT_FILE"
    else
        # 尝试从配置文件读取
        local install_dir=$(crs_get_install_dir)
        if [ -f "$install_dir/config/config.js" ]; then
            local port=$(sed -nE 's/.*port:[[:space:]]*([0-9]+).*/\1/p' "$install_dir/config/config.js" 2>/dev/null | head -1)
            if [ -n "$port" ]; then
                echo "$port"
                return
            fi
        fi
        echo "$CRS_DEFAULT_PORT"
    fi
}

# 检查 CRS 状态
crs_check_status() {
    # 检查 crs 命令是否存在
    if ! command -v crs &>/dev/null; then
        # 检查安装目录是否存在
        local install_dir=$(crs_get_install_dir)
        if [ -d "$install_dir" ]; then
            echo "installed_no_command"
        else
            echo "not_installed"
        fi
        return
    fi

    # 使用 crs status 检查
    local status_output=$(crs status 2>&1)
    if echo "$status_output" | grep -qi "running\|online\|started"; then
        echo "running"
    elif echo "$status_output" | grep -qi "stopped\|offline\|not running"; then
        echo "stopped"
    else
        # 通过端口检测
        local port=$(crs_get_port)
        if ss -lntp 2>/dev/null | grep -q ":${port} "; then
            echo "running"
        else
            echo "stopped"
        fi
    fi
}

# 检查端口是否可用
crs_check_port() {
    local port=$1
    if ss -lntp 2>/dev/null | grep -q ":${port} "; then
        return 1
    fi
    return 0
}

# 一键部署
crs_deploy() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  一键部署 Claude Relay Service (CRS)${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    # 检查是否已安装
    local status=$(crs_check_status)
    if [ "$status" != "not_installed" ]; then
        echo -e "${gl_huang}⚠️ CRS 已安装${gl_bai}"
        read -e -p "是否重新部署？这将保留数据但重装服务 (y/n) [n]: " reinstall
        if [ "$reinstall" != "y" ] && [ "$reinstall" != "Y" ]; then
            break_end
            return 0
        fi
        echo ""
        echo "正在停止现有服务..."
        crs stop 2>/dev/null
    fi

    echo ""
    echo -e "${gl_kjlan}[1/4] 下载安装脚本...${gl_bai}"

    # 创建临时目录
    local temp_dir=$(mktemp -d)
    cd "$temp_dir" || { echo -e "${gl_hong}❌ 创建临时目录失败${gl_bai}"; break_end; return 1; }

    # 下载 manage.sh
    if ! curl -fsSL "$CRS_MANAGE_SCRIPT_URL" -o manage.sh; then
        echo -e "${gl_hong}❌ 下载安装脚本失败${gl_bai}"
        rm -rf "$temp_dir"
        break_end
        return 1
    fi
    chmod +x manage.sh
    echo -e "${gl_lv}✅ 下载完成${gl_bai}"

    echo ""
    echo -e "${gl_kjlan}[2/4] 配置安装参数...${gl_bai}"
    echo ""

    # 安装目录
    local install_dir="$CRS_DEFAULT_INSTALL_DIR"
    read -e -p "安装目录 [$CRS_DEFAULT_INSTALL_DIR]: " input_dir
    if [ -n "$input_dir" ]; then
        install_dir="$input_dir"
    fi

    # 端口配置
    local port="$CRS_DEFAULT_PORT"
    read -e -p "服务端口 [$CRS_DEFAULT_PORT]: " input_port
    if [ -n "$input_port" ]; then
        port="$input_port"
    fi

    # 检查端口是否可用
    while ! crs_check_port "$port"; do
        echo -e "${gl_hong}⚠️ 端口 $port 已被占用${gl_bai}"
        read -e -p "请输入其他端口: " port
        if [ -z "$port" ]; then
            port="$CRS_DEFAULT_PORT"
        fi
    done
    echo -e "${gl_lv}✅ 端口 $port 可用${gl_bai}"

    # Redis 配置
    echo ""
    local redis_host="localhost"
    local redis_port="6379"
    local redis_password=""

    read -e -p "Redis 地址 [localhost]: " input_redis_host
    if [ -n "$input_redis_host" ]; then
        redis_host="$input_redis_host"
    fi

    read -e -p "Redis 端口 [6379]: " input_redis_port
    if [ -n "$input_redis_port" ]; then
        redis_port="$input_redis_port"
    fi

    read -e -p "Redis 密码 (无密码直接回车): " redis_password

    echo ""
    echo -e "${gl_kjlan}[3/4] 执行安装...${gl_bai}"
    echo ""
    echo "安装目录: $install_dir"
    echo "服务端口: $port"
    echo "Redis: $redis_host:$redis_port"
    echo ""

    # 使用 expect 或直接执行安装（通过环境变量传递参数）
    # CRS 的 manage.sh 支持交互式安装，这里我们传递参数
    export CRS_INSTALL_DIR="$install_dir"
    export CRS_PORT="$port"
    export CRS_REDIS_HOST="$redis_host"
    export CRS_REDIS_PORT="$redis_port"
    export CRS_REDIS_PASSWORD="$redis_password"

    # 执行安装脚本
    echo ""
    echo -e "${gl_huang}正在安装，请按提示操作...${gl_bai}"
    echo -e "${gl_zi}（安装目录输入: $install_dir，端口输入: $port）${gl_bai}"
    echo ""

    ./manage.sh install

    local install_result=$?

    # 清理临时文件
    cd /
    rm -rf "$temp_dir"

    if [ $install_result -ne 0 ]; then
        echo ""
        echo -e "${gl_hong}❌ 安装过程出现错误${gl_bai}"
        break_end
        return 1
    fi

    # 保存配置
    echo "$port" > "$CRS_PORT_FILE"
    echo "$install_dir" > "$CRS_INSTALL_DIR_FILE"

    echo ""
    echo -e "${gl_kjlan}[4/4] 验证安装...${gl_bai}"

    sleep 3

    # 获取服务器 IP
    local server_ip=$(curl -s4 ip.sb 2>/dev/null || curl -s6 ip.sb 2>/dev/null || echo "服务器IP")

    # 检查服务状态
    if command -v crs &>/dev/null; then
        echo -e "${gl_lv}✅ crs 命令已安装${gl_bai}"
    fi

    echo ""
    echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_lv}  ✅ 部署完成！${gl_bai}"
    echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    echo -e "Web 管理面板: ${gl_huang}http://${server_ip}:${port}/web${gl_bai}"
    echo ""
    echo -e "${gl_kjlan}【管理员账号】${gl_bai}"
    echo "  账号信息保存在: $install_dir/data/init.json"
    echo "  使用菜单「8. 查看管理员账号」可以直接查看"
    echo ""
    echo -e "${gl_kjlan}【下一步操作】${gl_bai}"
    echo "  1. 访问 Web 面板，使用管理员账号登录"
    echo "  2. 添加 Claude 账户（OAuth 授权）"
    echo "  3. 创建 API Key 分发给用户"
    echo "  4. 配置本地 Claude Code 环境变量"
    echo ""
    echo -e "${gl_kjlan}【Claude Code 配置】${gl_bai}"
    echo -e "  ${gl_huang}export ANTHROPIC_BASE_URL=\"http://${server_ip}:${port}/api/\"${gl_bai}"
    echo -e "  ${gl_huang}export ANTHROPIC_AUTH_TOKEN=\"后台创建的API密钥\"${gl_bai}"
    echo ""
    echo -e "${gl_zi}提示: 使用菜单「10. 查看配置指引」获取完整配置说明${gl_bai}"
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}管理命令:${gl_bai}"
    echo "  状态: crs status"
    echo "  启动: crs start"
    echo "  停止: crs stop"
    echo "  重启: crs restart"
    echo "  更新: crs update"
    echo ""

    break_end
}

# 更新服务
crs_update() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  更新 Claude Relay Service${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    local status=$(crs_check_status)
    if [ "$status" = "not_installed" ]; then
        echo -e "${gl_hong}❌ CRS 未安装，请先执行一键部署${gl_bai}"
        break_end
        return 1
    fi

    echo "正在更新..."
    echo ""

    if command -v crs &>/dev/null; then
        crs update
        if [ $? -eq 0 ]; then
            echo ""
            echo -e "${gl_lv}✅ 更新完成${gl_bai}"
        else
            echo ""
            echo -e "${gl_hong}❌ 更新失败${gl_bai}"
        fi
    else
        echo -e "${gl_hong}❌ crs 命令不可用，请重新部署${gl_bai}"
    fi

    break_end
}

# 查看状态
crs_status() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  Claude Relay Service 状态${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    local status=$(crs_check_status)
    local port=$(crs_get_port)
    local server_ip=$(curl -s4 ip.sb 2>/dev/null || curl -s6 ip.sb 2>/dev/null || echo "服务器IP")
    local install_dir=$(crs_get_install_dir)

    case "$status" in
        "running")
            echo -e "运行状态: ${gl_lv}✅ 运行中${gl_bai}"
            echo -e "服务端口: ${gl_huang}$port${gl_bai}"
            echo -e "Web 面板: ${gl_huang}http://${server_ip}:${port}/web${gl_bai}"
            echo -e "安装目录: ${gl_huang}$install_dir${gl_bai}"
            ;;
        "stopped")
            echo -e "运行状态: ${gl_hong}❌ 已停止${gl_bai}"
            echo -e "服务端口: ${gl_huang}$port${gl_bai}"
            echo -e "安装目录: ${gl_huang}$install_dir${gl_bai}"
            ;;
        "installed_no_command")
            echo -e "运行状态: ${gl_huang}⚠️ 已安装但 crs 命令不可用${gl_bai}"
            echo -e "安装目录: ${gl_huang}$install_dir${gl_bai}"
            echo ""
            echo "建议重新执行一键部署"
            ;;
        "not_installed")
            echo -e "运行状态: ${gl_hui}未安装${gl_bai}"
            echo ""
            echo "请使用「一键部署」选项安装"
            ;;
    esac

    echo ""

    # 如果 crs 命令可用，显示详细状态
    if command -v crs &>/dev/null && [ "$status" != "not_installed" ]; then
        echo -e "${gl_kjlan}详细状态:${gl_bai}"
        echo ""
        crs status
    fi

    echo ""
    break_end
}

# 查看日志
crs_logs() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  Claude Relay Service 日志${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    echo -e "${gl_zi}按 Ctrl+C 退出日志查看${gl_bai}"
    echo ""

    local status=$(crs_check_status)
    if [ "$status" = "not_installed" ]; then
        echo -e "${gl_hong}❌ CRS 未安装${gl_bai}"
        break_end
        return 1
    fi

    if command -v crs &>/dev/null; then
        crs logs
    else
        # 尝试查看日志文件
        local install_dir=$(crs_get_install_dir)
        if [ -d "$install_dir/logs" ]; then
            tail -f "$install_dir/logs/"*.log 2>/dev/null || echo "无法读取日志文件"
        else
            echo "日志目录不存在"
        fi
    fi
}

# 启动服务
crs_start() {
    echo ""
    echo "正在启动 CRS..."

    local status=$(crs_check_status)
    if [ "$status" = "not_installed" ]; then
        echo -e "${gl_hong}❌ CRS 未安装${gl_bai}"
        break_end
        return 1
    fi

    if command -v crs &>/dev/null; then
        crs start
        sleep 2
        if [ "$(crs_check_status)" = "running" ]; then
            local port=$(crs_get_port)
            local server_ip=$(curl -s4 ip.sb 2>/dev/null || curl -s6 ip.sb 2>/dev/null || echo "服务器IP")
            echo ""
            echo -e "${gl_lv}✅ 服务已启动${gl_bai}"
            echo -e "访问地址: ${gl_huang}http://${server_ip}:${port}/web${gl_bai}"
        else
            echo -e "${gl_hong}❌ 启动失败${gl_bai}"
        fi
    else
        echo -e "${gl_hong}❌ crs 命令不可用${gl_bai}"
    fi

    break_end
}

# 停止服务
crs_stop() {
    echo ""
    echo "正在停止 CRS..."

    local status=$(crs_check_status)
    if [ "$status" = "not_installed" ]; then
        echo -e "${gl_hong}❌ CRS 未安装${gl_bai}"
        break_end
        return 1
    fi

    if command -v crs &>/dev/null; then
        crs stop
        sleep 2
        if [ "$(crs_check_status)" != "running" ]; then
            echo -e "${gl_lv}✅ 服务已停止${gl_bai}"
        else
            echo -e "${gl_hong}❌ 停止失败${gl_bai}"
        fi
    else
        echo -e "${gl_hong}❌ crs 命令不可用${gl_bai}"
    fi

    break_end
}

# 重启服务
crs_restart() {
    echo ""
    echo "正在重启 CRS..."

    local status=$(crs_check_status)
    if [ "$status" = "not_installed" ]; then
        echo -e "${gl_hong}❌ CRS 未安装${gl_bai}"
        break_end
        return 1
    fi

    if command -v crs &>/dev/null; then
        crs restart
        sleep 2
        if [ "$(crs_check_status)" = "running" ]; then
            local port=$(crs_get_port)
            local server_ip=$(curl -s4 ip.sb 2>/dev/null || curl -s6 ip.sb 2>/dev/null || echo "服务器IP")
            echo ""
            echo -e "${gl_lv}✅ 服务已重启${gl_bai}"
            echo -e "访问地址: ${gl_huang}http://${server_ip}:${port}/web${gl_bai}"
        else
            echo -e "${gl_hong}❌ 重启失败${gl_bai}"
        fi
    else
        echo -e "${gl_hong}❌ crs 命令不可用${gl_bai}"
    fi

    break_end
}

# 查看管理员账号
crs_show_admin() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  CRS 管理员账号${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    local status=$(crs_check_status)
    if [ "$status" = "not_installed" ]; then
        echo -e "${gl_hong}❌ CRS 未安装${gl_bai}"
        break_end
        return 1
    fi

    local install_dir=$(crs_get_install_dir)
    local init_file="$install_dir/data/init.json"

    if [ -f "$init_file" ]; then
        echo -e "${gl_lv}管理员账号信息:${gl_bai}"
        echo ""

        # 解析 JSON 并显示
        local username=$(sed -nE 's/.*"username"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$init_file" 2>/dev/null | head -1)
        local password=$(sed -nE 's/.*"password"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$init_file" 2>/dev/null | head -1)

        if [ -n "$username" ] && [ -n "$password" ]; then
            local port=$(crs_get_port)
            local server_ip=$(curl -s4 ip.sb 2>/dev/null || curl -s6 ip.sb 2>/dev/null || echo "服务器IP")

            echo -e "  用户名: ${gl_huang}$username${gl_bai}"
            echo -e "  密  码: ${gl_huang}$password${gl_bai}"
            echo ""
            echo -e "  登录地址: ${gl_huang}http://${server_ip}:${port}/web${gl_bai}"
        else
            echo "无法解析账号信息，原始内容:"
            echo ""
            cat "$init_file"
        fi
    else
        echo -e "${gl_huang}⚠️ 未找到账号信息文件${gl_bai}"
        echo ""
        echo "文件路径: $init_file"
        echo ""
        echo "可能原因:"
        echo "  1. 服务尚未完成初始化"
        echo "  2. 使用了环境变量预设账号"
        echo ""
        echo "如果使用环境变量设置了账号，请查看安装时的配置"
    fi

    echo ""
    break_end
}

# 修改端口
crs_change_port() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  修改 CRS 端口${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    local status=$(crs_check_status)
    if [ "$status" = "not_installed" ]; then
        echo -e "${gl_hong}❌ CRS 未安装${gl_bai}"
        break_end
        return 1
    fi

    local current_port=$(crs_get_port)
    local install_dir=$(crs_get_install_dir)
    echo -e "当前端口: ${gl_huang}$current_port${gl_bai}"
    echo ""

    read -e -p "请输入新端口 (1-65535): " new_port

    # 验证端口
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        echo -e "${gl_hong}❌ 无效的端口号${gl_bai}"
        break_end
        return 1
    fi

    if [ "$new_port" = "$current_port" ]; then
        echo -e "${gl_huang}⚠️ 端口未改变${gl_bai}"
        break_end
        return 0
    fi

    # 检查端口是否被占用
    if ! crs_check_port "$new_port"; then
        echo -e "${gl_hong}❌ 端口 $new_port 已被占用${gl_bai}"
        break_end
        return 1
    fi

    echo ""
    echo "正在修改端口..."

    # 停止服务
    if command -v crs &>/dev/null; then
        crs stop 2>/dev/null
    fi

    # 修改配置文件
    local config_file="$install_dir/config/config.js"
    if [ -f "$config_file" ]; then
        # 使用 sed 修改端口
        sed -i "s/port:\s*[0-9]\+/port: $new_port/" "$config_file"
        echo -e "${gl_lv}✅ 配置文件已更新${gl_bai}"
    else
        echo -e "${gl_huang}⚠️ 配置文件不存在，仅更新端口记录${gl_bai}"
    fi

    # 保存端口配置
    echo "$new_port" > "$CRS_PORT_FILE"

    # 重启服务
    if command -v crs &>/dev/null; then
        crs start
        sleep 2

        if [ "$(crs_check_status)" = "running" ]; then
            local server_ip=$(curl -s4 ip.sb 2>/dev/null || curl -s6 ip.sb 2>/dev/null || echo "服务器IP")
            echo ""
            echo -e "${gl_lv}✅ 端口已修改为 $new_port${gl_bai}"
            echo -e "新访问地址: ${gl_huang}http://${server_ip}:${new_port}/web${gl_bai}"
        else
            echo -e "${gl_hong}❌ 服务启动失败，请检查配置${gl_bai}"
        fi
    fi

    break_end
}

# 查看配置指引
crs_show_config() {
    clear

    local status=$(crs_check_status)
    if [ "$status" = "not_installed" ]; then
        echo -e "${gl_hong}❌ CRS 未安装，请先执行一键部署${gl_bai}"
        break_end
        return 1
    fi

    local port=$(crs_get_port)
    local server_ip=$(curl -s4 ip.sb 2>/dev/null || curl -s6 ip.sb 2>/dev/null || echo "服务器IP")

    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  Claude Relay Service 配置指引${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    echo -e "Web 管理面板: ${gl_huang}http://${server_ip}:${port}/web${gl_bai}"
    echo ""
    echo -e "${gl_kjlan}【第一步】添加 Claude 账户${gl_bai}"
    echo "  1. 登录 Web 管理面板"
    echo "  2. 点击「Claude账户」标签"
    echo "  3. 点击「添加账户」→「生成授权链接」"
    echo "  4. 在新页面完成 Claude 登录授权"
    echo "  5. 复制 Authorization Code 粘贴回页面"
    echo ""
    echo -e "${gl_kjlan}【第二步】创建 API Key${gl_bai}"
    echo "  1. 点击「API Keys」标签"
    echo "  2. 点击「创建新Key」"
    echo "  3. 设置名称和限制（可选）"
    echo "  4. 保存并记录生成的 Key"
    echo ""
    echo -e "${gl_kjlan}【第三步】配置 Claude Code${gl_bai}"
    echo ""
    echo -e "${gl_huang}方式一：环境变量配置${gl_bai}"
    echo ""
    echo "  # 使用标准 Claude 账号池"
    echo -e "  ${gl_lv}export ANTHROPIC_BASE_URL=\"http://${server_ip}:${port}/api/\"${gl_bai}"
    echo -e "  ${gl_lv}export ANTHROPIC_AUTH_TOKEN=\"你的API密钥\"${gl_bai}"
    echo ""
    echo "  # 或使用 Antigravity 账号池"
    echo -e "  ${gl_lv}export ANTHROPIC_BASE_URL=\"http://${server_ip}:${port}/antigravity/api/\"${gl_bai}"
    echo -e "  ${gl_lv}export ANTHROPIC_AUTH_TOKEN=\"你的API密钥\"${gl_bai}"
    echo ""
    echo -e "${gl_huang}方式二：settings.json 配置${gl_bai}"
    echo ""
    echo "  编辑 ~/.claude/settings.json:"
    echo ""
    echo -e "  ${gl_lv}{"
    echo -e "    \"env\": {"
    echo -e "      \"ANTHROPIC_BASE_URL\": \"http://${server_ip}:${port}/api/\","
    echo -e "      \"ANTHROPIC_AUTH_TOKEN\": \"你的API密钥\""
    echo -e "    }"
    echo -e "  }${gl_bai}"
    echo ""
    echo -e "${gl_kjlan}【Gemini CLI 配置】${gl_bai}"
    echo ""
    echo -e "  ${gl_lv}export CODE_ASSIST_ENDPOINT=\"http://${server_ip}:${port}/gemini\"${gl_bai}"
    echo -e "  ${gl_lv}export GOOGLE_CLOUD_ACCESS_TOKEN=\"你的API密钥\"${gl_bai}"
    echo -e "  ${gl_lv}export GOOGLE_GENAI_USE_GCA=\"true\"${gl_bai}"
    echo -e "  ${gl_lv}export GEMINI_MODEL=\"gemini-2.5-pro\"${gl_bai}"
    echo ""
    echo -e "${gl_kjlan}【Codex CLI 配置】${gl_bai}"
    echo ""
    echo "  编辑 ~/.codex/config.toml 添加:"
    echo ""
    echo -e "  ${gl_lv}model_provider = \"crs\""
    echo -e "  [model_providers.crs]"
    echo -e "  name = \"crs\""
    echo -e "  base_url = \"http://${server_ip}:${port}/openai\""
    echo -e "  wire_api = \"responses\""
    echo -e "  requires_openai_auth = true"
    echo -e "  env_key = \"CRS_OAI_KEY\"${gl_bai}"
    echo ""
    echo "  然后设置环境变量:"
    echo -e "  ${gl_lv}export CRS_OAI_KEY=\"你的API密钥\"${gl_bai}"
    echo ""
    echo -e "${gl_zi}提示: 所有客户端使用相同的 API 密钥，系统根据路由自动选择账号类型${gl_bai}"
    echo ""

    break_end
}

# 卸载
crs_uninstall() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_hong}  卸载 Claude Relay Service${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    local status=$(crs_check_status)
    if [ "$status" = "not_installed" ]; then
        echo -e "${gl_hong}❌ CRS 未安装${gl_bai}"
        break_end
        return 1
    fi

    local install_dir=$(crs_get_install_dir)

    echo -e "${gl_hong}⚠️ 警告: 此操作将删除 CRS 服务和所有数据！${gl_bai}"
    echo ""
    echo "安装目录: $install_dir"
    echo ""

    read -e -p "确认卸载？(输入 yes 确认): " confirm

    if [ "$confirm" != "yes" ]; then
        echo "已取消"
        break_end
        return 0
    fi

    echo ""
    echo "正在卸载..."

    # 使用 crs uninstall 命令
    if command -v crs &>/dev/null; then
        crs uninstall
    else
        # 手动卸载
        echo "正在停止服务..."
        # 尝试停止 pm2 进程
        pm2 stop crs 2>/dev/null
        pm2 delete crs 2>/dev/null

        echo "正在删除文件..."
        rm -rf "$install_dir"
    fi

    # 删除配置文件
    rm -f "$CRS_PORT_FILE"
    rm -f "$CRS_INSTALL_DIR_FILE"

    # 删除 crs 命令
    rm -f /usr/local/bin/crs 2>/dev/null

    echo ""
    echo -e "${gl_lv}✅ 卸载完成${gl_bai}"

    break_end
}

# CRS 主菜单
manage_crs() {
    while true; do
        clear
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_kjlan}  Claude Relay Service (CRS) 部署管理${gl_bai}"
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""

        # 显示当前状态
        local status=$(crs_check_status)
        local port=$(crs_get_port)

        case "$status" in
            "running")
                echo -e "当前状态: ${gl_lv}✅ 运行中${gl_bai} (端口: $port)"
                ;;
            "stopped")
                echo -e "当前状态: ${gl_hong}❌ 已停止${gl_bai}"
                ;;
            "installed_no_command")
                echo -e "当前状态: ${gl_huang}⚠️ 已安装但命令不可用${gl_bai}"
                ;;
            "not_installed")
                echo -e "当前状态: ${gl_hui}未安装${gl_bai}"
                ;;
        esac

        echo ""
        echo -e "${gl_kjlan}[部署与更新]${gl_bai}"
        echo "1. 一键部署（首次安装）"
        echo "2. 更新服务"
        echo ""
        echo -e "${gl_kjlan}[服务管理]${gl_bai}"
        echo "3. 查看状态"
        echo "4. 查看日志"
        echo "5. 启动服务"
        echo "6. 停止服务"
        echo "7. 重启服务"
        echo ""
        echo -e "${gl_kjlan}[配置与信息]${gl_bai}"
        echo "8. 查看管理员账号"
        echo "9. 修改端口"
        echo "10. 查看配置指引"
        echo ""
        echo -e "${gl_kjlan}[卸载]${gl_bai}"
        echo -e "${gl_hong}99. 卸载（删除服务+数据）${gl_bai}"
        echo ""
        echo "0. 返回主菜单"
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"

        read -e -p "请选择操作 [0-10, 99]: " choice

        case $choice in
            1)
                crs_deploy
                ;;
            2)
                crs_update
                ;;
            3)
                crs_status
                ;;
            4)
                crs_logs
                ;;
            5)
                crs_start
                ;;
            6)
                crs_stop
                ;;
            7)
                crs_restart
                ;;
            8)
                crs_show_admin
                ;;
            9)
                crs_change_port
                ;;
            10)
                crs_show_config
                ;;
            99)
                crs_uninstall
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

# =====================================================
# Sub2API 部署管理
# =====================================================

# 常量定义
SUB2API_SERVICE_NAME="sub2api"
SUB2API_INSTALL_DIR="/opt/sub2api"
SUB2API_CONFIG_DIR="/etc/sub2api"
SUB2API_DEFAULT_PORT="8282"
SUB2API_PORT_FILE="/etc/sub2api-port"
SUB2API_INSTALL_SCRIPT="https://raw.githubusercontent.com/Wei-Shaw/sub2api/main/deploy/install.sh"

# 获取当前配置的端口
sub2api_get_port() {
    if [ -f "$SUB2API_PORT_FILE" ]; then
        cat "$SUB2API_PORT_FILE"
    else
        echo "$SUB2API_DEFAULT_PORT"
    fi
}

# 检查端口是否可用
sub2api_check_port() {
    local port=$1
    if ss -lntp 2>/dev/null | grep -q ":${port} "; then
        return 1
    fi
    return 0
}

# 检测 Sub2API 状态
sub2api_check_status() {
    if [ ! -d "$SUB2API_INSTALL_DIR" ] && [ ! -f "/etc/systemd/system/sub2api.service" ]; then
        echo "not_installed"
    elif systemctl is-active "$SUB2API_SERVICE_NAME" &>/dev/null; then
        echo "running"
    else
        echo "stopped"
    fi
}

# 从 systemd 服务文件提取端口
sub2api_extract_port() {
    local service_file="/etc/systemd/system/sub2api.service"
    if [ -f "$service_file" ]; then
        # 尝试从 ExecStart 行提取端口
        local port=$(sed -nE 's/.*:([0-9]+).*/\1/p' "$service_file" 2>/dev/null | head -1)
        if [ -n "$port" ]; then
            echo "$port"
            return
        fi
    fi
    echo "$SUB2API_DEFAULT_PORT"
}

# 安装 PostgreSQL 并创建数据库
sub2api_setup_postgres() {
    echo -e "${gl_kjlan}[1/4] 安装 PostgreSQL 数据库...${gl_bai}"

    if command -v psql &>/dev/null; then
        echo -e "${gl_lv}✅ PostgreSQL 已安装${gl_bai}"
    else
        echo "正在安装 PostgreSQL..."
        apt-get update -qq 2>/dev/null
        apt-get install -y -qq postgresql postgresql-contrib > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${gl_hong}❌ PostgreSQL 安装失败${gl_bai}"
            return 1
        fi
        echo -e "${gl_lv}✅ PostgreSQL 安装完成${gl_bai}"
    fi

    # 确保 PostgreSQL 运行
    systemctl start postgresql 2>/dev/null
    systemctl enable postgresql 2>/dev/null

    # 生成随机密码
    SUB2API_DB_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)
    SUB2API_DB_USER="sub2api"
    SUB2API_DB_NAME="sub2api"

    # 创建用户和数据库（如果不存在）
    echo "正在配置数据库..."
    sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='$SUB2API_DB_USER'" | grep -q 1 || \
        sudo -u postgres psql -c "CREATE USER $SUB2API_DB_USER WITH PASSWORD '$SUB2API_DB_PASSWORD';" > /dev/null 2>&1

    # 如果用户已存在，更新密码
    sudo -u postgres psql -c "ALTER USER $SUB2API_DB_USER WITH PASSWORD '$SUB2API_DB_PASSWORD';" > /dev/null 2>&1

    sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='$SUB2API_DB_NAME'" | grep -q 1 || \
        sudo -u postgres psql -c "CREATE DATABASE $SUB2API_DB_NAME OWNER $SUB2API_DB_USER;" > /dev/null 2>&1

    # 验证连接
    if PGPASSWORD="$SUB2API_DB_PASSWORD" psql -h localhost -U "$SUB2API_DB_USER" -d "$SUB2API_DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
        echo -e "${gl_lv}✅ 数据库配置完成，连接正常${gl_bai}"
    else
        # 可能需要修改 pg_hba.conf 允许密码认证
        local pg_hba=$(find /etc/postgresql -name pg_hba.conf 2>/dev/null | head -1)
        if [ -n "$pg_hba" ]; then
            # 检查是否已有 sub2api 的规则
            if ! grep -q "sub2api" "$pg_hba"; then
                # 在文件开头添加密码认证规则
                sed -i "1i host    sub2api    sub2api    127.0.0.1/32    md5" "$pg_hba"
                sed -i "2i host    sub2api    sub2api    ::1/128         md5" "$pg_hba"
                systemctl restart postgresql
                echo -e "${gl_lv}✅ 数据库认证已配置${gl_bai}"
            fi
        fi

        # 再次验证
        if PGPASSWORD="$SUB2API_DB_PASSWORD" psql -h localhost -U "$SUB2API_DB_USER" -d "$SUB2API_DB_NAME" -c "SELECT 1" > /dev/null 2>&1; then
            echo -e "${gl_lv}✅ 数据库配置完成，连接正常${gl_bai}"
        else
            echo -e "${gl_huang}⚠️ 数据库已创建，但本地连接验证未通过（不影响使用）${gl_bai}"
        fi
    fi

    # 保存数据库信息到文件
    cat > "$SUB2API_CONFIG_DIR/db-info" << EOF
DB_HOST=localhost
DB_PORT=5432
DB_USER=$SUB2API_DB_USER
DB_PASSWORD=$SUB2API_DB_PASSWORD
DB_NAME=$SUB2API_DB_NAME
EOF
    chmod 600 "$SUB2API_CONFIG_DIR/db-info"
    return 0
}

# 安装 Redis
sub2api_setup_redis() {
    echo -e "${gl_kjlan}[2/4] 安装 Redis...${gl_bai}"

    if command -v redis-cli &>/dev/null; then
        echo -e "${gl_lv}✅ Redis 已安装${gl_bai}"
    else
        echo "正在安装 Redis..."
        apt-get install -y -qq redis-server > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${gl_hong}❌ Redis 安装失败${gl_bai}"
            return 1
        fi
        echo -e "${gl_lv}✅ Redis 安装完成${gl_bai}"
    fi

    systemctl start redis-server 2>/dev/null
    systemctl enable redis-server 2>/dev/null

    # 验证 Redis
    if redis-cli ping 2>/dev/null | grep -q "PONG"; then
        echo -e "${gl_lv}✅ Redis 运行正常${gl_bai}"
    else
        echo -e "${gl_huang}⚠️ Redis 可能未正常运行，请检查${gl_bai}"
    fi
    return 0
}

# 一键部署
sub2api_deploy() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  一键部署 Sub2API${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    # 检查是否已安装
    local status=$(sub2api_check_status)
    if [ "$status" != "not_installed" ]; then
        echo -e "${gl_huang}⚠️ Sub2API 已安装${gl_bai}"
        read -e -p "是否重新部署？(y/n) [n]: " reinstall
        if [ "$reinstall" != "y" ] && [ "$reinstall" != "Y" ]; then
            break_end
            return 0
        fi
        # 停止现有服务
        systemctl stop "$SUB2API_SERVICE_NAME" 2>/dev/null
    fi

    # 创建配置目录
    mkdir -p "$SUB2API_CONFIG_DIR"

    # 安装 PostgreSQL
    echo ""
    sub2api_setup_postgres || { break_end; return 1; }

    # 安装 Redis
    echo ""
    sub2api_setup_redis || { break_end; return 1; }

    # 执行官方安装脚本
    echo ""
    echo -e "${gl_kjlan}[3/4] 执行官方安装脚本...${gl_bai}"
    echo ""
    echo -e "${gl_huang}提示: 官方脚本会询问地址和端口${gl_bai}"
    echo -e "${gl_zi}  → 地址: 直接回车（默认 0.0.0.0）${gl_bai}"
    echo -e "${gl_zi}  → 端口: 建议输入 ${SUB2API_DEFAULT_PORT}（避免与其他服务冲突）${gl_bai}"
    echo ""
    read -e -p "按回车开始安装..." _
    echo ""

    bash <(curl -fsSL "$SUB2API_INSTALL_SCRIPT")
    local install_result=$?

    if [ $install_result -ne 0 ]; then
        echo -e "${gl_hong}❌ 安装失败${gl_bai}"
        break_end
        return 1
    fi

    # 从服务文件提取端口并保存
    echo ""
    echo -e "${gl_kjlan}[4/4] 验证安装...${gl_bai}"
    local port=$(sub2api_extract_port)
    echo "$port" > "$SUB2API_PORT_FILE"

    # 获取服务器 IP
    local server_ip=$(curl -s4 ip.sb 2>/dev/null || curl -s6 ip.sb 2>/dev/null || echo "服务器IP")

    echo ""
    echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_lv}  ✅ 部署完成！${gl_bai}"
    echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    echo -e "Web 管理面板: ${gl_huang}http://${server_ip}:${port}/setup${gl_bai}"
    echo ""
    echo -e "${gl_kjlan}【网页初始化配置 - 请照抄以下信息】${gl_bai}"
    echo ""
    echo -e "${gl_kjlan}  第1步 - 数据库配置:${gl_bai}"
    echo -e "    主持人:     ${gl_huang}localhost${gl_bai}"
    echo -e "    端口:       ${gl_huang}5432${gl_bai}"
    echo -e "    用户名:     ${gl_huang}${SUB2API_DB_USER}${gl_bai}"
    echo -e "    密码:       ${gl_huang}${SUB2API_DB_PASSWORD}${gl_bai}"
    echo -e "    数据库名称: ${gl_huang}${SUB2API_DB_NAME}${gl_bai}"
    echo -e "    SSL 模式:   ${gl_huang}禁用${gl_bai}"
    echo ""
    echo -e "${gl_kjlan}  第2步 - Redis 配置:${gl_bai}"
    echo -e "    主持人:     ${gl_huang}localhost${gl_bai}"
    echo -e "    端口:       ${gl_huang}6379${gl_bai}"
    echo -e "    密码:       ${gl_huang}（留空，直接下一步）${gl_bai}"
    echo ""
    echo -e "${gl_kjlan}  第3步 - 管理员帐户:${gl_bai}"
    echo -e "    自己设置用户名和密码"
    echo ""
    echo -e "${gl_kjlan}  第4步 - 准备安装:${gl_bai}"
    echo -e "    点击安装即可"
    echo ""
    echo -e "${gl_zi}提示: 以上数据库信息已保存到 ${SUB2API_CONFIG_DIR}/db-info${gl_bai}"
    echo ""
    echo -e "${gl_kjlan}【完成初始化后 - Claude Code 配置】${gl_bai}"
    echo -e "  ${gl_huang}export ANTHROPIC_BASE_URL=\"http://${server_ip}:${port}/antigravity\"${gl_bai}"
    echo -e "  ${gl_huang}export ANTHROPIC_AUTH_TOKEN=\"后台创建的API密钥\"${gl_bai}"
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}管理命令:${gl_bai}"
    echo "  状态: systemctl status sub2api"
    echo "  启动: systemctl start sub2api"
    echo "  停止: systemctl stop sub2api"
    echo "  重启: systemctl restart sub2api"
    echo "  日志: journalctl -u sub2api -f"
    echo ""

    break_end
}

# 启动服务
sub2api_start() {
    echo "正在启动 Sub2API..."
    systemctl start "$SUB2API_SERVICE_NAME"
    sleep 1
    if systemctl is-active "$SUB2API_SERVICE_NAME" &>/dev/null; then
        echo -e "${gl_lv}✅ 启动成功${gl_bai}"
    else
        echo -e "${gl_hong}❌ 启动失败${gl_bai}"
    fi
    break_end
}

# 停止服务
sub2api_stop() {
    echo "正在停止 Sub2API..."
    systemctl stop "$SUB2API_SERVICE_NAME"
    sleep 1
    if ! systemctl is-active "$SUB2API_SERVICE_NAME" &>/dev/null; then
        echo -e "${gl_lv}✅ 已停止${gl_bai}"
    else
        echo -e "${gl_hong}❌ 停止失败${gl_bai}"
    fi
    break_end
}

# 重启服务
sub2api_restart() {
    echo "正在重启 Sub2API..."
    systemctl restart "$SUB2API_SERVICE_NAME"
    sleep 1
    if systemctl is-active "$SUB2API_SERVICE_NAME" &>/dev/null; then
        echo -e "${gl_lv}✅ 重启成功${gl_bai}"
    else
        echo -e "${gl_hong}❌ 重启失败${gl_bai}"
    fi
    break_end
}

# 查看状态
sub2api_view_status() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  Sub2API 服务状态${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    local port=$(sub2api_get_port)
    local server_ip=$(curl -s4 --max-time 3 ip.sb 2>/dev/null || echo "获取中...")

    echo -e "服务状态: $(systemctl is-active $SUB2API_SERVICE_NAME 2>/dev/null || echo '未知')"
    echo -e "访问端口: ${gl_huang}${port}${gl_bai}"
    echo -e "访问地址: ${gl_huang}http://${server_ip}:${port}${gl_bai}"
    echo ""
    echo -e "${gl_kjlan}--- systemctl status ---${gl_bai}"
    systemctl status "$SUB2API_SERVICE_NAME" --no-pager 2>/dev/null || echo "服务未安装"
    echo ""

    break_end
}

# 修改端口
sub2api_change_port() {
    local current_port=$(sub2api_get_port)
    echo ""
    echo -e "当前端口: ${gl_huang}${current_port}${gl_bai}"
    echo ""
    read -e -p "请输入新端口: " new_port

    if [ -z "$new_port" ]; then
        echo "已取消"
        break_end
        return
    fi

    # 检查端口是否被占用
    if ! sub2api_check_port "$new_port"; then
        echo -e "${gl_hong}❌ 端口 $new_port 已被占用${gl_bai}"
        break_end
        return 1
    fi

    echo ""
    echo "正在修改端口..."

    # 修改 systemd 服务文件中的端口
    local service_file="/etc/systemd/system/sub2api.service"
    if [ -f "$service_file" ]; then
        sed -i "s/:${current_port}/:${new_port}/g" "$service_file"
        sed -i "s/=${current_port}/=${new_port}/g" "$service_file"
    fi

    # 保存新端口
    echo "$new_port" > "$SUB2API_PORT_FILE"

    # 重载并重启服务
    systemctl daemon-reload
    systemctl restart "$SUB2API_SERVICE_NAME"

    sleep 1
    if systemctl is-active "$SUB2API_SERVICE_NAME" &>/dev/null; then
        echo -e "${gl_lv}✅ 端口已修改为 ${new_port}${gl_bai}"
    else
        echo -e "${gl_hong}❌ 服务重启失败，请检查配置${gl_bai}"
    fi

    break_end
}

# 查看日志
sub2api_view_logs() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  Sub2API 运行日志 (最近 50 行)${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    journalctl -u "$SUB2API_SERVICE_NAME" -n 50 --no-pager
    echo ""
    break_end
}

# 更新服务
sub2api_update() {
    local status=$(sub2api_check_status)
    if [ "$status" = "not_installed" ]; then
        echo -e "${gl_hong}❌ Sub2API 未安装，请先执行一键部署${gl_bai}"
        break_end
        return 1
    fi

    echo -e "${gl_kjlan}正在执行官方升级脚本...${gl_bai}"
    echo ""

    local tmp_script=$(mktemp)
    if ! curl -fsSL "$SUB2API_INSTALL_SCRIPT" -o "$tmp_script"; then
        echo -e "${gl_hong}❌ 下载升级脚本失败${gl_bai}"
        rm -f "$tmp_script"
        break_end
        return 1
    fi

    chmod +x "$tmp_script"
    bash "$tmp_script" upgrade
    local result=$?
    rm -f "$tmp_script"

    if [ $result -eq 0 ]; then
        echo -e "${gl_lv}✅ 升级完成${gl_bai}"
    else
        echo -e "${gl_hong}❌ 升级失败${gl_bai}"
    fi

    break_end
}

# 查看配置信息
sub2api_show_config() {
    clear

    local status=$(sub2api_check_status)
    if [ "$status" = "not_installed" ]; then
        echo -e "${gl_hong}❌ Sub2API 未安装，请先执行一键部署${gl_bai}"
        break_end
        return 1
    fi

    local port=$(sub2api_get_port)
    local server_ip=$(curl -s4 --max-time 3 ip.sb 2>/dev/null || curl -s6 --max-time 3 ip.sb 2>/dev/null || echo "服务器IP")

    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  Sub2API 配置信息${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    echo -e "Web 管理面板: ${gl_huang}http://${server_ip}:${port}${gl_bai}"
    echo -e "设置向导:     ${gl_huang}http://${server_ip}:${port}/setup${gl_bai}"
    echo ""

    # 读取数据库信息
    local db_info_file="$SUB2API_CONFIG_DIR/db-info"
    if [ -f "$db_info_file" ]; then
        local db_user=$(grep "DB_USER=" "$db_info_file" | cut -d= -f2)
        local db_pass=$(grep "DB_PASSWORD=" "$db_info_file" | cut -d= -f2)
        local db_name=$(grep "DB_NAME=" "$db_info_file" | cut -d= -f2)

        echo -e "${gl_kjlan}【数据库配置】${gl_bai}"
        echo -e "  主持人:     ${gl_huang}localhost${gl_bai}"
        echo -e "  端口:       ${gl_huang}5432${gl_bai}"
        echo -e "  用户名:     ${gl_huang}${db_user}${gl_bai}"
        echo -e "  密码:       ${gl_huang}${db_pass}${gl_bai}"
        echo -e "  数据库名称: ${gl_huang}${db_name}${gl_bai}"
        echo -e "  SSL 模式:   ${gl_huang}禁用${gl_bai}"
        echo ""
        echo -e "${gl_kjlan}【Redis 配置】${gl_bai}"
        echo -e "  主持人:     ${gl_huang}localhost${gl_bai}"
        echo -e "  端口:       ${gl_huang}6379${gl_bai}"
        echo -e "  密码:       ${gl_huang}（留空）${gl_bai}"
        echo ""
    else
        echo -e "${gl_huang}⚠️ 未找到数据库配置文件（旧版本部署）${gl_bai}"
        echo -e "  文件路径: ${SUB2API_CONFIG_DIR}/db-info"
        echo ""
    fi

    echo -e "${gl_kjlan}【Claude Code 配置】${gl_bai}"
    echo -e "  ${gl_huang}export ANTHROPIC_BASE_URL=\"http://${server_ip}:${port}/antigravity\"${gl_bai}"
    echo -e "  ${gl_huang}export ANTHROPIC_AUTH_TOKEN=\"后台创建的API密钥\"${gl_bai}"
    echo ""
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}管理命令:${gl_bai}"
    echo "  状态: systemctl status sub2api"
    echo "  启动: systemctl start sub2api"
    echo "  停止: systemctl stop sub2api"
    echo "  重启: systemctl restart sub2api"
    echo "  日志: journalctl -u sub2api -f"
    echo ""

    break_end
}

# 卸载
sub2api_uninstall() {
    echo ""
    echo -e "${gl_hong}⚠️ 此操作将卸载 Sub2API 并删除所有配置数据${gl_bai}"
    read -e -p "确定要卸载吗？(y/n) [n]: " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "已取消"
        break_end
        return
    fi

    echo ""
    echo "正在执行官方卸载脚本..."

    # 使用官方卸载命令
    local tmp_script=$(mktemp)
    if curl -fsSL "$SUB2API_INSTALL_SCRIPT" -o "$tmp_script" 2>/dev/null; then
        chmod +x "$tmp_script"
        bash "$tmp_script" uninstall -y --purge
        rm -f "$tmp_script"
    else
        # 官方脚本下载失败，手动卸载
        echo "官方脚本下载失败，执行手动卸载..."
        systemctl stop "$SUB2API_SERVICE_NAME" 2>/dev/null
        systemctl disable "$SUB2API_SERVICE_NAME" 2>/dev/null
        rm -f "/etc/systemd/system/sub2api.service"
        systemctl daemon-reload
        rm -rf "$SUB2API_INSTALL_DIR"
        userdel sub2api 2>/dev/null
    fi

    # 清理我们自己的配置文件
    rm -rf "$SUB2API_CONFIG_DIR"
    rm -f "$SUB2API_PORT_FILE"

    echo -e "${gl_lv}✅ 卸载完成${gl_bai}"
    break_end
}

# Sub2API 管理主菜单
manage_sub2api() {
    while true; do
        clear
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_kjlan}  Sub2API 部署管理${gl_bai}"
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""

        # 显示当前状态
        local status=$(sub2api_check_status)
        local port=$(sub2api_get_port)

        case "$status" in
            "running")
                echo -e "当前状态: ${gl_lv}✅ 运行中${gl_bai} (端口: $port)"
                ;;
            "stopped")
                echo -e "当前状态: ${gl_hong}❌ 已停止${gl_bai}"
                ;;
            "not_installed")
                echo -e "当前状态: ${gl_hui}未安装${gl_bai}"
                ;;
        esac
        echo ""

        echo -e "${gl_kjlan}[部署与更新]${gl_bai}"
        echo "1. 一键部署（首次安装）"
        echo "2. 更新服务"
        echo ""
        echo -e "${gl_kjlan}[服务管理]${gl_bai}"
        echo "3. 查看状态"
        echo "4. 查看日志"
        echo "5. 启动服务"
        echo "6. 停止服务"
        echo "7. 重启服务"
        echo ""
        echo -e "${gl_kjlan}[配置与信息]${gl_bai}"
        echo "8. 查看配置信息"
        echo "9. 修改端口"
        echo ""
        echo -e "${gl_kjlan}[卸载]${gl_bai}"
        echo -e "${gl_hong}99. 卸载（删除服务+数据）${gl_bai}"
        echo ""
        echo "0. 返回上级菜单"
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"

        read -e -p "请选择操作 [0-9, 99]: " choice

        case $choice in
            1)
                sub2api_deploy
                ;;
            2)
                sub2api_update
                ;;
            3)
                sub2api_view_status
                ;;
            4)
                sub2api_view_logs
                ;;
            5)
                sub2api_start
                ;;
            6)
                sub2api_stop
                ;;
            7)
                sub2api_restart
                ;;
            8)
                sub2api_show_config
                ;;
            9)
                sub2api_change_port
                ;;
            99)
                sub2api_uninstall
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

# =====================================================
# OpenClaw 部署管理 (AI多渠道消息网关)
# =====================================================

# 常量定义
OPENCLAW_SERVICE_NAME="openclaw-gateway"
OPENCLAW_HOME_DIR="${HOME}/.openclaw"
OPENCLAW_CONFIG_FILE="${HOME}/.openclaw/openclaw.json"
OPENCLAW_ENV_FILE="${HOME}/.openclaw/.env"
OPENCLAW_DEFAULT_PORT="18789"

# 检测 OpenClaw 状态
openclaw_check_status() {
    if ! command -v openclaw &>/dev/null; then
        echo "not_installed"
    elif systemctl is-active "$OPENCLAW_SERVICE_NAME" &>/dev/null; then
        echo "running"
    elif systemctl is-enabled "$OPENCLAW_SERVICE_NAME" &>/dev/null; then
        echo "stopped"
    else
        echo "installed_no_service"
    fi
}

# 获取当前端口
openclaw_get_port() {
    if [ -f "$OPENCLAW_CONFIG_FILE" ]; then
        # 兼容 JSON5 格式（key 无引号: port: 19966）和标准 JSON（"port": 19966）
        local port=$(sed -nE 's/.*"?port"?[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "$OPENCLAW_CONFIG_FILE" 2>/dev/null | head -1)
        if [ -n "$port" ]; then
            echo "$port"
            return
        fi
    fi
    echo "$OPENCLAW_DEFAULT_PORT"
}

# 检查端口是否可用
openclaw_check_port() {
    local port=$1
    if ss -lntp 2>/dev/null | grep -q ":${port} "; then
        return 1
    fi
    return 0
}

# 检测并安装 Node.js 22+
openclaw_install_nodejs() {
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

    echo "正在安装 Node.js 22..."

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        local os_id="${ID,,}"
    fi

    local setup_script=$(mktemp)
    local script_url=""

    if [[ "$os_id" == "debian" || "$os_id" == "ubuntu" ]]; then
        script_url="https://deb.nodesource.com/setup_22.x"
    elif [[ "$os_id" == "centos" || "$os_id" == "rhel" || "$os_id" == "fedora" || "$os_id" == "rocky" || "$os_id" == "alma" ]]; then
        script_url="https://rpm.nodesource.com/setup_22.x"
    fi

    if [ -n "$script_url" ]; then
        if ! curl -fsSL --connect-timeout 15 --max-time 60 "$script_url" -o "$setup_script" 2>/dev/null; then
            echo -e "${gl_hong}❌ 下载 Node.js 设置脚本失败${gl_bai}"
            rm -f "$setup_script"
            return 1
        fi

        if ! head -1 "$setup_script" | grep -q "^#!"; then
            echo -e "${gl_hong}❌ 脚本格式验证失败${gl_bai}"
            rm -f "$setup_script"
            return 1
        fi

        chmod +x "$setup_script"
        bash "$setup_script" >/dev/null 2>&1
        rm -f "$setup_script"
    fi

    if [[ "$os_id" == "debian" || "$os_id" == "ubuntu" ]]; then
        apt-get install -y nodejs >/dev/null 2>&1
    elif [[ "$os_id" == "centos" || "$os_id" == "rhel" || "$os_id" == "fedora" || "$os_id" == "rocky" || "$os_id" == "alma" ]]; then
        if command -v dnf &>/dev/null; then
            dnf install -y nodejs >/dev/null 2>&1
        else
            yum install -y nodejs >/dev/null 2>&1
        fi
    else
        echo -e "${gl_hong}❌ 不支持的系统，请手动安装 Node.js 22+${gl_bai}"
        return 1
    fi

    if command -v node &>/dev/null; then
        local installed_ver=$(node -v | sed 's/v//' | cut -d. -f1)
        if [ "$installed_ver" -ge 22 ]; then
            echo -e "${gl_lv}✅ Node.js $(node -v) 安装成功${gl_bai}"
            return 0
        else
            echo -e "${gl_hong}❌ 安装的 Node.js 版本仍低于 22，请手动升级${gl_bai}"
            return 1
        fi
    else
        echo -e "${gl_hong}❌ Node.js 安装失败${gl_bai}"
        return 1
    fi
}

# 安装 OpenClaw
openclaw_install_pkg() {
    echo -e "${gl_kjlan}[2/4] 安装 OpenClaw...${gl_bai}"
    echo -e "${gl_hui}正在下载并安装，可能需要 1-3 分钟...${gl_bai}"
    echo ""

    npm install -g openclaw@latest --loglevel info

    if command -v openclaw &>/dev/null; then
        local ver=$(openclaw --version 2>/dev/null || echo "unknown")
        echo -e "${gl_lv}✅ OpenClaw ${ver} 安装成功${gl_bai}"
        return 0
    else
        echo -e "${gl_hong}❌ OpenClaw 安装失败${gl_bai}"
        return 1
    fi
}

# 交互式模型配置
openclaw_config_model() {
    clear
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

# 执行 onboard 初始化
openclaw_onboard() {
    local port=$(openclaw_get_port)
    echo -e "${gl_kjlan}[4/4] 创建 systemd 服务并启动网关...${gl_bai}"
    echo ""

    # 创建必要的目录
    mkdir -p "${OPENCLAW_HOME_DIR}/agents/main/sessions"
    mkdir -p "${OPENCLAW_HOME_DIR}/credentials"
    mkdir -p "${OPENCLAW_HOME_DIR}/workspace"

    # 获取 openclaw 实际路径
    local openclaw_bin=$(which openclaw 2>/dev/null || echo "/usr/bin/openclaw")

    # 创建 systemd 服务
    cat > "/etc/systemd/system/${OPENCLAW_SERVICE_NAME}.service" <<EOF
[Unit]
Description=OpenClaw Gateway
After=network.target

[Service]
Type=simple
ExecStart=${openclaw_bin} gateway --port ${port} --verbose
Restart=always
RestartSec=5
EnvironmentFile=-${HOME}/.openclaw/.env
Environment=HOME=${HOME}
WorkingDirectory=${HOME}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$OPENCLAW_SERVICE_NAME" >/dev/null 2>&1
    systemctl start "$OPENCLAW_SERVICE_NAME"

    sleep 5

    if systemctl is-active "$OPENCLAW_SERVICE_NAME" &>/dev/null; then
        echo -e "${gl_lv}✅ OpenClaw 网关已启动${gl_bai}"
        return 0
    else
        echo -e "${gl_hong}❌ 网关启动失败，查看日志:${gl_bai}"
        journalctl -u "$OPENCLAW_SERVICE_NAME" -n 10 --no-pager
        return 1
    fi
}

# 一键部署
openclaw_deploy() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  OpenClaw 一键部署${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    local status=$(openclaw_check_status)
    if [ "$status" = "running" ]; then
        echo -e "${gl_huang}⚠ OpenClaw 已在运行中${gl_bai}"
        echo ""
        read -e -p "是否重新部署？(Y/N): " confirm
        case "$confirm" in
            [Yy]) ;;
            *) return ;;
        esac
        echo ""
        systemctl stop "$OPENCLAW_SERVICE_NAME" 2>/dev/null
    fi

    # 步骤1: Node.js
    openclaw_install_nodejs || { break_end; return 1; }
    echo ""

    # 步骤2: 安装 OpenClaw
    openclaw_install_pkg || { break_end; return 1; }
    echo ""

    # 步骤3: 交互式模型配置
    echo -e "${gl_kjlan}[3/4] 配置模型与 API...${gl_bai}"
    echo ""
    openclaw_config_model || { break_end; return 1; }
    echo ""

    # 步骤4: 初始化并启动
    openclaw_onboard || { break_end; return 1; }

    # 获取服务器 IP
    local server_ip=$(curl -s4 ip.sb 2>/dev/null || curl -s6 ip.sb 2>/dev/null || echo "服务器IP")
    local port=$(openclaw_get_port)

    echo ""
    echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_lv}  ✅ OpenClaw 部署完成！${gl_bai}"
    echo -e "${gl_lv}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    echo -e "控制面板: ${gl_huang}http://${server_ip}:${port}/${gl_bai}"
    echo ""

    # 显示 gateway token
    local gw_token=$(sed -nE 's/.*OPENCLAW_GATEWAY_TOKEN=(.*)/\1/p' "$OPENCLAW_ENV_FILE" 2>/dev/null)
    if [ -n "$gw_token" ]; then
        echo -e "网关 Token: ${gl_huang}${gw_token}${gl_bai}"
        echo -e "${gl_zi}（远程访问控制面板时需要此 Token）${gl_bai}"
        echo ""
    fi

    echo -e "${gl_kjlan}【下一步】连接消息频道${gl_bai}"
    echo "  运行: openclaw channels login"
    echo "  支持: WhatsApp / Telegram / Discord / Slack 等"
    echo ""
    echo -e "${gl_kjlan}【聊天命令】（在消息平台中使用）${gl_bai}"
    echo "  /status  — 查看会话状态"
    echo "  /new     — 清空上下文"
    echo "  /think   — 调整推理级别"
    echo ""
    echo -e "${gl_kjlan}【安全说明】${gl_bai}"
    echo "  网关默认绑定 loopback，外部访问需 SSH 隧道:"
    echo -e "  ${gl_huang}ssh -N -L ${port}:127.0.0.1:${port} root@${server_ip}${gl_bai}"
    echo "  检查安全: openclaw doctor"
    echo ""
    echo -e "${gl_kjlan}管理命令:${gl_bai}"
    echo "  状态: systemctl status $OPENCLAW_SERVICE_NAME"
    echo "  日志: journalctl -u $OPENCLAW_SERVICE_NAME -f"
    echo "  重启: systemctl restart $OPENCLAW_SERVICE_NAME"
    echo ""

    break_end
}

# 更新 OpenClaw
openclaw_update() {
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
    systemctl restart "$OPENCLAW_SERVICE_NAME" 2>/dev/null

    sleep 2
    if systemctl is-active "$OPENCLAW_SERVICE_NAME" &>/dev/null; then
        echo -e "${gl_lv}✅ 服务已重启${gl_bai}"
    else
        echo -e "${gl_huang}⚠ 服务未通过 systemctl 管理，请手动重启${gl_bai}"
    fi

    break_end
}

# 查看状态
openclaw_status() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  OpenClaw 服务状态${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    if command -v openclaw &>/dev/null; then
        echo -e "版本: ${gl_huang}$(openclaw --version 2>/dev/null || echo 'unknown')${gl_bai}"
        echo ""
    fi

    systemctl status "$OPENCLAW_SERVICE_NAME" --no-pager 2>/dev/null || \
        echo -e "${gl_huang}⚠ systemd 服务不存在，可能需要重新执行 onboard${gl_bai}"

    echo ""
    break_end
}

# 查看日志
openclaw_logs() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_kjlan}  OpenClaw 日志（按 Ctrl+C 退出）${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""

    journalctl -u "$OPENCLAW_SERVICE_NAME" -f 2>/dev/null || \
        echo -e "${gl_huang}⚠ 无法读取日志，服务可能未通过 systemd 管理${gl_bai}"
}

# 启动服务
openclaw_start() {
    echo "正在启动服务..."
    systemctl start "$OPENCLAW_SERVICE_NAME" 2>/dev/null
    sleep 2

    if systemctl is-active "$OPENCLAW_SERVICE_NAME" &>/dev/null; then
        echo -e "${gl_lv}✅ 服务已启动${gl_bai}"
    else
        echo -e "${gl_hong}❌ 服务启动失败，查看日志: journalctl -u $OPENCLAW_SERVICE_NAME -n 20${gl_bai}"
    fi

    break_end
}

# 停止服务
openclaw_stop() {
    echo "正在停止服务..."
    systemctl stop "$OPENCLAW_SERVICE_NAME" 2>/dev/null

    if ! systemctl is-active "$OPENCLAW_SERVICE_NAME" &>/dev/null; then
        echo -e "${gl_lv}✅ 服务已停止${gl_bai}"
    else
        echo -e "${gl_hong}❌ 服务停止失败${gl_bai}"
    fi

    break_end
}

# 重启服务
openclaw_restart() {
    echo "正在重启服务..."

    local port=$(openclaw_get_port)
    local pid=$(ss -lntp 2>/dev/null | grep ":${port} " | sed -nE 's/.*pid=([0-9]+).*/\1/p' | head -1)
    local service_pid=$(systemctl show -p MainPID "$OPENCLAW_SERVICE_NAME" 2>/dev/null | cut -d= -f2)

    if [ -n "$pid" ] && [ "$pid" != "$service_pid" ] && [ "$pid" != "0" ]; then
        echo -e "${gl_huang}⚠ 端口 ${port} 被 PID ${pid} 占用，正在释放...${gl_bai}"
        kill "$pid" 2>/dev/null
        sleep 1
        if ss -lntp 2>/dev/null | grep -q ":${port} "; then
            kill -9 "$pid" 2>/dev/null
            sleep 1
        fi
    fi

    systemctl restart "$OPENCLAW_SERVICE_NAME" 2>/dev/null
    sleep 2

    if systemctl is-active "$OPENCLAW_SERVICE_NAME" &>/dev/null; then
        echo -e "${gl_lv}✅ 服务已重启${gl_bai}"
    else
        echo -e "${gl_hong}❌ 服务重启失败${gl_bai}"
        echo "查看日志: journalctl -u $OPENCLAW_SERVICE_NAME -n 20"
    fi

    break_end
}

# 更新频道配置到 openclaw.json（通过 Node.js 合并 JSON5）
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

# 从 openclaw.json 移除频道配置
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

# 频道管理菜单
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
                    echo -e "  3. 在服务器运行: ${gl_huang}openclaw pairing approve telegram <配对码>${gl_bai}"

                    if systemctl is-active "$OPENCLAW_SERVICE_NAME" &>/dev/null; then
                        systemctl restart "$OPENCLAW_SERVICE_NAME" 2>/dev/null
                        sleep 2
                        echo ""
                        echo -e "${gl_lv}✅ 服务已重启，配置已生效${gl_bai}"
                    fi
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

                            if systemctl is-active "$OPENCLAW_SERVICE_NAME" &>/dev/null; then
                                systemctl restart "$OPENCLAW_SERVICE_NAME" 2>/dev/null
                                sleep 2
                            fi

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

                    if systemctl is-active "$OPENCLAW_SERVICE_NAME" &>/dev/null; then
                        systemctl restart "$OPENCLAW_SERVICE_NAME" 2>/dev/null
                        sleep 2
                        echo -e "${gl_lv}✅ 服务已重启，配置已生效${gl_bai}"
                    fi
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

                    if systemctl is-active "$OPENCLAW_SERVICE_NAME" &>/dev/null; then
                        systemctl restart "$OPENCLAW_SERVICE_NAME" 2>/dev/null
                        sleep 2
                        echo -e "${gl_lv}✅ 服务已重启，配置已生效${gl_bai}"
                    fi
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
                # 查看频道日志
                clear
                echo -e "${gl_kjlan}━━━ 频道日志（最近 50 行）━━━${gl_bai}"
                echo ""
                journalctl -u "$OPENCLAW_SERVICE_NAME" --no-pager -n 50 2>/dev/null || \
                openclaw logs 2>&1 || \
                echo "无法获取频道日志"
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

                        if systemctl is-active "$OPENCLAW_SERVICE_NAME" &>/dev/null; then
                            systemctl restart "$OPENCLAW_SERVICE_NAME" 2>/dev/null
                            sleep 2
                            echo -e "${gl_lv}✅ 服务已重启${gl_bai}"
                        fi
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

# 查看当前配置
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
    local server_ip=$(curl -s4 ip.sb 2>/dev/null || curl -s6 ip.sb 2>/dev/null || echo "服务器IP")
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
    echo -e "控制面板:   ${gl_huang}http://${server_ip}:${port}/${gl_bai}"
    echo ""
    echo -e "${gl_kjlan}━━━ 访问方式 ━━━${gl_bai}"
    echo -e "SSH 隧道:   ${gl_huang}ssh -N -L ${port}:127.0.0.1:${port} root@${server_ip}${gl_bai}"
    echo -e "然后访问:   ${gl_huang}http://localhost:${port}/${gl_bai}"
    echo ""

    echo -e "${gl_kjlan}━━━ 管理命令 ━━━${gl_bai}"
    echo "  状态: systemctl status $OPENCLAW_SERVICE_NAME"
    echo "  日志: journalctl -u $OPENCLAW_SERVICE_NAME -f"
    echo "  重启: systemctl restart $OPENCLAW_SERVICE_NAME"
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

# 编辑配置文件
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

    local editor="nano"
    if command -v vim &>/dev/null; then
        editor="vim"
    fi
    if command -v nano &>/dev/null; then
        editor="nano"
    fi

    $editor "$OPENCLAW_CONFIG_FILE"

    echo ""
    echo -e "${gl_zi}提示: 修改配置后需重启服务生效 (systemctl restart $OPENCLAW_SERVICE_NAME)${gl_bai}"

    read -e -p "是否现在重启服务？(Y/N): " confirm
    case "$confirm" in
        [Yy])
            systemctl restart "$OPENCLAW_SERVICE_NAME" 2>/dev/null
            sleep 2
            if systemctl is-active "$OPENCLAW_SERVICE_NAME" &>/dev/null; then
                echo -e "${gl_lv}✅ 服务已重启${gl_bai}"
            else
                echo -e "${gl_hong}❌ 服务重启失败，请检查配置是否正确${gl_bai}"
            fi
            ;;
    esac

    break_end
}

# 快速替换 API（保留现有设置）
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

    # 更新 .env 中的 API Key
    if [ -f "$OPENCLAW_ENV_FILE" ]; then
        sed -i "s|^OPENCLAW_API_KEY=.*|OPENCLAW_API_KEY=${api_key}|" "$OPENCLAW_ENV_FILE"
        echo "✅ API Key 已更新"
    else
        mkdir -p "$OPENCLAW_HOME_DIR"
        echo "OPENCLAW_API_KEY=${api_key}" > "$OPENCLAW_ENV_FILE"
        chmod 600 "$OPENCLAW_ENV_FILE"
        echo "✅ 环境变量文件已创建"
    fi

    # 重启服务
    if systemctl is-active "$OPENCLAW_SERVICE_NAME" &>/dev/null; then
        systemctl restart "$OPENCLAW_SERVICE_NAME" 2>/dev/null
        sleep 2
        if systemctl is-active "$OPENCLAW_SERVICE_NAME" &>/dev/null; then
            echo -e "${gl_lv}✅ 服务已重启，API 已生效${gl_bai}"
        else
            echo -e "${gl_hong}❌ 服务重启失败，查看日志: journalctl -u ${OPENCLAW_SERVICE_NAME} -n 20${gl_bai}"
        fi
    else
        echo -e "${gl_huang}⚠ 服务未运行，请手动启动: systemctl start ${OPENCLAW_SERVICE_NAME}${gl_bai}"
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

# 安全检查
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

# 卸载 OpenClaw
openclaw_uninstall() {
    clear
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo -e "${gl_hong}  卸载 OpenClaw${gl_bai}"
    echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
    echo ""
    echo -e "${gl_huang}警告: 此操作将删除 OpenClaw 及其所有配置！${gl_bai}"
    echo ""
    echo "将删除以下内容:"
    echo "  - OpenClaw 全局包"
    echo "  - systemd 服务"
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
    systemctl stop "$OPENCLAW_SERVICE_NAME" 2>/dev/null
    systemctl disable "$OPENCLAW_SERVICE_NAME" 2>/dev/null

    echo "正在删除 systemd 服务..."
    rm -f "/etc/systemd/system/${OPENCLAW_SERVICE_NAME}.service"
    systemctl daemon-reload 2>/dev/null

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
            echo -e "${gl_zi}配置目录已保留，下次安装可复用${gl_bai}"
            ;;
    esac

    echo ""
    echo -e "${gl_lv}✅ OpenClaw 卸载完成${gl_bai}"

    break_end
}

# OpenClaw 主菜单
manage_openclaw() {
    while true; do
        clear
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_kjlan}  OpenClaw 部署管理 (AI多渠道消息网关)${gl_bai}"
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""

        # 显示当前状态
        local status=$(openclaw_check_status)
        local port=$(openclaw_get_port)

        case "$status" in
            "not_installed")
                echo -e "当前状态: ${gl_huang}⚠ 未安装${gl_bai}"
                ;;
            "installed_no_service")
                echo -e "当前状态: ${gl_huang}⚠ 已安装但服务未配置${gl_bai}"
                ;;
            "running")
                echo -e "当前状态: ${gl_lv}✅ 运行中${gl_bai} (端口: ${port})"
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
        echo "0. 返回主菜单"
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"

        read -e -p "请选择操作 [0-14]: " choice

        case $choice in
            1)
                openclaw_deploy
                ;;
            2)
                openclaw_update
                ;;
            3)
                openclaw_status
                ;;
            4)
                openclaw_logs
                ;;
            5)
                openclaw_start
                ;;
            6)
                openclaw_stop
                ;;
            7)
                openclaw_restart
                ;;
            8)
                openclaw_config_model
                echo ""
                # 检查服务是否存在再决定重启
                if systemctl list-unit-files "${OPENCLAW_SERVICE_NAME}.service" &>/dev/null && \
                   systemctl cat "$OPENCLAW_SERVICE_NAME" &>/dev/null 2>&1; then
                    read -e -p "是否重启服务使配置生效？(Y/N): " confirm
                    case "$confirm" in
                        [Yy])
                            systemctl restart "$OPENCLAW_SERVICE_NAME" 2>/dev/null
                            sleep 2
                            if systemctl is-active "$OPENCLAW_SERVICE_NAME" &>/dev/null; then
                                echo -e "${gl_lv}✅ 服务已重启${gl_bai}"
                            else
                                echo -e "${gl_hong}❌ 服务重启失败，查看日志: journalctl -u ${OPENCLAW_SERVICE_NAME} -n 20${gl_bai}"
                            fi
                            ;;
                    esac
                else
                    echo -e "${gl_huang}⚠ systemd 服务尚未创建，请先运行「1. 一键部署」完成完整部署${gl_bai}"
                fi
                break_end
                ;;
            9)
                openclaw_quick_api
                ;;
            10)
                openclaw_channels
                ;;
            11)
                openclaw_show_config
                ;;
            12)
                openclaw_edit_config
                ;;
            13)
                openclaw_doctor
                ;;
            14)
                openclaw_uninstall
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


# =====================================================
# OpenClaw Deploy 主菜单
# =====================================================
ai_toolkit_main() {
    while true; do
        clear
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo -e "${gl_kjlan}  OpenClaw Deploy - 一键部署工具箱 v${TOOLKIT_VERSION}${gl_bai}"
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"
        echo ""
        echo "1. OpenClaw 部署管理 (AI多渠道消息网关)"
        echo "2. CRS 部署管理 (Claude多账户中转/拼车)"
        echo "3. Sub2API 部署管理"
        echo ""
        echo "0. 退出"
        echo -e "${gl_kjlan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${gl_bai}"

        read -e -p "请选择操作 [0-3]: " choice

        case $choice in
            1)
                manage_openclaw
                ;;
            2)
                manage_crs
                ;;
            3)
                manage_sub2api
                ;;
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

# =====================================================
# 脚本入口
# =====================================================
check_root
ai_toolkit_main

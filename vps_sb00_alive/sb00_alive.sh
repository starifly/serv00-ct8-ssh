#!/bin/bash
#老王原始vps保活脚本：https://github.com/eooce/Sing-box/blob/main/keep_00.sh
#yutian81修改vps保活脚本：https://github.com/yutian81/serv00-ct8-ssh/blob/main/vps_sb00_alive/sb00_alive.sh
#老王原始serv00四合一无交互脚本：https://github.com/eooce/Sing-box/blob/main/sb_00.sh
#yutian81修改serv00四合一无交互脚本：https://github.com/yutian81/serv00-ct8-ssh/blob/main/vps_sb00_alive/sb00-sk5.sh
#yutian81修改serv00四合一有交互脚本：https://github.com/yutian81/serv00-ct8-ssh/blob/main/sb_serv00_socks.sh
#yutian81无交互脚本执行命令的变量为 SCRIPT_URL；有交互脚本执行命令的变量为 REBOOT_URL
#yutian81-vps保活serv00项目说明：https://github.com/yutian81/serv00-ct8-ssh/blob/main/vps_sb00_alive/README.md
#修改说明：yutian81的版本在老王原始四合一脚本基础上，去掉了 TUIC 协议，增加了 SOCKS5 协议

# 定义颜色
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }

# 定义变量
SCRIPT_PATH="/root/sb00_alive.sh"  # 本脚本路径，不要改变文件名
SCRIPT_URL="https://raw.githubusercontent.com/yutian81/serv00-ct8-ssh/main/vps_sb00_alive/sb00-sk5.sh"  # 四合一无交互yutian版，含socks5，无tuic
#SCRIPT_URL="https://raw.githubusercontent.com/eooce/Sing-box/refs/heads/main/sb_00.sh"  # 四合一无交互老王版，无socks5，含tuic
VPS_JSON_URL="https://raw.githubusercontent.com/yutian81/Wanju-Nodes/main/serv00-panel3/sb00ssh.json"  # 储存vps登录信息及无交互脚本外部变量的json文件
REBOOT_URL="https://raw.githubusercontent.com/yutian81/serv00-ct8-ssh/main/reboot.sh"   # 仅支持重启yutian81修改serv00四合一有交互脚本
NEZHA_URL="https://nezha.yutian81.top"  # 哪吒面板地址，需要 http(s):// 前缀
NEZHA_APITOKEN=""  # 哪吒面板的 API TOKEN
NEZHA_API="$NEZHA_URL/api/v1/server/list"  # 获取哪吒探针列表的api接口，请勿修改

# 外部传入参数
export TERM=xterm
export DEBIAN_FRONTEND=noninteractive
export CFIP=${CFIP:-'www.visa.com.tw'}  # 优选域名或优选ip
export CFPORT=${CFPORT:-'443'}     # 优选域名或优选ip对应端口

# 根据对应系统安装依赖
install_packages() {
    if [ -f /etc/debian_version ]; then
        package_manager="apt-get install -y"
        packages="sshpass curl netcat-openbsd cron jq"
    elif [ -f /etc/redhat-release ]; then
        package_manager="yum install -y"
        packages="sshpass curl netcat-openbsd cron jq"
    elif [ -f /etc/fedora-release ]; then
        package_manager="dnf install -y"
        packages="sshpass curl netcat-openbsd cron jq"
    elif [ -f /etc/alpine-release ]; then
        package_manager="apk add"
        packages="sshpass curl netcat-openbsd cronie jq"
    else
        red "不支持的系统架构！"
        exit 1
    fi
    $package_manager $packages > /dev/null
}
install_packages

# 判断系统架构，添加对应的定时任务
add_cron_job() {
    local new_cron="*/5 * * * * /bin/bash $SCRIPT_PATH >> /root/00_keep.log 2>&1"
    local current_cron
    if crontab -l | grep -q "$SCRIPT_PATH" > /dev/null 2>&1; then
        red "定时任务已存在，跳过添加计划任务"
    else
        if [ -f /etc/debian_version ] || [ -f /etc/redhat-release ] || [ -f /etc/fedora-release ]; then
            (crontab -l; echo "$new_cron") | crontab -
        elif [ -f /etc/alpine-release ]; then
            if [ -f /var/spool/cron/crontabs/root ]; then
                current_cron=$(cat /var/spool/cron/crontabs/root)
            fi
            echo -e "$current_cron\n$new_cron" > /var/spool/cron/crontabs/root
            rc-service crond restart
        fi
        green "已添加定时任务，每5分钟执行一次"
    fi
}
add_cron_job

# 下载存储有服务器登录及无交互脚本外部变量信息的 JSON 文件
download_json() {
    if ! curl -s "$VPS_JSON_URL" -o sb00ssh.json; then
        red "VPS 参数文件下载失败，尝试使用 wget 下载！"
        if ! wget -q "$VPS_JSON_URL" -O sb00ssh.json; then
            red "VPS 参数文件下载失败，请检查下载地址是否正确！"
            exit 1
        else
            green "VPS 参数文件通过 wget 下载成功！"
        fi
    else
        green "VPS 参数文件通过 curl 下载成功！"
    fi
}
download_json

# 检测 TCP 端口
check_tcp_port() {
    local HOST=$1
    local VMESS_PORT=$2
    nc -zv "$HOST" "$VMESS_PORT" &> /dev/null
    return $?
}

# 检查 Argo 隧道状态
check_argo_status() {
    argo_status=$(curl -o /dev/null -s -w "%{http_code}\n" "https://$ARGO_DOMAIN")
    echo "$argo_status"
}

# 检查 nezha 探针在线状态
check_nezha_status() {
    # 获取哪吒agent列表
    agent_list=$(curl -s -H "Authorization: $NEZHA_APITOKEN" "$NEZHA_API")
    if [ $? -ne 0 ]; then
        red "哪吒面板访问失败，请检查面板地址和 API TOKEN 是否正确"
        exit 1
    fi
    echo "$agent_list"
}

# 连接并执行远程命令的函数
run_remote_command() {
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$HOST" \
    "ps aux | grep \"$(whoami)\" | grep -v 'sshd\|bash\|grep' | awk '{print \$2}' | xargs -r kill -9 > /dev/null 2>&1 && \
    VMESS_PORT=$VMESS_PORT HY2_PORT=$HY2_PORT SOCKS_PORT=$SOCKS_PORT \
    SOCKS_USER=$SOCKS_USER SOCKS_PASS=\"$SOCKS_PASS\" \
    ARGO_DOMAIN=$ARGO_DOMAIN ARGO_AUTH=\"$ARGO_AUTH\" \
    NEZHA_SERVER=$NEZHA_SERVER NEZHA_PORT=$NEZHA_PORT NEZHA_KEY=$NEZHA_KEY \
    bash <(curl -Ls ${SCRIPT_URL})"
    #bash <(curl -Ls ${REBOOT_URL})  #使用此脚本无需重装节点，它将直接启动原本存储在服务器中进程和配置文件，实现节点重启，仅适用于yutian81修改serv00四合一有交互脚本
}

# 处理服务器列表并遍历，TCP端口、Argo、哪吒探针三项检测有一项不通即连接 SSH 执行命令
process_servers() {
    local attempt=0
    local max_attempts=5  # 最大尝试检测次数
    local time=$(TZ="Asia/Hong_Kong" date +"%Y-%m-%d %H:%M")
    
    jq -c '.[]' "sb00ssh.json" | while IFS= read -r servers; do
        HOST=$(echo "$servers" | jq -r '.HOST')
        SSH_USER=$(echo "$servers" | jq -r '.SSH_USER')
        SSH_PASS=$(echo "$servers" | jq -r '.SSH_PASS')
        VMESS_PORT=$(echo "$servers" | jq -r '.VMESS_PORT')
        SOCKS_PORT=$(echo "$servers" | jq -r '.SOCKS_PORT')
        HY2_PORT=$(echo "$servers" | jq -r '.HY2_PORT')
        SOCKS_USER=$(echo "$servers" | jq -r '.SOCKS_USER')
        SOCKS_PASS=$(echo "$servers" | jq -r '.SOCKS_PASS')
        ARGO_DOMAIN=$(echo "$servers" | jq -r '.ARGO_DOMAIN')
        ARGO_AUTH=$(echo "$servers" | jq -r '.ARGO_AUTH')
        NEZHA_SERVER=$(echo "$servers" | jq -r '.NEZHA_SERVER')
        NEZHA_PORT=$(echo "$servers" | jq -r '.NEZHA_PORT')
        NEZHA_KEY=$(echo "$servers" | jq -r '.NEZHA_KEY')
        green "正在处理…… 服务器: $(yellow "$HOST")  账户：$(yellow "$SSH_USER")"

        while [ $attempt -lt $max_attempts ]; do
            all_checks=true
            
            # 检查 TCP 端口是否通畅，不通则 30 秒后重试
            check_tcp_port "$HOST" "$VMESS_PORT"
            if [ $? -ne 0 ]; then
                red "TCP 端口 $(yellow "$VMESS_PORT") 不可用！休眠 30 秒后重试"
                all_checks=false
                sleep 30
                attempt=$((attempt + 1))
                continue
            fi
            
            # 检查 Argo 连接是否通畅，不通则 30 秒后重试
            check_argo_status "$ARGO_DOMAIN"
            if [ "$argo_status" == "530" ]; then
                red "Argo $(yellow "$ARGO_DOMAIN") 不可用！状态码：$(yellow "$ARGO_HTTP_CODE")，休眠 30 秒后重试"
                all_checks=false
                sleep 30
                attempt=$((attempt + 1))
                continue
            fi
            
            # 检查哪吒探针是否在线
            check_nezha_status
            current_time=$(date +%s)
            ids_found=("13" "14" "17" "23" "24")  # 此处填写需要检测的 serv00 哪吒探针的 ID
            server_found=false  # 用于标记是否找到符合条件的探针
            echo "$agent_list" | jq -c '.result[]' | while read -r server; do
                server_name=$(echo "$server" | jq -r '.name')
                last_active=$(echo "$server" | jq -r '.last_active')
                valid_ip=$(echo "$server" | jq -r '.valid_ip')
                server_id=$(echo "$server" | jq -r '.id')              
                # 筛选指定服务器的探针
                if [[ " ${ids_found[@]} " =~ " $server_id " ]]; then
                    green "已找到指定的探针 $server_name, ID 为 $server_id, 开始检查探针活动状态"
                    server_found=true
                    # 指定服务器的探针在30秒内无活动，则重新检查探针活动状态
                    if [ $((current_time - last_active)) -gt 30 ]; then
                        red "哪吒探针 $(yellow "$server_name") - $(yellow "$valid_ip") 已离线，立即重试"
                        all_checks=false
                        attempt=$((attempt + 1))
                        continue
                    fi
                fi
            done
            if [ "$server_found" = false ]; then
                red "没有找到指定的探针，请检查 ids_found 变量填写是否正确"
            fi
 
            # 如果所有检查都通过，则打印通畅信息并退出循环
            if [ "$all_checks" == true ]; then
                green "TCP 端口 $(yellow "$VMESS_PORT") 通畅; Argo $(yellow "$ARGO_DOMAIN") 正常; 哪吒探针 $(yellow "$server_name") 正常 \
                服务器 $(yellow "$HOST") 一切正常！ IP：$(yellow "$valid_ip"), 账户：$(yellow "$SSH_USER")"
                break
            fi
        done
        
        # 三项循环检测达到 5 次，远程连接 SSH 执行安装命令
        if [ $attempt -ge $max_attempts ]; then
            red "多次检测失败，尝试 SSH 连接远程执行命令。服务器: $(yellow "$HOST")  账户：$(yellow "$SSH_USER")  [$time]"
            if sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$HOST" -q exit; then
                green "SSH 连接成功。服务器: $(yellow "$HOST")  账户：$(yellow "$SSH_USER")  [$time]"
                run_remote_command "$HOST" "$SSH_USER" "$SSH_PASS" "$VMESS_PORT" "$HY2_PORT" "$SOCKS_PORT" "$SOCKS_USER" "$SOCKS_PASS" "$ARGO_DOMAIN" "$ARGO_AUTH" "$NEZHA_SERVER" "$NEZHA_PORT" "$NEZHA_KEY"
                sleep 3
                if [ $? -eq 0 ] && [ "$argo_status" != "530" ] && [ $((current_time - last_active)) -lt 30 ]; then
                    green "远程命令执行成功，结果如下："
                    green "服务器 $(yellow "$HOST") 恢复正常。端口 $(yellow "$VMESS_PORT") 正常; Argo $(yellow "$ARGO_DOMAIN") 正常; 哪吒 $(yellow "$server_name") 正常"
                else
                    red "远程命令执行失败，请检查变量设置是否正确"
                fi
            else
                red "SSH 连接失败，请检查账户和密码。服务器: $(yellow "$HOST")  账户：$(yellow "$SSH_USER")  [$time]"
            fi
        fi
    done
}
process_servers

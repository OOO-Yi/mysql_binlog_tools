#!/bin/bash

# MySQL Binlog闪回恢复工具 - 合并Bash版本
# 基于Python版本转换而来，所有功能集成在一个文件中

# 默认配置
MYSQL_HOST="127.0.0.1"
MYSQL_PORT="3306"
MYSQL_USER="root"
MYSQL_PASSWORD="Ab123456"
MYSQL_DATABASE="A810sp1"
MYSQL_CLIENT_PATH="/usr/local/mysql/bin/mysql"
BINLOG_DIR="/usr/local/mysql/data/"
MYSQLBINLOG_PATH="/usr/local/mysql/bin/mysqlbinlog"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

log_error() {
    echo -e "${RED}✗ $1${NC}"
}

# 加载配置文件
load_config() {
    local config_file="$1"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
        log_success "配置文件加载成功: $config_file"
    else
        log_warning "配置文件不存在: $config_file，使用默认配置"
    fi
}

# 查找MySQL客户端
find_mysql_client() {
    # 首先检查PATH中的mysql
    if command -v mysql &> /dev/null; then
        MYSQL_CLIENT_PATH="mysql"
        return 0
    fi

    # 检查常见的MySQL安装路径
    local possible_paths=(
        "/usr/local/mysql/bin/mysql"
        "/usr/bin/mysql"
        "/opt/homebrew/bin/mysql"
        "/usr/local/bin/mysql"
        "/opt/local/bin/mysql"
    )

    for path in "${possible_paths[@]}"; do
        if [[ -f "$path" ]]; then
            MYSQL_CLIENT_PATH="$path"
            log_success "找到MySQL客户端: $path"
            return 0
        fi
    done

    log_error "未找到MySQL客户端，请确保MySQL已正确安装"
    return 1
}

# 检查MySQL连接
check_mysql_connection() {
    log_info "正在连接MySQL数据库..."

    # 首先尝试查找MySQL客户端
    if ! find_mysql_client; then
        return 1
    fi

    # 使用找到的MySQL客户端路径进行连接测试
    if "$MYSQL_CLIENT_PATH" -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SELECT 1;" &> /dev/null; then
        log_success "MySQL连接成功"
        return 0
    else
        log_error "MySQL连接失败"
        log_info "请检查以下配置:"
        log_info "- 主机: $MYSQL_HOST"
        log_info "- 端口: $MYSQL_PORT"
        log_info "- 用户名: $MYSQL_USER"
        log_info "- 密码: ******"
        log_info "- MySQL客户端路径: $MYSQL_CLIENT_PATH"
        return 1
    fi
}

# 检查MySQL版本和binlog配置
check_mysql_environment() {
    log_info "检查MySQL环境配置..."

    if ! check_mysql_connection; then
        return 1
    fi

    # 检查MySQL版本
    local version=$("$MYSQL_CLIENT_PATH" -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -sN -e "SELECT VERSION();")
    log_success "MySQL版本: $version"

    # 检查binlog状态
    local log_bin=$("$MYSQL_CLIENT_PATH" -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -sN -e "SHOW VARIABLES LIKE 'log_bin';" | awk '{print $2}')
    log_info "Binlog状态: $log_bin"

    # 检查binlog格式
    local binlog_format=$("$MYSQL_CLIENT_PATH" -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -sN -e "SHOW VARIABLES LIKE 'binlog_format';" | awk '{print $2}')
    log_info "Binlog格式: $binlog_format"

    # 验证配置
    if [[ "$log_bin" != "ON" ]]; then
        log_error "MySQL未开启binlog"
        return 1
    fi

    if [[ "$binlog_format" != "ROW" ]]; then
        log_error "binlog_format不是ROW模式，当前为: $binlog_format"
        return 1
    fi

    log_success "Binlog配置检查通过"
    return 0
}

# 检查路径配置
check_paths() {
    log_info "检查路径配置..."

    # 检查mysqlbinlog路径
    if [[ ! -f "$MYSQLBINLOG_PATH" ]]; then
        log_error "mysqlbinlog路径不存在: $MYSQLBINLOG_PATH"
        log_info "请尝试以下路径:"

        local possible_paths=(
            "/usr/local/mysql/bin/mysqlbinlog"
            "/usr/bin/mysqlbinlog"
            "/opt/homebrew/bin/mysqlbinlog"
            "/usr/local/bin/mysqlbinlog"
            "/usr/bin/mysqlbinlog"
        )

        for path in "${possible_paths[@]}"; do
            if [[ -f "$path" ]]; then
                log_success "找到: $path"
                MYSQLBINLOG_PATH="$path"
                break
            fi
        done

        if [[ ! -f "$MYSQLBINLOG_PATH" ]]; then
            log_error "未找到mysqlbinlog，请确保MySQL已正确安装"
            return 1
        fi
    fi

    # 检查binlog目录
    if [[ ! -d "$BINLOG_DIR" ]]; then
        log_error "binlog目录不存在: $BINLOG_DIR"
        log_info "请检查MySQL数据目录配置"
        return 1
    fi

    log_success "路径检查通过"
    return 0
}

# 获取binlog文件列表
list_binlog_files() {
    log_info "获取可用的binlog文件列表..."

    if ! check_mysql_connection; then
        return 1
    fi

    "$MYSQL_CLIENT_PATH" -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "SHOW BINARY LOGS;" 2>/dev/null

    if [[ $? -ne 0 ]]; then
        log_error "获取binlog文件列表失败"
        return 1
    fi
}

# 清理数值格式
clean_value() {
    local value="$1"
    # 处理类似 "-2759643316332706090 (15687100757376845526)" 的格式
    if [[ "$value" =~ \(.*\) ]]; then
        # 提取括号前的数值
        value="${value%% (*}"
    fi
    echo "$value"
}

# 将binlog内容转换为恢复SQL
convert_to_recovery_sql() {
    local binlog_content="$1"
    local recovery_sql=""
    local IFS=$'\n'
    local lines=($binlog_content)

    local i=0
    while [[ $i -lt ${#lines[@]} ]]; do
        local line="${lines[$i]}"
        line="${line//$'\r'/}"  # 移除Windows换行符

        # 处理UPDATE语句
        if [[ "$line" =~ "UPDATE" ]] && [[ "$line" =~ "###" ]]; then
            if [[ "$line" =~ UPDATE\ \`([^\`]+)\`\.\`([^\`]+)\` ]]; then
                local database="${BASH_REMATCH[1]}"
                local table="${BASH_REMATCH[2]}"
                recovery_sql+=$'\n'"-- UPDATE恢复语句 for $database.$table"$'\n'

                # 查找SET和WHERE部分
                local set_values=()
                local where_conditions=()
                local j=$((i + 1))

                while [[ $j -lt ${#lines[@]} ]] && [[ "${lines[$j]}" =~ "###" ]]; do
                    local set_line="${lines[$j]}"
                    set_line="${set_line//$'\r'/}"

                    if [[ "$set_line" =~ "WHERE" ]]; then
                        # 开始处理WHERE条件
                        local k=$((j + 1))
                        while [[ $k -lt ${#lines[@]} ]] && [[ "${lines[$k]}" =~ "###" ]] && [[ ! "${lines[$k]}" =~ "SET" ]]; do
                            local where_line="${lines[$k]}"
                            where_line="${where_line//$'\r'/}"

                            if [[ "$where_line" =~ \#\#\#\ \ \ @([0-9]+)=([^/]*) ]]; then
                                local col_num="${BASH_REMATCH[1]}"
                                local value="${BASH_REMATCH[2]}"
                                value=$(clean_value "$value")
                                where_conditions["$col_num"]="$value"
                            fi
                            k=$((k + 1))
                        done

                        # 处理SET值
                        local l=$k
                        while [[ $l -lt ${#lines[@]} ]] && [[ "${lines[$l]}" =~ "###" ]]; do
                            local set_line="${lines[$l]}"
                            set_line="${set_line//$'\r'/}"

                            if [[ "$set_line" =~ \#\#\#\ \ \ @([0-9]+)=([^/]*) ]]; then
                                local col_num="${BASH_REMATCH[1]}"
                                local value="${BASH_REMATCH[2]}"
                                value=$(clean_value "$value")
                                set_values["$col_num"]="$value"
                            fi
                            l=$((l + 1))
                        done
                        break
                    fi
                    j=$((j + 1))
                done

                # 构建恢复SQL (反向UPDATE)
                if [[ ${#set_values[@]} -gt 0 ]] && [[ ${#where_conditions[@]} -gt 0 ]]; then
                    local sql="UPDATE \`$database\`.\`$table\` SET "
                    local set_parts=()
                    local where_parts=()

                    for col_num in "${!set_values[@]}"; do
                        if [[ -n "${where_conditions[$col_num]}" ]]; then
                            set_parts+=("\`col$col_num\` = ${where_conditions[$col_num]}")
                        fi
                    done

                    for col_num in "${!where_conditions[@]}"; do
                        where_parts+=("\`col$col_num\` = ${set_values[$col_num]:-NULL}")
                    done

                    if [[ ${#set_parts[@]} -gt 0 ]] && [[ ${#where_parts[@]} -gt 0 ]]; then
                        sql+=$(IFS=,; echo "${set_parts[*]}")
                        sql+=" WHERE "
                        sql+=$(IFS=' AND '; echo "${where_parts[*]}")
                        sql+=";"
                        recovery_sql+="$sql"$'\n'
                    fi
                fi

                i=$((l > i ? l : j))
            fi

        # 处理DELETE语句
        elif [[ "$line" =~ "DELETE" ]] && [[ "$line" =~ "###" ]]; then
            if [[ "$line" =~ DELETE\ FROM\ \`([^\`]+)\`\.\`([^\`]+)\` ]]; then
                local database="${BASH_REMATCH[1]}"
                local table="${BASH_REMATCH[2]}"
                recovery_sql+=$'\n'"-- DELETE恢复语句 for $database.$table"$'\n'

                # 查找VALUES部分构建INSERT语句
                local j=$((i + 1))
                local values=()

                while [[ $j -lt ${#lines[@]} ]] && [[ "${lines[$j]}" =~ "###" ]]; do
                    local value_line="${lines[$j]}"
                    value_line="${value_line//$'\r'/}"

                    if [[ "$value_line" =~ \#\#\#\ \ \ @([0-9]+)=([^/]*) ]]; then
                        local col_num="${BASH_REMATCH[1]}"
                        local value="${BASH_REMATCH[2]}"
                        value=$(clean_value "$value")
                        values+=("$value")
                    fi
                    j=$((j + 1))
                done

                if [[ ${#values[@]} -gt 0 ]]; then
                    local sql="INSERT INTO \`$database\`.\`$table\` VALUES ("
                    sql+=$(IFS=,; echo "${values[*]}")
                    sql+=");"
                    recovery_sql+="$sql"$'\n'
                fi

                i=$j

            fi

        # 处理INSERT语句 (转换为DELETE)
        elif [[ "$line" =~ "INSERT" ]] && [[ "$line" =~ "###" ]]; then
            if [[ "$line" =~ INSERT\ INTO\ \`([^\`]+)\`\.\`([^\`]+)\` ]]; then
                local database="${BASH_REMATCH[1]}"
                local table="${BASH_REMATCH[2]}"
                recovery_sql+=$'\n'"-- INSERT恢复语句 for $database.$table"$'\n'

                # 查找VALUES部分构建DELETE的WHERE条件
                local j=$((i + 1))
                local conditions=()

                while [[ $j -lt ${#lines[@]} ]] && [[ "${lines[$j]}" =~ "###" ]]; do
                    local value_line="${lines[$j]}"
                    value_line="${value_line//$'\r'/}"

                    if [[ "$value_line" =~ \#\#\#\ \ \ @([0-9]+)=([^/]*) ]]; then
                        local col_num="${BASH_REMATCH[1]}"
                        local value="${BASH_REMATCH[2]}"
                        conditions+=("\`col$col_num\` = $(clean_value "$value")")
                    fi
                    j=$((j + 1))
                done

                if [[ ${#conditions[@]} -gt 0 ]]; then
                    local sql="DELETE FROM \`$database\`.\`$table\` WHERE "
                    sql+=$(IFS=' AND '; echo "${conditions[*]}")
                    sql+=";"
                    recovery_sql+="$sql"$'\n'
                fi

                i=$j
            fi
        else
            i=$((i + 1))
        fi
    done

    if [[ -z "$recovery_sql" ]]; then
        recovery_sql="-- 未找到可转换的SQL语句"
    fi

    echo "$recovery_sql"
}

# 查看binlog内容
view_binlog_content() {
    local binlog_file="$1"
    local start_datetime="$2"
    local output_path="$3"

    log_info "开始查看binlog内容..."

    # 检查环境
    if ! check_mysql_environment; then
        return 1
    fi

    if ! check_paths; then
        return 1
    fi

    local binlog_full_path="$BINLOG_DIR/$binlog_file"

    # 检查binlog文件是否存在
    if [[ ! -f "$binlog_full_path" ]]; then
        log_error "binlog文件不存在: $binlog_full_path"
        log_info "请检查文件名是否正确，或使用 --list-binlogs 查看可用文件"
        return 1
    fi

    # 构建命令
    local cmd=("sudo" "$MYSQLBINLOG_PATH" "--base64-output=decode-rows" "-v" "$binlog_full_path" "--start-datetime=$start_datetime")

    log_info "执行命令: ${cmd[*]}"
    log_info "正在执行，请稍候..."

    # 执行命令
    local result
    result=$("${cmd[@]}" 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log_error "执行mysqlbinlog命令失败，退出码: $exit_code"
        log_error "错误输出: $result"

        # 尝试不使用sudo
        log_info "尝试不使用sudo执行..."
        local cmd_without_sudo=("$MYSQLBINLOG_PATH" "--base64-output=decode-rows" "-v" "$binlog_full_path" "--start-datetime=$start_datetime")

        result=$("${cmd_without_sudo[@]}" 2>&1)
        exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            log_success "不使用sudo执行成功"
        else
            log_error "不使用sudo也失败: $result"
            return 1
        fi
    fi

    # 检查输出是否为空
    if [[ -z "$result" ]]; then
        log_warning "mysqlbinlog命令执行成功但输出为空"
        log_info "可能的原因:"
        log_info "1. 指定的时间范围内没有binlog事件"
        log_info "2. binlog文件可能已损坏"
        log_info "3. 时间格式不正确"
        return 1
    fi

    # 获取当前执行时间
    local current_time=$(date "+%Y-%m-%d %H:%M:%S")

    # 创建输出目录
    mkdir -p "$(dirname "$output_path")"

    # 写入文件
    {
        echo "-- MySQL Binlog内容查看"
        echo "-- 执行时间: $current_time"
        echo "-- Binlog文件: $binlog_file"
        echo "-- 开始时间: $start_datetime"
        echo "-- 生成工具: MySQL Binlog闪回恢复工具"
        echo "-- =================================================="
        echo ""
        echo "$result"
    } > "$output_path"

    log_success "Binlog内容已保存到: $output_path"
    log_info "文件大小: $(wc -c < "$output_path") 字节"
    log_info "执行时间: $current_time"
    log_success "输出为原始格式，无需base64解码即可查看"
    return 0
}

# 提取恢复SQL
extract_recovery_sql() {
    local binlog_file="$1"
    local start_datetime="$2"
    local stop_datetime="$3"
    local output_path="$4"

    log_info "开始提取恢复SQL..."

    # 检查环境
    if ! check_mysql_environment; then
        return 1
    fi

    if ! check_paths; then
        return 1
    fi

    local binlog_full_path="$BINLOG_DIR/$binlog_file"

    # 检查binlog文件是否存在
    if [[ ! -f "$binlog_full_path" ]]; then
        log_error "binlog文件不存在: $binlog_full_path"
        log_info "请检查文件名是否正确，或使用 --list-binlogs 查看可用文件"
        return 1
    fi

    # 构建命令
    local cmd=("sudo" "$MYSQLBINLOG_PATH" "--base64-output=decode-rows" "-v" "$binlog_full_path" "--start-datetime=$start_datetime" "--stop-datetime=$stop_datetime")

    log_info "执行命令: ${cmd[*]}"
    log_info "正在执行，请稍候..."

    # 执行命令
    local result
    result=$("${cmd[@]}" 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log_error "执行mysqlbinlog命令失败，退出码: $exit_code"
        log_error "错误输出: $result"

        # 尝试不使用sudo
        log_info "尝试不使用sudo执行..."
        local cmd_without_sudo=("$MYSQLBINLOG_PATH" "--base64-output=decode-rows" "-v" "$binlog_full_path" "--start-datetime=$start_datetime" "--stop-datetime=$stop_datetime")

        result=$("${cmd_without_sudo[@]}" 2>&1)
        exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            log_success "不使用sudo执行成功"
        else
            log_error "不使用sudo也失败: $result"
            return 1
        fi
    fi

    # 检查输出是否为空
    if [[ -z "$result" ]]; then
        log_warning "mysqlbinlog命令执行成功但输出为空"
        log_info "可能的原因:"
        log_info "1. 指定的时间范围内没有binlog事件"
        log_info "2. binlog文件可能已损坏"
        log_info "3. 时间格式不正确"
        return 1
    fi

    # 解析并转换SQL为恢复SQL
    local recovery_sql
    recovery_sql=$(convert_to_recovery_sql "$result")

    # 获取当前执行时间
    local current_time=$(date "+%Y-%m-%d %H:%M:%S")

    # 创建输出目录
    mkdir -p "$(dirname "$output_path")"

    # 写入文件
    {
        echo "-- MySQL Binlog恢复SQL"
        echo "-- 执行时间: $current_time"
        echo "-- Binlog文件: $binlog_file"
        echo "-- 开始时间: $start_datetime"
        echo "-- 结束时间: $stop_datetime"
        echo "-- 生成工具: MySQL Binlog闪回恢复工具"
        echo "-- 注意: 请仔细检查生成的SQL语句，确保正确性后再执行"
        echo "-- =================================================="
        echo ""
        echo "$recovery_sql"
    } > "$output_path"

    log_success "恢复SQL已保存到: $output_path"
    log_info "执行时间: $current_time"
    log_info "生成的恢复SQL行数: $(wc -l < "$output_path")"
    return 0
}

# 显示帮助信息
show_help() {
    cat << EOF
MySQL Binlog闪回恢复工具 - Bash版本

用法: $0 [选项]

选项:
    --check-env               检查MySQL环境配置
    --check-paths             检查路径配置
    --list-binlogs            列出可用的binlog文件
    --view-binlog FILE START_DATETIME OUTPUT_PATH
                              查看binlog内容
    --extract-sql FILE START_DATETIME STOP_DATETIME OUTPUT_PATH
                              提取恢复SQL

常用命令示例:
1. 检查环境: $0 --check-env
2. 检查路径: $0 --check-paths
3. 列出binlog文件: $0 --list-binlogs
4. 查看binlog内容: $0 --view-binlog "binlog.000001" "2024-01-01 10:00:00" "/tmp/binlog_content.txt"
5. 提取恢复SQL: $0 --extract-sql "binlog.000007" "binlog.000001" "2024-01-01 10:00:00" "2024-01-01 11:00:00" "/tmp/recovery.sql"

注意:
- 时间格式应为 "YYYY-MM-DD HH:MM:SS"
- 配置文件可选，如不提供则使用脚本内默认配置
- 配置文件格式应为Bash变量定义格式

EOF
}

# 主函数
main() {
    # 默认加载当前目录下的config.sh（如果存在）
    if [[ -f "./config.sh" ]]; then
        load_config "./config.sh"
    fi

    # 如果没有参数，显示帮助
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                if [[ -n "$2" ]]; then
                    load_config "$2"
                    shift 2
                else
                    log_error "--config 需要指定配置文件路径"
                    exit 1
                fi
                ;;
            --check-env)
                check_mysql_environment
                exit $?
                ;;
            --check-paths)
                check_paths
                exit $?
                ;;
            --list-binlogs)
                list_binlog_files
                exit $?
                ;;
            --view-binlog)
                if [[ $# -ge 4 ]]; then
                    view_binlog_content "$2" "$3" "$4"
                    exit $?
                else
                    log_error "--view-binlog 需要3个参数: 文件名 开始时间 输出路径"
                    exit 1
                fi
                ;;
            --extract-sql)
                if [[ $# -ge 5 ]]; then
                    extract_recovery_sql "$2" "$3" "$4" "$5"
                    exit $?
                else
                    log_error "--extract-sql 需要4个参数: 文件名 开始时间 结束时间 输出路径"
                    exit 1
                fi
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 如果脚本被直接执行，调用主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
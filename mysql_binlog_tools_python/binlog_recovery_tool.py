#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import os
import subprocess
import sys
import argparse
import base64
from datetime import datetime
import pymysql
import re


class MySQLBinlogRecoveryTool:
    def __init__(self, config_file="config.json"):
        """初始化工具，加载配置文件"""
        self.config = self.load_config(config_file)
        self.connection = None

    def load_config(self, config_file):
        """加载配置文件"""
        try:
            with open(config_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except FileNotFoundError:
            print(f"错误: 配置文件 {config_file} 不存在")
            sys.exit(1)
        except json.JSONDecodeError:
            print(f"错误: 配置文件 {config_file} 格式错误")
            sys.exit(1)

    def connect_to_mysql(self):
        """连接到MySQL数据库"""
        try:
            mysql_config = self.config['mysql']
            self.connection = pymysql.connect(
                host=mysql_config['host'],
                port=mysql_config['port'],
                user=mysql_config['user'],
                password=mysql_config['password'],
                database=mysql_config.get('database', ''),
                charset='utf8mb4'
            )
            print("✓ MySQL连接成功")
            return True
        except Exception as e:
            print(f"✗ MySQL连接失败: {e}")
            return False

    def check_mysql_version(self):
        """检查MySQL版本和运行环境"""
        try:
            with self.connection.cursor() as cursor:
                cursor.execute("SELECT VERSION()")
                version = cursor.fetchone()[0]
                print(f"✓ MySQL版本: {version}")

                # 检查系统变量
                cursor.execute("SHOW VARIABLES LIKE 'log_bin'")
                log_bin = cursor.fetchone()
                print(f"✓ Binlog状态: {log_bin[1]}")

                cursor.execute("SHOW VARIABLES LIKE 'binlog_format'")
                binlog_format = cursor.fetchone()
                print(f"✓ Binlog格式: {binlog_format[1]}")

                return version, log_bin[1], binlog_format[1]
        except Exception as e:
            print(f"✗ 检查MySQL环境失败: {e}")
            return None, None, None

    def check_binlog_config(self):
        """检查MySQL是否开启binlog以及binlog_format是否为ROW"""
        version, log_bin, binlog_format = self.check_mysql_version()

        if log_bin != 'ON':
            print("✗ 错误: MySQL未开启binlog")
            return False

        if binlog_format != 'ROW':
            print("✗ 错误: binlog_format不是ROW模式，当前为: " + binlog_format)
            return False

        print("✓ Binlog配置检查通过")
        return True

    def check_paths(self):
        """检查配置的路径是否存在"""
        binlog_config = self.config['binlog']

        # 检查mysqlbinlog路径
        mysqlbinlog_path = binlog_config['mysqlbinlog_path']
        if not os.path.exists(mysqlbinlog_path):
            print(f"✗ 错误: mysqlbinlog路径不存在: {mysqlbinlog_path}")
            print("请尝试以下路径:")
            possible_paths = [
                "/usr/local/mysql/bin/mysqlbinlog",
                "/usr/bin/mysqlbinlog",
                "/opt/homebrew/bin/mysqlbinlog",
                "/usr/local/bin/mysqlbinlog"
            ]
            for path in possible_paths:
                if os.path.exists(path):
                    print(f"  ✓ 找到: {path}")
                    return False
            print("  未找到mysqlbinlog，请确保MySQL已正确安装")
            return False

        # 检查binlog目录
        binlog_dir = binlog_config['binlog_dir']
        if not os.path.exists(binlog_dir):
            print(f"✗ 错误: binlog目录不存在: {binlog_dir}")
            print("请检查MySQL数据目录配置")
            return False

        print("✓ 路径检查通过")
        return True

    def get_binlog_files(self):
        """获取可用的binlog文件列表"""
        try:
            with self.connection.cursor() as cursor:
                cursor.execute("SHOW BINARY LOGS")
                binlogs = cursor.fetchall()
                print("可用的binlog文件:")
                for binlog in binlogs:
                    print(f"  - {binlog[0]} (大小: {binlog[1]} bytes)")
                return [binlog[0] for binlog in binlogs]
        except Exception as e:
            print(f"✗ 获取binlog文件列表失败: {e}")
            return []

    def view_binlog_content(self, binlog_file, start_datetime, output_path):
        """查看binlog文件内容并直接输出（无需base64编码）"""
        try:
            # 首先检查路径
            if not self.check_paths():
                return False

            binlog_config = self.config['binlog']
            binlog_full_path = os.path.join(binlog_config['binlog_dir'], binlog_file)

            # 检查binlog文件是否存在
            if not os.path.exists(binlog_full_path):
                print(f"✗ 错误: binlog文件不存在: {binlog_full_path}")
                print("请检查文件名是否正确，或使用 --list-binlogs 查看可用文件")
                return False

            mysqlbinlog_path = binlog_config['mysqlbinlog_path']

            # 构建命令 - 修正参数格式：时间参数用双引号括起来
            cmd = [
                'sudo', mysqlbinlog_path,
                '--base64-output=decode-rows',
                '-v',
                binlog_full_path,
                f'--start-datetime={start_datetime}'  # 使用双引号括起来
            ]

            print(f"执行命令: {' '.join(cmd)}")
            print("正在执行，请稍候...")

            # 执行命令并捕获输出，包含错误输出
            result = subprocess.run(cmd, capture_output=True, text=True, check=False)

            if result.returncode != 0:
                print(f"✗ 执行mysqlbinlog命令失败，退出码: {result.returncode}")
                print(f"错误输出: {result.stderr}")

                # 尝试不使用sudo
                print("尝试不使用sudo执行...")
                cmd_without_sudo = cmd[1:]  # 移除sudo
                result_without_sudo = subprocess.run(cmd_without_sudo, capture_output=True, text=True, check=False)

                if result_without_sudo.returncode == 0:
                    print("✓ 不使用sudo执行成功")
                    result = result_without_sudo
                else:
                    print(f"不使用sudo也失败: {result_without_sudo.stderr}")
                    return False

            # 检查输出是否为空
            if not result.stdout.strip():
                print("⚠️ 警告: mysqlbinlog命令执行成功但输出为空")
                print("可能的原因:")
                print("1. 指定的时间范围内没有binlog事件")
                print("2. binlog文件可能已损坏")
                print("3. 时间格式不正确")
                return False

            # 获取当前执行时间
            current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

            # 直接写入文件，无需base64编码，添加执行时间信息
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            with open(output_path, 'w', encoding='utf-8') as f:
                # 写入执行时间信息
                f.write(f"-- MySQL Binlog内容查看\n")
                f.write(f"-- 执行时间: {current_time}\n")
                f.write(f"-- Binlog文件: {binlog_file}\n")
                f.write(f"-- 开始时间: {start_datetime}\n")
                f.write(f"-- 生成工具: MySQL Binlog闪回恢复工具\n")
                f.write("-- " + "=" * 50 + "\n\n")
                f.write(result.stdout)

            print(f"✓ Binlog内容已保存到: {output_path}")
            print(f"文件大小: {len(result.stdout)} 字节")
            print(f"执行时间: {current_time}")
            print("✓ 输出为原始格式，无需base64解码即可查看")
            return True

        except Exception as e:
            print(f"✗ 处理binlog内容失败: {e}")
            return False

    def extract_recovery_sql(self, binlog_file, start_datetime, stop_datetime, output_path):
        """提取恢复SQL"""
        try:
            # 首先检查路径
            if not self.check_paths():
                return False

            binlog_config = self.config['binlog']
            binlog_full_path = os.path.join(binlog_config['binlog_dir'], binlog_file)

            # 检查binlog文件是否存在
            if not os.path.exists(binlog_full_path):
                print(f"✗ 错误: binlog文件不存在: {binlog_full_path}")
                print("请检查文件名是否正确，或使用 --list-binlogs 查看可用文件")
                return False

            mysqlbinlog_path = binlog_config['mysqlbinlog_path']

            # 构建命令 - 修复参数格式问题
            cmd = [
                'sudo', mysqlbinlog_path,
                '--base64-output=decode-rows',
                '-v',
                binlog_full_path,
                f'--start-datetime={start_datetime}',  # 使用双引号括起来
                f'--stop-datetime={stop_datetime}'  # 使用双引号括起来
            ]

            print(f"执行命令: {' '.join(cmd)}")
            print("正在执行，请稍候...")

            # 执行命令并捕获输出，包含错误输出
            result = subprocess.run(cmd, capture_output=True, text=True, check=False)

            if result.returncode != 0:
                print(f"✗ 执行mysqlbinlog命令失败，退出码: {result.returncode}")
                print(f"错误输出: {result.stderr}")

                # 尝试不使用sudo
                print("尝试不使用sudo执行...")
                cmd_without_sudo = cmd[1:]  # 移除sudo
                result_without_sudo = subprocess.run(cmd_without_sudo, capture_output=True, text=True, check=False)

                if result_without_sudo.returncode == 0:
                    print("✓ 不使用sudo执行成功")
                    result = result_without_sudo
                else:
                    print(f"不使用sudo也失败: {result_without_sudo.stderr}")
                    return False

            # 检查输出是否为空
            if not result.stdout.strip():
                print("⚠️ 警告: mysqlbinlog命令执行成功但输出为空")
                print("可能的原因:")
                print("1. 指定的时间范围内没有binlog事件")
                print("2. binlog文件可能已损坏")
                print("3. 时间格式不正确")
                return False

            # 解析并转换SQL为恢复SQL
            recovery_sql = self.convert_to_recovery_sql(result.stdout)

            # 获取当前执行时间
            current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

            # 写入文件，添加执行时间信息
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            with open(output_path, 'w', encoding='utf-8') as f:
                # 写入执行时间信息
                f.write(f"-- MySQL Binlog恢复SQL\n")
                f.write(f"-- 执行时间: {current_time}\n")
                f.write(f"-- Binlog文件: {binlog_file}\n")
                f.write(f"-- 开始时间: {start_datetime}\n")
                f.write(f"-- 结束时间: {stop_datetime}\n")
                f.write(f"-- 生成工具: MySQL Binlog闪回恢复工具\n")
                f.write("-- 注意: 请仔细检查生成的SQL语句，确保正确性后再执行\n")
                f.write("-- " + "=" * 50 + "\n\n")
                f.write(recovery_sql)

            print(f"✓ 恢复SQL已保存到: {output_path}")
            print(f"执行时间: {current_time}")
            print(f"生成的恢复SQL行数: {len(recovery_sql.splitlines())}")
            return True

        except Exception as e:
            print(f"✗ 提取恢复SQL失败: {e}")
            return False

    def convert_to_recovery_sql(self, binlog_content):
        """将binlog内容转换为恢复SQL"""
        recovery_sql = []
        lines = binlog_content.split('\n')

        def clean_value(value):
            """清理数值格式，移除括号中的额外数值"""
            # 处理类似 "-2759643316332706090 (15687100757376845526)" 的格式
            if '(' in value and ')' in value:
                # 提取括号前的数值
                main_value = value.split('(')[0].strip()
                return main_value
            return value

        i = 0
        while i < len(lines):
            line = lines[i].strip()

            # 处理UPDATE语句
            if 'UPDATE' in line and '###' in line:
                table_match = re.search(r'UPDATE `([^`]+)`\.`([^`]+)`', line)
                if table_match:
                    database, table = table_match.groups()
                    recovery_sql.append(f"\n-- UPDATE恢复语句 for {database}.{table}")

                    # 查找SET和WHERE部分
                    set_values = {}
                    where_conditions = {}

                    j = i + 1
                    while j < len(lines) and '###' in lines[j]:
                        set_line = lines[j].strip()
                        if 'WHERE' in set_line:
                            # 开始处理WHERE条件
                            k = j + 1
                            while k < len(lines) and '###' in lines[k] and 'SET' not in lines[k]:
                                where_line = lines[k].strip()
                                where_match = re.search(r'###   @(\d+)=([^/]*)', where_line)
                                if where_match:
                                    col_num, value = where_match.groups()
                                    where_conditions[col_num] = clean_value(value.strip())
                                k += 1

                            # 处理SET值
                            l = k
                            while l < len(lines) and '###' in lines[l]:
                                set_line = lines[l].strip()
                                set_match = re.search(r'###   @(\d+)=([^/]*)', set_line)
                                if set_match:
                                    col_num, value = set_match.groups()
                                    set_values[col_num] = clean_value(value.strip())
                                l += 1
                            break
                        j += 1

                    # 构建恢复SQL (反向UPDATE)
                    if set_values and where_conditions:
                        sql = f"UPDATE `{database}`.`{table}` SET "
                        set_parts = []
                        for col_num, value in set_values.items():
                            if col_num in where_conditions:
                                set_parts.append(f"`col{col_num}` = {where_conditions[col_num]}")

                        where_parts = []
                        for col_num, value in where_conditions.items():
                            where_parts.append(f"`col{col_num}` = {set_values.get(col_num, 'NULL')}")

                        if set_parts and where_parts:
                            sql += ', '.join(set_parts) + " WHERE " + ' AND '.join(where_parts) + ";"
                            recovery_sql.append(sql)

                    i = l if l > i else j

            # 处理DELETE语句
            elif 'DELETE' in line and '###' in line:
                table_match = re.search(r'DELETE FROM `([^`]+)`\.`([^`]+)`', line)
                if table_match:
                    database, table = table_match.groups()
                    recovery_sql.append(f"\n-- DELETE恢复语句 for {database}.{table}")

                    # 查找VALUES部分构建INSERT语句
                    j = i + 1
                    values = []
                    while j < len(lines) and '###' in lines[j]:
                        value_line = lines[j].strip()
                        value_match = re.search(r'###   @(\d+)=([^/]*)', value_line)
                        if value_match:
                            col_num, value = value_match.groups()
                            # 清理数值格式
                            cleaned_value = clean_value(value.strip())
                            values.append(cleaned_value)
                        j += 1

                    if values:
                        # 直接使用实际值构建INSERT语句，而不是占位符
                        sql = f"INSERT INTO `{database}`.`{table}` VALUES ({', '.join(values)});"
                        recovery_sql.append(sql)

                    i = j

            # 处理INSERT语句 (转换为DELETE)
            elif 'INSERT' in line and '###' in line:
                table_match = re.search(r'INSERT INTO `([^`]+)`\.`([^`]+)`', line)
                if table_match:
                    database, table = table_match.groups()
                    recovery_sql.append(f"\n-- INSERT恢复语句 for {database}.{table}")

                    # 查找VALUES部分构建DELETE的WHERE条件
                    j = i + 1
                    conditions = []
                    while j < len(lines) and '###' in lines[j]:
                        value_line = lines[j].strip()
                        value_match = re.search(r'###   @(\d+)=([^/]*)', value_line)
                        if value_match:
                            col_num, value = value_match.groups()
                            conditions.append(f"`col{col_num}` = {clean_value(value.strip())}")
                        j += 1

                    if conditions:
                        sql = f"DELETE FROM `{database}`.`{table}` WHERE {' AND '.join(conditions)};"
                        recovery_sql.append(sql)

                    i = j
            else:
                i += 1

        return '\n'.join(recovery_sql) if recovery_sql else "-- 未找到可转换的SQL语句"

    def close_connection(self):
        """关闭数据库连接"""
        if self.connection:
            self.connection.close()
            print("✓ MySQL连接已关闭")


def main():
    parser = argparse.ArgumentParser(description='MySQL Binlog闪回恢复工具')
    parser.add_argument('--config', default='config.json', help='配置文件路径')
    parser.add_argument('--check-env', action='store_true', help='检查MySQL环境')
    parser.add_argument('--check-paths', action='store_true', help='检查路径配置')
    parser.add_argument('--list-binlogs', action='store_true', help='列出可用的binlog文件')
    parser.add_argument('--view-binlog', nargs=3, metavar=('FILE', 'START_DATETIME', 'OUTPUT_PATH'),
                        help='查看binlog内容，参数: 文件名 开始时间 输出路径')
    parser.add_argument('--extract-sql', nargs=4, metavar=('FILE', 'START_DATETIME', 'STOP_DATETIME', 'OUTPUT_PATH'),
                        help='提取恢复SQL，参数: 文件名 开始时间 结束时间 输出路径')

    args = parser.parse_args()

    tool = MySQLBinlogRecoveryTool(args.config)

    try:
        # 连接到MySQL
        if not tool.connect_to_mysql():
            return

        if args.check_env:
            # 检查环境
            tool.check_binlog_config()

        elif args.check_paths:
            # 检查路径
            tool.check_paths()

        elif args.list_binlogs:
            # 列出binlog文件
            tool.get_binlog_files()

        elif args.view_binlog:
            # 查看binlog内容
            binlog_file, start_datetime, output_path = args.view_binlog
            if tool.check_binlog_config():
                tool.view_binlog_content(binlog_file, start_datetime, output_path)

        elif args.extract_sql:
            # 提取恢复SQL
            binlog_file, start_datetime, stop_datetime, output_path = args.extract_sql
            if tool.check_binlog_config():
                tool.extract_recovery_sql(binlog_file, start_datetime, stop_datetime, output_path)

        else:
            print("请使用 --help 查看可用命令")
            print("\n常用命令示例:")
            print("1. 检查环境: python binlog_recovery_tool.py --check-env")
            print("2. 检查路径: python binlog_recovery_tool.py --check-paths")
            print("3. 列出binlog文件: python binlog_recovery_tool.py --list-binlogs")
            print(
                "4. 查看binlog内容: python binlog_recovery_tool.py --view-binlog \"binlog.000007\" \"2026-01-06 16:54:00\" \"/path/to/output.txt\"")
            print(
                "5. 提取恢复SQL: python binlog_recovery_tool.py --extract-sql \"binlog.000007\" \"2026-01-06 16:54:00\" \"2026-01-06 16:55:00\" \"/path/to/recovery.sql\"")

    finally:
        tool.close_connection()


if __name__ == "__main__":
    main()
# MySQL Binlog闪回恢复工具 - Bash版本

## 一、概述

基于Bash脚本的MySQL二进制日志（Binlog）闪回恢复工具，可以将误操作的SQL语句（INSERT、UPDATE、DELETE）转换为对应的恢复SQL语句，快速恢复数据。

## 功能特性

- ✅ **自动MySQL客户端检测** - 自动查找MySQL客户端路径
- ✅ **环境检查** - 检查MySQL版本、binlog状态和格式
- ✅ **路径检查** - 验证binlog目录和工具路径
- ✅ **binlog文件列表** - 列出可用的binlog文件
- ✅ **binlog内容查看** - 查看指定时间段的binlog内容
- ✅ **恢复SQL生成** - 自动生成反向操作的恢复SQL
- ✅ **彩色日志输出** - 直观的状态提示

## 二、前置要求

- MySQL 8.0+
- mysqlbinlog工具（通常随MySQL安装）
- Bash shell环境（macOS/Linux）

## 三、快速开始

### 1. 设置执行权限

```bash
chmod +x binlog_recovery_tool.sh
```
### 2.编辑代码中数据库信息

### 3. 检查环境配置

```bash
./binlog_recovery_tool.sh --check-env
```
```
预期输出：
ℹ 检查MySQL环境配置...
ℹ 正在连接MySQL数据库...
✓ 找到MySQL客户端: /usr/local/mysql/bin/mysql
✓ MySQL连接成功
✓ MySQL版本: 8.0.43
ℹ Binlog状态: ON
ℹ Binlog格式: ROW
✓ Binlog配置检查通过
```


### 4. 检查路径配置

```bash
./binlog_recovery_tool.sh --check-paths
```
```
预期输出：
ℹ 检查路径配置... 
✓ 路径检查通过
```
### 5. 列出可用的binlog文件

```bash
./binlog_recovery_tool.sh --list-binlogs
```

## 四、详细使用说明

### 1. 基本命令格式

```bash
./binlog_recovery_tool.sh [选项] [参数]
```

### 可用选项

| 选项 | 参数 | 说明 |
|------|------|------|
| `--check-env` | 无 | 检查MySQL环境配置 |
| `--check-paths` | 无 | 检查路径配置 |
| `--list-binlogs` | 无 | 列出可用的binlog文件 |
| `--view-binlog` | 文件名 开始时间 输出路径 | 查看binlog内容 |
| `--extract-sql` | 文件名 开始时间 结束时间 输出路径 | 提取恢复SQL |
| `--help` 或 `-h` | 无 | 显示帮助信息 |

### 2. 查看binlog内容

```bash
./binlog_recovery_tool.sh --view-binlog "binlog.000001" "2026-01-01 16:54:00" "/tmp/binlog_content.txt"
```

**参数说明：**
- `binlog.000001` - binlog文件名
- `2024-01-01 10:00:00` - 开始时间（格式：YYYY-MM-DD HH:MM:SS）
- `/tmp/binlog_content.txt` - 输出文件路径

### 3. 提取恢复SQL

```bash
./binlog_recovery_tool.sh --extract-sql "binlog.000001" "2026-01-01 16:54:00" "2026-01-01 16:55:00" "/tmp/recovery.sql"
```

**参数说明：**
- `binlog.000001` - binlog文件名
- `2024-01-01 10:00:00` - 开始时间
- `2024-01-01 11:00:00` - 结束时间
- `/tmp/recovery.sql` - 恢复SQL输出路径


## 五、恢复SQL转换规则

工具会自动将binlog中的SQL操作转换为反向操作：

| 原始操作 | 恢复操作 | 说明 |
|----------|----------|------|
| INSERT | DELETE | 删除插入的数据 |
| UPDATE | UPDATE | 将数据恢复到修改前的状态 |
| DELETE | INSERT | 重新插入被删除的数据 |

## 六、实际使用示例

### 场景：误删数据恢复

1. **确定误操作时间**
   ```bash
   假设误操作发生在 2026-01-01 16:54:00 到 16:55:00 之间
   ```

2. **查看该时间段的binlog内容**
   ```bash
   ./binlog_recovery_tool.sh --view-binlog "binlog.000001" "2026-01-01 16:54:00" "/tmp/view_result.txt"
   ```

3. **提取恢复SQL**
   ```bash
   ./binlog_recovery_tool.sh --extract-sql "binlog.000001" "2026-01-01 16:54:00" "2026-01-01 16:55:00" "/tmp/recovery.sql"
   ```

4. **检查并执行恢复SQL**
   ```bash
   # 查看生成的恢复SQL
   cat /tmp/recovery.sql
   
   # 确认无误后执行
   mysql -u root -p < /tmp/recovery.sql
   ```

## 六、故障排除

### 1. 常见问题

1. **"mysql客户端未安装或不在PATH中"**
   - 解决方案：脚本会自动检测MySQL客户端路径，如果检测失败请检查MySQL是否正确安装

2. **"MySQL连接失败"**
   - 检查MySQL服务是否运行
   - 验证用户名、密码、主机和端口配置
   - 检查网络连接

3. **"binlog文件不存在"**
   - 确认binlog文件名正确
   - 检查BINLOG_DIR配置路径
   - 尝试添加sudo权限，如：`sudo ./binlog_recovery_tool.sh --list-binlogs`

4. **"mysqlbinlog路径不存在"**
   - 脚本会自动查找常见路径，如失败请手动设置MYSQLBINLOG_PATH


## 七、注意事项

1. **安全警告**：MySQL会在命令行中提示密码安全警告，这是正常现象
2. **权限要求**：可能需要sudo权限访问binlog文件
3. **时间格式**：必须使用 "YYYY-MM-DD HH:MM:SS" 格式
4. **数据验证**：执行恢复SQL前务必仔细检查生成的语句
5. **备份建议**：在执行恢复操作前建议备份当前数据



## 八、工具测试环境
1. **操作系统**：macOS15
2. **数据库版本**：MySQL 8.0.43
3. **Binlog状态**：ON
4. **Binlog格式**：ROW
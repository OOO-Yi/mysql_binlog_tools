# MySQL Binlog闪回恢复工具 - Python版本

## 一、概述

基于Python代码的MySQL二进制日志（Binlog）闪回恢复工具，可以将误操作的SQL语句（INSERT、UPDATE、DELETE）转换为对应的恢复SQL语句，快速恢复数据。

## 功能特性

- ✅ **自动MySQL客户段检测** - 通过配置文件配置MySQL连接参数
- ✅ **环境监察** - 检查MySQL版本和运行环境
- ✅ **binlog配置检查** - 检查MySQL是否开启binlog以及binlog_format是否为ROW
- ✅ **binlog内容查看** - 查看指定时间段的binlog内容
- ✅ **恢复SQL生成** - 自动生成反向操作的恢复SQL

## 二、前置要求

- MySQL 8.0+
- mysqlbinlog工具（通常随MySQL安装）
- Bash shell环境（macOS/Linux）

## 三、快速开始

### 1.依赖安装
```bash
pip install -r requirements.txt
```
### 2.编辑配置文件

编辑 `config.json` 文件：

```json
{
  "mysql": {
    "host": "127.0.0.1",
    "port": 3306,
    "user": "root",
    "password": "Ab123456",
    "database": "db_server"
  },
  "binlog": {
    "binlog_dir": "/usr/local/mysql/data/",
    "mysqlbinlog_path": "/usr/local/mysql/bin/mysqlbinlog"
  }
}
```
### 3. 检查环境配置
```bash
python binlog_recovery_tool.py --config config.json --check-env
```
```
预期输出：
✓ MySQL连接成功
✓ MySQL版本: 8.0.43
✓ Binlog状态: ON
✓ Binlog格式: ROW
✓ Binlog配置检查通过
✓ MySQL连接已关闭
```
### 4. 配置路径检查
```bash
python binlog_recovery_tool.py --config config.json --check-env
```
```
预期输出：
✓ MySQL连接成功
✓ 路径检查通过
✓ MySQL连接已关闭
```
### 5. 列出可用的binlog文件
```bash
sudo python binlog_recovery_tool.py --config config.json --list-binlogs
```


## 四、详细使用说明
```bash
python binlog_recovery_tool.py --config config.json [选项] [参数]
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
sudo python binlog_recovery_tool.py --config config.json --view-binlog "binlog.000001" "2026-01-01 16:54:00" "/tmp/binlog_content.txt"
```

**参数说明：**
- `binlog.000001` - binlog文件名
- `2026-01-01 16:54:00` - 开始时间（格式：YYYY-MM-DD HH:MM:SS）
- `/tmp/binlog_content.txt` - 输出文件路径

### 3. 提取恢复SQL

```bash
sudo python binlog_recovery_tool.py --config config.json --extract-sql "binlog.000001" "2026-01-01 16:54:00" "2026-01-01 16:55:00" "/tmp/recovery.sql"
```

**参数说明：**
- `binlog.000001` - binlog文件名
- `2026-01-01 16:54:00` - 开始时间
- `2026-01-01 16:55:00` - 结束时间
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
   ```txt
   假设误操作发生在 2026-01-01 16:54:00 到 16:55:00 之间
   ```

2. **查看该时间段的binlog内容**
   ```bash
   ./binlog_recovery_tool.sh --view-binlog "binlog.000007" "2026-01-01 16:54:00" "/tmp/view_result.txt"
   ```

3. **提取恢复SQL**
   ```bash
   ./binlog_recovery_tool.sh --extract-sql "binlog.000007" "2026-01-01 16:54:00" "2026-01-01 16:55:00" "/tmp/recovery.sql"
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

1. **"MySQL连接失败"**
   - 检查MySQL服务是否运行
   - 验证用户名、密码、主机和端口配置
   - 检查网络连接

2. **"binlog文件不存在"**
   - 检查binlog_dir配置路径
   - 尝试添加sudo权限，如：`sudo ./binlog_recovery_tool.sh --list-binlogs`

3. **"mysqlbinlog路径不存在"**
   - 脚本会自动查找常见路径，如失败请手动设置mysqlbinlog_path


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
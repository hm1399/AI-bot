---
name: computer-control
description: 电脑控制技能 — 通过 exec 工具执行系统命令来操控用户电脑
always: true
---

# 电脑控制

你可以通过 `exec` 工具执行 shell 命令来控制用户的电脑。

## 常用操作

### 打开应用
- macOS: `open -a "应用名"` (如 `open -a "WeChat"`, `open -a "Safari"`)
- Windows: `start 应用名`
- 打开网页: `open "https://..."` (macOS) 或 `start "https://..."` (Windows)

### 文件操作
- 查看文件: `cat 文件路径`
- 列出目录: `ls -la 路径`
- 搜索文件: `find ~ -name "文件名" -maxdepth 3`

### 系统信息
- 当前时间: `date`
- 系统信息: `uname -a`
- 磁盘空间: `df -h`
- 内存使用: macOS 用 `vm_stat`, Linux 用 `free -h`

### 进程管理
- 查看进程: `ps aux | grep 进程名`
- 结束进程: `pkill 进程名` (需用户确认)

## 安全规则

1. **危险命令需确认**: `rm`, `rmdir`, `kill`, `shutdown`, `reboot`, 格式化等操作前必须向用户确认
2. **禁止执行**: `rm -rf /`, `rm -rf ~`, `shutdown`, `reboot`, `mkfs`, `dd if=/dev/zero`
3. **隐私保护**: 不主动读取用户敏感文件 (密钥、密码、浏览器历史等)
4. **路径安全**: 操作用户目录下的文件，不要随意操作系统目录

## 回复风格

- 执行成功: 简洁告知结果 (如 "微信已打开")
- 执行失败: 说明原因和建议 (如 "没找到该应用，你是指…？")
- 语音场景回复不超过 50 字

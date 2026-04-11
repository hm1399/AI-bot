---
name: computer-control
description: 电脑控制技能 — 优先通过 structured `computer_control` 工具调用产品级电脑动作
always: true
---

# 电脑控制

你应优先使用结构化 `computer_control` 工具处理产品级电脑动作，不要默认回退到 raw `exec`。

## 默认路由

- 产品动作优先走 `computer_control`
  - 例如：`open_app`、`focus_app_or_window`、`open_path`、`open_url`
  - 例如：`run_shortcut`、`run_script`、`clipboard_get`、`clipboard_set`
  - 例如：`active_window`、`screenshot`、`system_info`
- `exec` 只用于调试 / backoffice / 仓库维护类命令
  - 例如查看日志、检查目录、运行开发命令
  - 不要用 raw `exec` 重新实现已经存在结构化动作的产品能力
- 如果当前 runtime 还没有注册 `computer_control`
  - 对产品动作应明确说明能力暂不可用或等待系统接线完成
  - 不要因为工具暂时缺失就退回 raw `exec` 伪装成产品能力

## 调用方式

- 结构化动作示例：

```json
{
  "action": "open_app",
  "target": {"app": "Safari"},
  "reason": "Open the browser for the user"
}
```

- 如果动作属于外发、发送、代用户确认之外会产生真实副作用的高风险行为：
  - 必须先走确认流
  - 应返回等待确认，而不是直接执行
  - 例如：发消息、联系人相关外发、未来的 UI scripting 发送动作

## 常用操作

- 打开应用: `computer_control(action="open_app", target={"app": "WeChat"})`
- 打开网页: `computer_control(action="open_url", target={"url": "https://..."})`
- 打开路径: `computer_control(action="open_path", target={"path": "/Users/..."})`
- 获取系统信息: `computer_control(action="system_info", target={"profile": "frontmost_app"})`
- 获取当前窗口: `computer_control(action="active_window")`
- 复制文本: `computer_control(action="clipboard_set", target={"text": "..."})`

只有在结构化动作不适用、且任务本质是调试或运维时，才考虑使用 `exec`。

## 安全规则

1. **结构化优先**: 已有 `computer_control` 动作时，不要改用 raw `exec`
2. **高风险外发必须确认**: 发消息、联系人操作、未来发送类 UI 自动化都必须先确认
3. **危险命令需确认**: 只有在 debug/backoffice fallback 下，`rm`、`rmdir`、`kill`、`shutdown`、`reboot` 等仍必须确认
4. **禁止执行**: `rm -rf /`, `rm -rf ~`, `shutdown`, `reboot`, `mkfs`, `dd if=/dev/zero`
5. **隐私保护**: 不主动读取用户敏感文件 (密钥、密码、浏览器历史等)
6. **路径安全**: 操作用户目录下的文件，不要随意操作系统目录

## 回复风格

- 执行成功: 简洁告知结果 (如 "微信已打开")
- 等待确认: 明确说明还未执行，正在等用户确认
- 执行失败: 说明原因和建议 (如 "没找到该应用，你是指…？")
- 语音场景回复不超过 50 字

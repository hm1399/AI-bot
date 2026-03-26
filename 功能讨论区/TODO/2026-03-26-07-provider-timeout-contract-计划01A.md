# 计划 01A - provider timeout contract + LiteLLMProvider/config

## 任务边界

- 仅处理 provider/config contract
- 不修改 `server/services/app_runtime.py`
- 不修改 `server/nanobot/bus/queue.py`
- 不修改 `server/nanobot/session/manager.py`
- 不修改 `server/nanobot/agent/loop.py`

## 目标

1. 为 provider 响应定义最小结构化错误契约，区分 timeout 与普通 provider error
2. 在 `LiteLLMProvider` 中实现单次模型请求总超时和错误分类
3. 将超时配置接入 `server/config.py`、`server/config.yaml`、`server/bootstrap.py`
4. 补齐 provider/config 直接相关测试
5. 运行相关测试并单独提交 git commit

## TDD 步骤

1. 先新增/扩展 provider 测试，覆盖 timeout 分类与普通异常分类
2. 运行 provider 测试，确认先失败
3. 新增/扩展 config 测试，覆盖默认值与校验
4. 运行 config 测试，确认先失败
5. 最小实现 `LLMResponse` 错误契约、LiteLLM 超时处理、配置默认值和校验
6. 运行与改动直接相关的测试直到通过
7. 检查 diff，仅提交本任务改动

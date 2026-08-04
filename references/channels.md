# 通道配置表

> 修改通道、模型 ID、base URL、免费额度只改本文件,不改 SKILL.md 与脚本。SKILL.md 只引用本表的"类别 → 通道"结论。

## 云端通道(视觉)

| 通道 | 类别 | Base URL（chat/completions） | 默认模型 | 环境变量 | 费用 |
|---|---|---|---|---|---|
| custom | 默认视觉（用户自定义） | VISION_CUSTOM_BASE_URL（OpenAI 兼容，可填 DashScope/中转/任意服务商） | VISION_CUSTOM_MODEL（如 qwen3.7-plus、gpt-4o 等） | VISION_CUSTOM_API_KEY | 视服务商 |
| glm | 降级/简单任务（免费兜底） | https://open.bigmodel.cn/api/paas/v4/chat/completions | glm-4v-flash | GLM_API_KEY | 永久免费（官方） |
| glm-thinking | 降级/复杂推理（免费兜底） | https://open.bigmodel.cn/api/paas/v4/chat/completions | glm-4.1v-thinking-flash | GLM_API_KEY | 免费（官方） |

> 设计说明：视觉默认通道统一走 `custom`（用户自定义 OpenAI 兼容接口），用户在其中配置自己的视觉模型即可——例如想用 Qwen3.7-Plus 就填 DashScope 地址 + `qwen3.7-plus` + key，想用其他模型就填对应服务商。不再提供专门的 qwen 通道配置，避免冗余；GLM 免费模型保留作兜底。

## 生图通道

| 通道 | 端点 | 请求体 | 环境变量 | 说明 |
|---|---|---|---|---|
| image-gen | `{VISION_GEN_BASE_URL}/v1/images/generations`（OpenAI 标准） | model / prompt / n / size / response_format（先 b64_json，被拒自动回退 url） | VISION_GEN_BASE_URL + VISION_GEN_API_KEY + VISION_GEN_MODEL | 无免费兜底；生成图默认保存到用户 Downloads 目录（`-OutDir` 可改），`result` 返回本地文件路径 |

## OCR 通道

| 通道 | 端点 | 参数 | 环境变量 | 免费情况 |
|---|---|---|---|---|
| baidu-ocr | https://aip.baidubce.com/rest/2.0/ocr/v1/general_basic（-Accurate 用 accurate_basic） | language_type=CHN_ENG | BAIDU_API_KEY + BAIDU_SECRET_KEY | 免费额度（以百度云控制台为准） |
| windows-ocr | 本地 WinRT OcrEngine | 离线 | 无 | 系统自带 |
| mineru | `mineru-open-api flash-extract` | 表格/版式 | MINERU_TOKEN（仅 extract） | flash 免 token |

## 注册与启用

| 通道 | 注册入口 | 环境变量 |
|---|---|---|
| custom（默认视觉） | 你的 OpenAI 兼容视觉服务商（如想用千问可注册 https://platform.qianwenai.com/home/api-keys） | VISION_CUSTOM_BASE_URL + VISION_CUSTOM_API_KEY + VISION_CUSTOM_MODEL |
| image-gen | 你的生图服务商（支持 images/generations） | VISION_GEN_BASE_URL + VISION_GEN_API_KEY + VISION_GEN_MODEL |
| glm | https://open.bigmodel.cn/ | GLM_API_KEY |
| glm-thinking | https://open.bigmodel.cn/（与 glm 同 key） | GLM_API_KEY |
| baidu-ocr | https://console.bce.baidu.com/ai/#/ai/ocr/app/list | BAIDU_API_KEY + BAIDU_SECRET_KEY |

启用命令（写入用户级环境变量，立即生效；默认先验证后保存，`-Force` 强制保存）：

```powershell
scripts\setup.ps1 -SetCustom -BaseUrl <url> -Key <key> -Model <model> -Verify   # 默认视觉通道（必配才能识图；glm 兜底除外）
scripts\setup.ps1 -SetGen -BaseUrl <url> -Key <key> -Model <model> -Verify      # 生图通道（必配才能生图）
scripts\setup.ps1 -SetKey -Channel glm -Key <key> -Verify                       # 免费兜底通道（建议）
scripts\setup.ps1 -SetKey -Channel baidu-ocr -Key <ak> -Secret <sk> -Verify
scripts\setup.ps1 -Status    # 查看配置状态
scripts\setup.ps1 -Help      # 查看注册指引
scripts\setup.ps1 -RemoveKey -Channel <name|custom|gen>
```

## 本地通道

| 运行时 | 端口 | 说明 |
|---|---|---|
| Ollama | 11434 | 首选；`ollama pull qwen2.5-vl:3b` 后即可用 |
| LM Studio | 1234 | 启动本地服务（OpenAI 兼容） |
| llama.cpp | 8080 | `llama-server -m model.gguf --port 8080` |

选型：`scripts/local-select.ps1` 用 llmfit（`uv tool install llmfit` 或 `scoop install llmfit`）检测硬件并过滤视觉模型；llmfit 缺失或结果为空时按显存兜底：

- VRAM ≥ 8GB：qwen2.5-vl:7b / llama3.2-vision:11b / qwen2.5-vl:3b / minicpm-v / moondream
- VRAM ≥ 4GB：qwen2.5-vl:3b / minicpm-v / moondream / smolvlm
- 无 GPU：moondream / smolvlm（CPU 可跑，较慢）

选型结果缓存：`%USERPROFILE%\.ds-vision\local-profile.json`。

## 验证步骤

视觉通道用一张小测试图执行：

```powershell
scripts\vlm-vision.ps1 -ImagePath <test.png> -Prompt "describe this image in one sentence" -Channel custom
```

生图通道验证：

```powershell
scripts\image-gen.ps1 -Prompt "a tiny solid-color test image" -Json
```

通过标准：返回内容且非 401/404/429。模型 ID 失效（404）时更新本表；401/403 说明 key 无效；429 说明限流（换通道）。

## 错误码（vlm-vision.ps1 / image-gen.ps1）

| 退出码 | 含义 |
|---|---|
| 0 | 成功，stdout 为内容/图片路径 |
| 1 | 通用失败（文件不存在、空响应等） |
| 2 | 缺 key / 缺配置 / 认证失败（401/403） |
| 3 | 限流（429，含额度超限/欠费） |
| 4 | 网络/服务器错误（500/503） |
| 5 | 请求被拒（404/400，通常是模型 ID 失效） |

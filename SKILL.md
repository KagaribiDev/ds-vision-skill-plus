---
name: ds-vision-skill-plus
description: >
  给纯文本模型(DeepSeek 等)加"眼睛"的多通道视觉路由与生图转发。当用户发送、粘贴或引用图片、截图、照片、图表、架构图、UI 截图、代码截图、数学题图片、扫描件、PDF 或文档,并要求描述、理解、推理、阅读、提取文字、OCR、解析图表或分析内容时使用(例如"看看这张图"、"识别图中文字"、"解析这个图表");当用户要求画图、生成图片、插图、海报、头像、图片创作等生图需求时同样使用。视觉理解默认通道为 custom(用户自定义 OpenAI 兼容视觉模型,请求路径/API Key/模型名统一由 VISION_CUSTOM_* 配置,可填 Qwen3.7-Plus 或任意模型),失败时降级免费 GLM 通道。文档解析用 MinerU;OCR 用百度优先、Windows 本地兜底。生图走 OpenAI 标准 images/generations 接口转发到用户配置的 VISION_GEN_* 模型,生成完毕保存本地并把图片路径返回给 agent。所有工具结果输出标准化 JSON,把像素转成文字/图片后交给主模型(DeepSeek)推理。
---

# DS 视觉桥 Plus(Vision Enhancement Skill)

本技能是 DeepSeek 的视觉能力扩展模块:负责视觉任务识别、工具选择、结果整理,不直接替代 DeepSeek。视觉输入先转成文本/结构化 JSON,再交给 DeepSeek 推理;生图需求转发到用户配置的第三方生图模型,生成结果(本地图片路径)返回给 DeepSeek 汇报给用户。

**默认视觉通道是 custom(用户自定义 OpenAI 兼容模型)**。用户通过 `setup.ps1 -SetCustom -BaseUrl <url> -Key <key> -Model <model>` 配置自己的视觉模型(如 Qwen3.7-Plus、GLM、GPT-4o 或任何 OpenAI 兼容模型);custom 未配置或调用失败时,按降级链依次尝试免费 GLM 通道,保证 skill 仍可用。

## 角色与能力

| 层 | 工具 | 职责 |
|---|---|---|
| 视觉理解(默认,用户自定义) | custom(`VISION_CUSTOM_MODEL`,OpenAI 兼容) | 图片理解、图像推理、图表/架构图分析、UI 截图、代码截图、数学题、多模态交互;用户在此配置任何想要的视觉模型 |
| 视觉理解(降级/免费) | GLM-4V-Flash(简单)、GLM-4.1V-Thinking-Flash(复杂) | custom 失败或未配置 key 时的免费兜底通道;复杂视觉推理 |
| 生图(需配置) | 用户配置的生图模型(`VISION_GEN_MODEL`,OpenAI images/generations) | 文生图、插画、海报、头像等;生成图片保存本地并返回路径 |
| 文档解析 | MinerU(flash / extract) | PDF/论文/报告解析、表格提取、公式识别、多栏排版恢复、Markdown 结构化输出 |
| OCR | 百度 OCR(优先)、Windows OCR(本地兜底,另可部署 PaddleOCR/Tesseract) | 图片文字提取、扫描件识别、表格文字、票据识别、低清图片文字恢复 |

## 路由决策

输入:用户上传图片、PDF、截图、扫描件,或提出生图需求。按以下顺序判断:

1. **生图需求**(画/生成/绘制/创作一张图、插画、海报、头像、Logo 等,无输入图片)→ 生图:`scripts/image-gen.ps1 -Prompt "<描述>" [-Size 1024x1024] [-Json]`。需要用户已配置 `VISION_GEN_BASE_URL` + `VISION_GEN_API_KEY` + `VISION_GEN_MODEL`(未配置则提示用户先 `setup.ps1 -SetGen`);生图无免费兜底。生成完成后,按"输出规范"里的展示要求,在回答末尾用 Markdown 图片语法向用户展示生成的图片。
2. **PDF / 论文 / 长文档 / 多页扫描** → 文档解析:`scripts/mineru-extract.ps1 -FilePath <file> [-Mode flash|extract] [-Json]`。不要用视觉模型处理超长文档;`extract` 模式需要 `MINERU_TOKEN`。
3. **图片 + 需要理解/推理**(描述、问答、图表、架构、UI、代码、数学题)→ 视觉理解:
   - 默认通道:`scripts/vlm-vision.ps1 -ImagePath <path> -Prompt "<问题>" -Channel custom [-Json]`(用户配置的 OpenAI 兼容视觉模型)
   - 降级通道:`-Channel glm`(免费)/ `-Channel glm-thinking`(复杂推理,免费)/ `-Channel local`
   - 简单 vs 复杂:custom 通道单模型可同时处理简单与复杂任务;只有 custom 不可用时才按"多步骤推理/逻辑/数学/密集图表 → glm-thinking;其余 → glm"降级选择。
4. **图片 + 只要文字**(OCR、扫描件文字、票据、表格文字)→ OCR:`scripts/baidu-ocr.ps1 -ImagePath <path> [-Accurate] [-Json]`;无百度 key 或失败 → `scripts/windows-ocr.ps1 -ImagePath <path> [-Json]`(离线)→ 仍需要版式/表格时 → MinerU。
5. **无法判断** → 默认调用 `custom`;custom 不可用则 `glm-thinking`。

执行前可运行 `scripts/preflight.ps1` 确认可用通道;执行后必须按下方输出规范整理结果。

## 输出规范

所有视觉/生图工具调用结果必须标准化为 JSON:

```json
{
  "task_type": "image_reasoning | image_generation | document_parsing | ocr",
  "tool_used": "实际调用的模型或工具",
  "confidence": "high | medium | low",
  "result": "视觉分析内容 / 生图本地文件路径",
  "metadata": { "额外信息" }
}
```

- `vlm-vision.ps1`、`image-gen.ps1`、`windows-ocr.ps1`、`baidu-ocr.ps1`、`mineru-extract.ps1` 均支持 `-Json` 直接输出该结构;`-Json` 未指定时输出纯文本/图片路径(快速预览用)。
- DeepSeek 推理时只使用 `result` 字段内容(生图时为本地图片路径,可向用户展示该文件);向用户汇报时附带 `task_type` 与 `tool_used`。
- **生图完成后的展示要求(三级策略,按优先级)**:agent 必须在回答末尾向用户展示生成的图片——
  1. **URL 展示**:若 `metadata.url` 是非空公网链接,用 `![生成的图片](<url>)` 展示(即时、成本最低;url 可能有时效,展示的同时附一句本地保存路径);
  2. **工作区相对路径**:url 缺失或失效时,把图片复制到当前工作区(如会话附件目录),用相对路径 `![生成的图片](<相对路径>)` 引用;
  3. **base64 嵌入**:前两者都无法渲染时,读取图片转 base64,用 `![生成的图片](data:image/png;base64,...)` 嵌入(仅适合较小图片;大图先压缩到 512px 或 JPEG)。
  无论哪种,都保留一句话说明生成位置(本地路径),方便用户找文件。
- `confidence` 由工具默认给出;OCR 结果乱码、视觉模型回答可疑时,把置信度降级并在 metadata 说明。

## 降级链(异常处理)

- 视觉理解失败(401/429/网络/空响应):**custom(用户配置)→ glm → glm-thinking → local**;全失败 → 用 OCR 提取文字后交回 DeepSeek。
- custom 通道常见失败:缺配置 / 401(退出码 2)→ 提示配置 `setup.ps1 -SetCustom` 或切 glm;429(退出码 3,含额度超限/欠费)→ 切 glm。
- 生图失败(未配置/401/429/网络)→ 明确报告失败原因并提示配置 `setup.ps1 -SetGen`;同一配置不反复重试。
- MinerU 失败或无内容:降级 OCR(baidu-ocr → windows-ocr),把识别文本交回 DeepSeek。
- OCR 质量低(乱码/缺行/置信度 low):调用 `glm-thinking` 重新理解原图(custom 可用时优先 custom)。
- 同一通道失败不要反复重试;429/401/网络错误直接切下一通道。
- 全部失败:明确告诉用户失败原因,请其描述图片。

## 成本优化策略

- **custom 通道费用以用户配置的服务商为准**;识图结果按"图片哈希 + prompt + 通道 + 模型"缓存到 `%USERPROFILE%\.ds-vision\cache\`,命中直接复用;`-NoCache` 强制重跑。同一图片同一问题不重复解析;优先复用本会话已得结果。
- GLM 免费通道仅在降级时使用(不额外花钱)。
- 生图按次计费,不做缓存(每次生成都是新图);多张生图前先确认用户接受费用。
- 长文档优先 MinerU,不用视觉模型逐页喂图。
- OCR 优先百度免费额度;无网络/失败时才用本地 OCR。
- 多张图片循环处理前,先确认用户是否接受付费通道;在意成本时用 `-Channel glm`。

## 脚本用法

- `scripts/preflight.ps1`:探测 key/工具/本地端口,输出"任务类型 → 可用通道"矩阵(只读,不联网)。
- `scripts/vlm-vision.ps1 -ImagePath <path> -Prompt "<问题>" -Channel <custom|glm|glm-thinking|local> [-Json] [-NoCache]`:视觉理解/推理,**默认 custom(用户配置的 OpenAI 兼容视觉模型)**。`-Model/-BaseUrl/-ApiKey` 可覆盖通道默认;`local` 自动探测 Ollama(11434)/LM Studio(1234)/llama.cpp(8080)。
- `scripts/image-gen.ps1 -Prompt "<描述>" [-Size 1024x1024] [-N 1] [-OutDir <dir>] [-Json]`:生图(OpenAI images/generations),需 `VISION_GEN_BASE_URL`+`VISION_GEN_API_KEY`+`VISION_GEN_MODEL`;图片默认保存到用户 Downloads 目录(可用 `-OutDir` 指定其他位置),`result` 返回本地路径。
- `scripts/baidu-ocr.ps1 -ImagePath <path> [-Accurate] [-Json]`:百度 OCR(标准/高精度),需要 `BAIDU_API_KEY`+`BAIDU_SECRET_KEY`。
- `scripts/windows-ocr.ps1 -ImagePath <path> [-Json]`:Windows 离线 OCR。
- `scripts/mineru-extract.ps1 -FilePath <file> [-Mode flash|extract] [-Json]`:MinerU 文档解析封装,输出 Markdown。
- `scripts/local-select.ps1 [-Force]`:llmfit 选本地视觉模型,结果缓存到 `%USERPROFILE%\.ds-vision\local-profile.json`。
- `scripts/setup.ps1 -Status / -Help / -SetKey / -RemoveKey / -SetCustom / -SetGen / -Verify`:配置引导。

约定:脚本源码 ASCII-only,中文通过参数传入;图片 >15MB 先缩放或用 MinerU;多张图片循环处理、汇总输出。

## 配置引导(安装后)

1. 运行 `scripts/setup.ps1 -Status` 展示各通道状态;需要注册链接时运行 `scripts/setup.ps1 -Help`。
2. **视觉默认通道(必配才能识图,否则走 glm 兜底)**:`setup.ps1 -SetCustom -BaseUrl <url> -Key <key> -Model <model> -Verify`。BaseUrl/Key/Model 全部按 OpenAI 统一请求规范填你自己的服务商;想用千问模型就填 DashScope 地址 + 模型名 + key(注册 https://platform.qianwenai.com/home/api-keys)。
3. **生图通道(必配才能生图)**:`setup.ps1 -SetGen -BaseUrl <url> -Key <key> -Model <model> -Verify`,要求服务商支持 OpenAI 标准 `POST {base}/v1/images/generations`。
4. 降级通道(可选但建议):glm / glm-thinking 共用 `GLM_API_KEY`(`setup.ps1 -SetKey -Channel glm -Key <key> -Verify`);baidu-ocr 需要 `-Key` + `-Secret`。
5. 本地通道:询问用户是否安装 Ollama(`winget install Ollama.Ollama` + `ollama pull qwen2.5-vl:3b`,安装前需用户确认);完成后运行 `scripts/local-select.ps1 -Force`。
6. 配置立即生效(写入用户级环境变量);移除用 `scripts/setup.ps1 -RemoveKey -Channel <name|custom|gen>`。
7. 配置完再跑一次 `scripts/setup.ps1 -Status` 汇报最终可用通道。

## 报告与隐私

- 每次识图/生图报告 `task_type` + `tool_used` + 结果概要;多通道试过时简要说明降级过程。
- 生图汇报必须在回答末尾向用户展示生成的图片,按三级策略:优先 `![生成的图片](<metadata.url>)`;url 缺失/失效则复制到工作区用相对路径;仍不行则 base64 data URI 嵌入。均附带一句本地保存路径说明。
- 云端通道会把图片发送到你的视觉/生图服务商、智谱(GLM)/百度/你的中转服务商服务器;用户明确在意隐私时,优先 Windows OCR(不出网)或本地通道。

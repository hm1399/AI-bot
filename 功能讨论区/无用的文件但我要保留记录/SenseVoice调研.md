# SenseVoice 语音识别调研报告

> 调研日期：2026-03-18
> 项目地址：https://github.com/FunAudioLLM/SenseVoice
> 开发团队：阿里巴巴 FunAudioLLM

## 一、SenseVoice 是什么

SenseVoice 是阿里巴巴开发的**多任务语音理解基础模型**，不仅做语音识别（ASR），还同时支持：

- **语音识别（ASR）**：语音转文字
- **语种识别（LID）**：自动检测说的是什么语言
- **语音情感识别（SER）**：检测情绪（开心、悲伤、愤怒、中性）
- **音频事件检测（AED）**：检测背景音（音乐、掌声、笑声、咳嗽等）
- **逆文本正则化（ITN）**：将口语数字/日期转为书面形式

提供两个版本：

| 版本 | 架构 | 参数量 | 语言支持 | 特点 |
|------|------|--------|----------|------|
| SenseVoice-Small | 编码器，非自回归 | ~244M（与Whisper-Small相当） | 5种（中/英/粤/日/韩） | 极速推理 |
| SenseVoice-Large | 编码器-解码器 | 更大 | 50+种 | 高精度，支持时间戳 |

## 二、核心优势：速度

这是 SenseVoice 最大的卖点：

| 模型 | 10秒音频推理耗时 | 相对速度 |
|------|-----------------|----------|
| **SenseVoice-Small** | **70ms** | **基准** |
| Whisper-Small | ~350ms | 慢5倍 |
| Whisper-Large-V3 | ~1050ms | 慢15倍 |

原因：SenseVoice-Small 采用**非自回归**架构（一次性输出全部结果），而 Whisper 是自回归的（逐个token生成）。

## 三、识别精度对比

### 中文/粤语
SenseVoice-Small **明显优于** Whisper，在 AISHELL-1、AISHELL-2、WenetSpeech 等基准上表现更好。

### 英语
与 Whisper-Small 相当，略逊于 Whisper-Large-V3。

### 情感识别
即使没有针对性微调，也达到或超过了当前最好的专用情感识别模型。

## 四、硬件需求

SenseVoice 对硬件要求非常友好：

- **CPU推理**：完全支持，通过 ONNX Runtime 或 SenseVoice.cpp（基于GGML）
- **GPU推理**：支持 PyTorch CUDA 和 TensorRT
- **边缘设备**：可通过 sherpa-onnx 部署到树莓派、iOS、Android
- **量化支持**：SenseVoice.cpp 支持 3/4/5/8-bit 量化，零第三方依赖

**结论**：普通电脑CPU就能跑，70ms延迟完全够用。

## 五、部署方式

### 方式1：FunASR AutoModel（推荐，支持VAD长音频）

```python
from funasr import AutoModel
from funasr.utils.postprocess_utils import rich_transcription_postprocess

model = AutoModel(
    model="FunAudioLLM/SenseVoiceSmall",
    vad_model="fsmn-vad",
    vad_kwargs={"max_single_segment_time": 30000},
    device="cuda:0",  # 或 "cpu"
    hub="hf",
)

res = model.generate(
    input="audio.wav",
    cache={},
    language="auto",  # 自动检测语言
    use_itn=True,
    batch_size_s=60,
    merge_vad=True,
)
text = rich_transcription_postprocess(res[0]["text"])
```

### 方式2：ONNX Runtime（生产部署）

```python
from funasr_onnx import SenseVoiceSmall
model = SenseVoiceSmall("iic/SenseVoiceCTC", batch_size=1, quantize=True)
result = model(["audio.wav"])
```

### 方式3：sherpa-onnx（跨平台）

支持 C++、C、Python、C#、Go、Swift、Kotlin、Java、JavaScript、Dart，有预编译的 Android APK。

### 方式4：SenseVoice.cpp（纯C/C++）

零依赖，支持极低bit量化，适合嵌入式或极简部署。

## 六、流式/实时支持

SenseVoice-Small **本身不是流式模型**（处理完整语句），但：

- 有社区项目 `streaming-sensevoice` 实现了**伪流式**（分块推理 + 截断注意力）
- sherpa-onnx 提供实时语音识别支持
- 70ms处理10秒音频，即使非流式，对语音助手场景来说延迟已经足够低

## 七、许可证

| 部分 | 许可证 |
|------|--------|
| 代码（FunASR框架） | MIT |
| 模型权重 | FunASR Model Open Source License v1.1（阿里自定义） |

模型许可证要点：
- ✅ 允许使用、复制、修改、分享
- ✅ **未明确禁止商用**
- ⚠️ 需注明出处和作者
- ⚠️ 非标准开源许可证，商用前建议仔细审查

## 八、与 Whisper 的全面对比

| 对比项 | SenseVoice-Small | Whisper-Small | Whisper-Large-V3 |
|--------|-----------------|---------------|-------------------|
| 参数量 | ~244M | ~244M | ~1.55B |
| 架构 | 非自回归 | 自回归 | 自回归 |
| 10秒音频延迟 | **70ms** | ~350ms | ~1050ms |
| 中文识别 | **更好** | 一般 | 尚可 |
| 英文识别 | 相当 | 相当 | **略好** |
| 支持语言数 | 5/50+ | 99+ | 99+ |
| 情感识别 | **✅** | ❌ | ❌ |
| 音频事件检测 | **✅** | ❌ | ❌ |
| 语种自动识别 | **✅ 内置** | ✅ | ✅ |
| 社区生态 | 较新，较小 | **非常成熟** | **非常成熟** |
| 部署方案 | 多样 | **最多** | **最多** |

## 九、适用性分析：AI-Bot 桌面助手

### ✅ 非常适合的点

1. **速度极快**：70ms处理10秒音频，在普通电脑CPU上就能实现近实时响应，完全满足"说话→识别→回复"的交互流程
2. **中文识别优秀**：我们的产品主要面向中文用户，SenseVoice在中文上明显优于Whisper
3. **情感识别加分**：可以检测用户情绪，让AI回复更有温度（例如检测到用户不开心，语气更温柔）
4. **音频事件检测**：可以识别背景噪音，提高交互体验
5. **集成简单**：`pip install funasr`，几行代码即可替换现有Whisper
6. **硬件友好**：不需要GPU，普通电脑CPU就行
7. **中英日韩粤五语支持**：覆盖我们目标用户群的主要语言

### ⚠️ 需要注意的点

1. **语言覆盖有限**：Small版本只支持5种语言（但够用）
2. **社区生态较新**：Whisper的社区更成熟，遇到问题找解决方案更容易
3. **许可证非标准**：商用前需要仔细审查阿里的模型许可证
4. **非原生流式**：不过70ms延迟已经让这个问题不太重要

### 💡 建议

**推荐用 SenseVoice-Small 替换 Whisper 作为 ASR 引擎**，理由：

1. 速度快5倍，用户体验更好
2. 中文识别更准确
3. 额外的情感识别功能可以提升产品差异化
4. 硬件需求更低

**建议集成方案**：
- 使用 FunASR AutoModel + VAD（语音活动检测）
- 设备端（ESP32-S3）录音 → 发送到服务端 → SenseVoice识别 → 返回文字
- 利用情感识别结果调整AI回复风格

## 十、安装依赖

```bash
# 基础安装
pip install funasr

# ONNX部署（生产环境推荐）
pip install funasr-onnx

# Python 3.8+ 即可
# 主要依赖：PyTorch, torchaudio
# 模型权重首次运行自动从 HuggingFace 下载
```

## 参考资料

- [SenseVoice GitHub](https://github.com/FunAudioLLM/SenseVoice)
- [SenseVoice HuggingFace 模型卡](https://huggingface.co/FunAudioLLM/SenseVoiceSmall)
- [FunAudioLLM 论文 (arXiv:2407.04051)](https://arxiv.org/html/2407.04051v1)
- [sherpa-onnx SenseVoice 文档](https://k2-fsa.github.io/sherpa/onnx/sense-voice/index.html)
- [FunASR 模型许可证](https://github.com/modelscope/FunASR/blob/main/MODEL_LICENSE)

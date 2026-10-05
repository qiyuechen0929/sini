# 流式语音识别模型（端侧）

把 **sherpa-onnx** 的流式 Zipformer 中英双语模型解压到这个目录，语音识别（流式转写 / 语音通话）才能工作。

需要的文件：

```text
encoder-epoch-99-avg-1.int8.onnx
decoder-epoch-99-avg-1.onnx
joiner-epoch-99-avg-1.int8.onnx
tokens.txt
```

推荐模型：`sherpa-onnx-streaming-zipformer-bilingual-zh-en-int8-2023-02-20`

- 模型下载：[sherpa-onnx releases](https://github.com/k2-fsa/sherpa-onnx/releases)
- 推理位置：**本机 CPU**，不联网、不上传

> 目录留空时：语音相关功能不可用，其余功能一切正常。

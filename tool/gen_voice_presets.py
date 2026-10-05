#!/usr/bin/env python3
"""重新生成「似你」的 6 个预设音色参考音频。

为什么需要这个脚本：预设音色是 **零样本克隆**（ZipVoice）的参考音频 ——
用户在创建页试听时听到的就是这几个 mp3 原文件，所以它们的质量直接决定
「这个声音像不像人」。以前是手工跑 edge-tts 生成的，参数没留下来，
想改就得重猜。这里把参数固化成代码，改声音只需要改 SPEC 再跑一遍。

用法：
    python tool/gen_voice_presets.py                # 生成到 web/models/presets/
    python tool/gen_voice_presets.py --dry-run      # 只打印将执行的命令
    python tool/gen_voice_presets.py --only yujie   # 只重做某一个

依赖：
    - edge-tts（pip install edge-tts），需要联网访问微软的语音服务
    - ffmpeg / ffprobe（做两遍 loudnorm 响度归一化 + 时长检查）

生成后**必须**同步三处，否则用户听到的还是旧音频或克隆跑偏：
    1. lib/features/voice/presets.dart 的 promptText / kPresetAudioVersion
    2. web/models/presets/manifest.json
    3. flutter build web --release（把 web/ 拷进 build/web/）

关于文本（踩过的坑）：
    - promptText 必须与音频**逐字一致**，多一个字 ZipVoice 的对齐就乱。
    - 写成**口语短句**，有语气词、疑问、停顿；书面长句出来就是机器念稿。
    - 长度 **5~9 秒**：太短模型不稳，太长合成慢且容易糊。
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys

# ── 音色规格 ──────────────────────────────────────────────────────────────
# id / edge-tts voice / rate / pitch / 要念的文本（= presets.dart 的 promptText）
#
# edge-tts 的 zh-CN 标准音色只有 5 个：Xiaoxiao(女·暖) Xiaoyi(女·活泼)
# Yunxi(男·阳光) Yunjian(男·有力) Yunyang(男·沉稳)；另有 liaoning/shaanxi 两个
# 方言音色不适合当通用人设。所以「清冷御姐」和「温柔女声」共用 Xiaoxiao，
# 靠音高（差 11Hz）和语速（差 9%）拉开区别。
SPEC = [
    {
        "id": "bazongzi",
        "voice": "zh-CN-YunjianNeural",
        "rate": "-6%",
        "pitch": "-8Hz",
        "text": "行，这事就这么定了，别再讨论。你要是不服，就拿结果来说话。",
    },
    {
        "id": "yangguang",
        "voice": "zh-CN-YunxiNeural",
        "rate": "+10%",
        "pitch": "+6Hz",
        "text": "嘿！今天天气也太好了吧！走走走，别宅着了，咱们出去打会儿球，出出汗多痛快！",
    },
    {
        "id": "mengmei",
        "voice": "zh-CN-XiaoyiNeural",
        "rate": "+6%",
        "pitch": "+14Hz",
        "text": "哇，这个蛋糕看着也太好吃了吧！我们一人一半好不好？不行不行，我要大的那半，你让着我嘛。",
    },
    {
        "id": "yujie",
        "voice": "zh-CN-XiaoxiaoNeural",
        "rate": "-12%",
        "pitch": "-8Hz",
        "text": "你不用急着解释。我听的不是你说什么，而是你做什么。想清楚了，再来找我。",
    },
    {
        "id": "wenrou",
        "voice": "zh-CN-XiaoxiaoNeural",
        "rate": "-3%",
        "pitch": "+3Hz",
        "text": "今天辛苦啦，我给你煮了点汤，趁热喝。工作再忙，也要记得好好吃饭，好好照顾自己。",
    },
    {
        "id": "chenwen",
        "voice": "zh-CN-YunyangNeural",
        "rate": "-6%",
        "pitch": "-2Hz",
        "text": "人生就像一场旅行，重要的不是目的地，而是沿途的风景。慢一点也没关系，我们总会到的。",
    },
]

# 统一响度：不同音色原始 mean_volume 能差 7dB，不归一化用户在试听列表里
# 点来点去会觉得「忽大忽小」。
TARGET_I = -18.0
TARGET_TP = -1.5
TARGET_LRA = 11.0
OUT_SR = "24000"
OUT_CH = "1"
OUT_BR = "48k"

MIN_SECONDS = 3.0
MAX_SECONDS = 10.0


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", **kw)


def duration(path):
    r = run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "csv=p=0", path])
    try:
        return float(r.stdout.strip())
    except ValueError:
        return -1.0


def synth(spec, out_path):
    """edge-tts 合成一条参考音频。"""
    return run(["edge-tts",
                "--voice", spec["voice"],
                f"--rate={spec['rate']}",
                f"--pitch={spec['pitch']}",
                "--text", spec["text"],
                "--write-media", out_path])


def normalize(path):
    """两遍 loudnorm：先测量，再按测量值精确归一化（单遍会动态压缩、容易 pumping）。"""
    p1 = run(["ffmpeg", "-hide_banner", "-i", path,
              "-af", f"loudnorm=I={TARGET_I}:TP={TARGET_TP}:LRA={TARGET_LRA}:print_format=json",
              "-f", "null", "-"])
    m = re.search(r"\{[^{}]*\"input_i\"[^{}]*\}", p1.stderr, re.S)
    if not m:
        return False, "测量失败：" + p1.stderr[-300:]
    s = json.loads(m.group(0))
    af = (f"loudnorm=I={TARGET_I}:TP={TARGET_TP}:LRA={TARGET_LRA}"
          f":measured_I={s['input_i']}:measured_TP={s['input_tp']}"
          f":measured_LRA={s['input_lra']}:measured_thresh={s['input_thresh']}"
          f":offset={s.get('target_offset', 0)}:linear=true")
    tmp = path + ".norm.mp3"
    p2 = run(["ffmpeg", "-hide_banner", "-y", "-i", path, "-af", af,
              "-ar", OUT_SR, "-ac", OUT_CH, "-b:a", OUT_BR, tmp])
    if p2.returncode != 0 or not os.path.exists(tmp):
        return False, "归一化失败：" + p2.stderr[-300:]
    os.replace(tmp, path)
    return True, "ok"


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    default_out = os.path.join(here, "..", "web", "models", "presets")

    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.normpath(default_out),
                    help="输出目录（默认 web/models/presets）")
    ap.add_argument("--only", action="append", default=None,
                    help="只重做指定 id（可重复）")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    for exe in ("edge-tts", "ffmpeg", "ffprobe"):
        if shutil.which(exe) is None:
            print(f"[错误] 找不到 {exe}，请先安装。", file=sys.stderr)
            return 1

    os.makedirs(args.out, exist_ok=True)
    todo = [s for s in SPEC if not args.only or s["id"] in args.only]
    if not todo:
        print("[错误] --only 没有匹配到任何 id", file=sys.stderr)
        return 1

    failed = []
    for spec in todo:
        path = os.path.join(args.out, spec["id"] + ".mp3")
        print(f"\n=== {spec['id']} · {spec['voice']} {spec['rate']} {spec['pitch']} ===")
        print(f"    文本：{spec['text']}")
        if args.dry_run:
            continue

        r = synth(spec, path)
        if r.returncode != 0 or not os.path.exists(path):
            failed.append((spec["id"], "edge-tts 失败：" + (r.stderr or "")[-300:]))
            continue

        d = duration(path)
        print(f"    合成时长 {d:.2f}s")

        ok, msg = normalize(path)
        if not ok:
            failed.append((spec["id"], msg))
            continue

        d = duration(path)
        peak = run(["ffmpeg", "-hide_banner", "-i", path, "-af", "volumedetect",
                    "-f", "null", "-"]).stderr
        mm = re.search(r"mean_volume:\s*([-\d.]+) dB", peak)
        print(f"    归一化后 {d:.2f}s  平均电平 {mm.group(1) if mm else '?'} dB")

        if not (MIN_SECONDS <= d <= MAX_SECONDS):
            # 不直接判失败，但明确提醒：超出区间克隆质量会掉
            print(f"    [警告] 时长 {d:.2f}s 不在建议区间 {MIN_SECONDS}~{MAX_SECONDS}s，"
                  f"建议调整文本长度或 rate。")

    print("\n─────────────────────────────")
    if failed:
        for i, why in failed:
            print(f"[失败] {i}: {why}")
        return 1
    print(f"完成 {len(todo)} 条 → {args.out}")
    print("别忘了：同步 presets.dart 的 promptText 并把 kPresetAudioVersion +1，"
          "再 flutter build web --release。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

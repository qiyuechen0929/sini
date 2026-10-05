"""生成用于验证「聊天记录导入」的测试语料。

刻意覆盖真实的坑：
  - 微信 MemoTrace 的 TXT 是 **GBK 编码**，直接按 UTF-8 读会乱码
  - MemoTrace 的 CSV 是 UTF-8-BOM，且发送者要靠 IsSender + Talker 推
  - QQ 导出的昵称带 (QQ号)
  - Telegram 的 text 既可能是字符串，也可能是实体数组
  - 通用格式的列名千奇百怪

同时语料本身带**明显的说话风格**，用于肉眼核对画像是否学到了东西：
  「小雨」短句、爱用～、几乎不用句号、口头禅是「嗯」「真的假的」「还行」
"""
import json
import os
from datetime import datetime, timedelta

OUT = r"D:\sini\似你_flutter_前端_MVP\sini_flutter_frontend\test\fixtures"
os.makedirs(OUT, exist_ok=True)

# ── 构造一段有风格特征的对话 ──────────────────────────────
# (是否小雨说的, 内容)
DIALOG = [
    (False, "在干嘛呢？"),
    (True, "躺着～"),
    (False, "周末要不要一起去看那个展"),
    (True, "嗯？哪个"),
    (False, "就上次说的那个摄影展，在美术馆"),
    (True, "哦哦想到了"),
    (True, "去呗"),
    (False, "你不是说要加班吗"),
    (True, "推了"),
    (False, "真的假的"),
    (True, "骗你干嘛～"),
    (False, "行，那我买票了，周六下午两点"),
    (True, "嗯嗯"),
    (True, "不过我得晚点到"),
    (False, "为什么"),
    (True, "上午要去医院复查一下牙"),
    (False, "牙还没好啊"),
    (True, "还行，就是有点麻烦"),
    (False, "那我自己先进去等你"),
    (True, "好～"),
    (False, "记得带伞，明天有雨"),
    (True, "知道了知道了"),
    (True, "你怎么比我妈还啰嗦"),
    (False, "……行吧"),
    (True, "哈哈哈"),
    (False, "笑什么"),
    (True, "没什么"),
    (True, "就是觉得你挺好玩的"),
    (False, "谢谢夸奖"),
    (True, "不客气～"),
    (False, "对了你上次那个项目怎么样了"),
    (True, "别提了"),
    (True, "改了七八版"),
    (False, "这么惨"),
    (True, "嗯，甲方想要五彩斑斓的黑"),
    (False, "哈哈哈哈哈这个比喻绝了"),
    (True, "别笑"),
    (True, "我真的会谢"),
    (False, "那你怎么办"),
    (True, "先这么交着吧"),
    (True, "反正他也不会看"),
    (False, "你这心态可以"),
    (True, "没办法～"),
    (False, "晚上吃什么"),
    (True, "不知道"),
    (True, "你有推荐吗"),
    (False, "公司楼下新开了家面馆"),
    (True, "面啊"),
    (True, "行吧"),
    (False, "不想吃面？"),
    (True, "没有，就是最近吃太多了"),
    (True, "换别的也行"),
    (False, "那吃日料"),
    (True, "可以～"),
    (True, "你请客？"),
    (False, "凭什么"),
    (True, "因为你刚才笑我"),
    (False, "那算了吧，各付各的"),
    (True, "小气"),
    (True, "真的小气"),
    (False, "嗯，我小气，你别来了"),
    (True, "我错了嘛"),
    (True, "哈哈哈"),
    (False, "……"),
    (True, "生气啦？"),
    (False, "没有"),
    (True, "那就是生气了"),
    (False, "说了没有"),
    (True, "好吧～"),
    (True, "那我请你"),
    (False, "你请就你请"),
    (True, "嗯嗯"),
    (True, "几点"),
    (False, "七点吧，我先回趟家"),
    (True, "那我六点半到你楼下"),
    (False, "不用，直接店里见"),
    (True, "也行"),
    (True, "不过我想先去买杯咖啡"),
    (False, "你又喝咖啡，晚上睡不着别找我"),
    (True, "知道了"),
    (True, "啰嗦"),
    (False, "我啰嗦？"),
    (True, "没有没有"),
    (True, "你最好"),
]

BASE = datetime(2023, 3, 4, 20, 15)
rows = []
t = BASE
for is_ta, text in DIALOG:
    rows.append({
        "is_ta": is_ta,
        "sender": "小雨" if is_ta else "我",
        "text": text,
        "time": t,
    })
    t += timedelta(seconds=40 + (len(text) * 3))

# 扩到更多轮，让统计量与画像更稳（复制 3 遍，错开月份）
all_rows = []
for k in range(3):
    for r in rows:
        all_rows.append({
            "is_ta": r["is_ta"],
            "sender": r["sender"],
            "text": r["text"],
            "time": r["time"] + timedelta(days=30 * k),
        })

fmt = "%Y-%m-%d %H:%M:%S"

# ── 1) 微信 MemoTrace TXT（GBK 编码，时间+昵称，正文换行）──────────
lines = []
for r in all_rows:
    lines.append(f"{r['time'].strftime(fmt)} {r['sender']}")
    lines.append(r["text"])
with open(os.path.join(OUT, "wechat_memotrace_gbk.txt"), "w", encoding="gb18030") as f:
    f.write("\n".join(lines))

# ── 2) 微信 MemoTrace CSV（UTF-8-BOM，Talker + IsSender）─────────
csv_lines = ["localId,Time,Talker,IsSender,Type,SubType,Content"]
for i, r in enumerate(all_rows, start=1):
    content = r["text"].replace('"', '""')
    csv_lines.append(
        f'{i},{r["time"].strftime(fmt)},wxid_xiaoyu,{1 if not r["is_ta"] else 0},1,0,"{content}"'
    )
with open(os.path.join(OUT, "wechat_memotrace.csv"), "w", encoding="utf-8-sig") as f:
    f.write("\n".join(csv_lines))

# ── 3) QQ 导出 TXT（昵称带 QQ 号，UTF-8）────────────────────────
lines = []
for r in all_rows:
    name = f"{r['sender']}(10001)" if r["is_ta"] else "我(10002)"
    lines.append(f"{r['time'].strftime(fmt)} {name}")
    lines.append(r["text"])
with open(os.path.join(OUT, "qq_export.txt"), "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

# ── 4) Telegram result.json（text 混合字符串与实体数组）───────────
messages = []
for i, r in enumerate(all_rows, start=1):
    # 故意混用两种 text 形态，验证解析器都能处理
    if i % 5 == 0:
        text = [{"type": "bold", "text": r["text"]}]
    else:
        text = r["text"]
    messages.append({
        "id": i,
        "type": "message",
        "date": r["time"].strftime("%Y-%m-%dT%H:%M:%S"),
        "from": "小雨" if r["is_ta"] else "我",
        "from_id": "user10001" if r["is_ta"] else "user10002",
        "text": text,
    })
with open(os.path.join(OUT, "telegram_result.json"), "w", encoding="utf-8") as f:
    json.dump({"name": "小雨", "type": "personal_chat", "id": 10001, "messages": messages},
              f, ensure_ascii=False, indent=1)

# ── 5) 通用 CSV（自定义表头）──────────────────────────────────
csv_lines = ["发送时间,发送者,消息内容"]
for r in all_rows:
    content = r["text"].replace('"', '""')
    csv_lines.append(f'{r["time"].strftime(fmt)},{r["sender"]},"{content}"')
with open(os.path.join(OUT, "generic_chat.csv"), "w", encoding="utf-8") as f:
    f.write("\n".join(csv_lines))

# ── 6) 通用 TXT（昵称: 正文，无时间）────────────────────────────
lines = [f"{r['sender']}: {r['text']}" for r in all_rows]
with open(os.path.join(OUT, "generic_chat.txt"), "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

# ── 7) 带时间戳的通用 JSON（数组，sender/time/content）─────────────
data = [{
    "sender": r["sender"],
    "time": r["time"].strftime(fmt),
    "content": r["text"],
} for r in all_rows]
with open(os.path.join(OUT, "generic_chat.json"), "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=1)

print("fixtures written to", OUT)
for n in sorted(os.listdir(OUT)):
    p = os.path.join(OUT, n)
    print(f"  {n}  {os.path.getsize(p)} bytes")

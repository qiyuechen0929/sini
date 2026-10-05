"""假的 OpenAI 兼容服务，用于离线验证评测工具本身跑得通（不花钱、不需要真 Key）。

按请求内容区分三种调用：
  1. 风格取证（prompt 里含「语言风格取证」）→ 返回一份画像 JSON
  2. 盲评（prompt 里含「请判断 B」）      → 返回 {"score":..,"reason":..,"diff":..}
  3. 其他（生成回复）                    → 返回一句短句风格的回复
"""
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 8799

STYLE_JSON = {
    "summary": "句子很短，爱用波浪号，几乎不用句号",
    "catchphrases": ["嗯嗯", "好吧～", "还行"],
    "callUser": "你",
    "selfCall": "我",
    "nicknames": [],
    "speechHabits": ["几乎不用句号", "句子很短，常只有两三个字", "爱用～结尾"],
    "emojiHabit": "几乎不用表情",
    "lengthHabit": "平均 5 个字",
    "sampleLines": ["躺着～", "嗯嗯", "还行，就是有点麻烦", "知道了知道了"],
    "interests": ["看展", "咖啡"],
    "emotionalPattern": "开心时发哈哈哈；不高兴时说还行、就这样；关心时会催对方休息",
    "dos": ["保持极短", "结尾偶尔带～"],
    "donts": ["不要用句号", "不要长篇大论", "不要用书面语"],
    "topWords": ["知道", "还是", "感觉"],
    "traits": {"warmth": 0.6, "rationality": 0.4, "initiative": 0.5, "humor": 0.6},
    "relationshipGuess": "朋友",
    "sinceGuess": "2023",
    "memories": [{"text": "约好了周末去看摄影展", "kind": "fact"}],
}

FAKE_REPLIES = [
    "嗯嗯",
    "好～",
    "还行吧",
    "知道啦",
]

# 流式分支专用：故意给长一点、带多句的话，方便验证「按句切 + 边收边合成」
# 和实时字幕（短句一闪就过去了，截不到图）。
STREAM_REPLIES = [
    "嗯，我在呢。今天有点忙，刚把手里的活儿收尾。你那边怎么样？",
    "听到了听到了。你先别急，慢慢说，我一直在。",
]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _cors(self):
        # 浏览器里 Flutter Web 是直连这个 mock 的，没有 CORS 头会被拦掉。
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(n).decode("utf-8", "ignore")
        try:
            body = json.loads(raw)
        except Exception:
            body = {}
        text = json.dumps(body.get("messages", []), ensure_ascii=False)
        model = body.get("model", "")

        if "语言风格取证" in text:
            content = "```json\n" + json.dumps(STYLE_JSON, ensure_ascii=False) + "\n```"
        elif "请判断 B" in text:
            content = json.dumps(
                {"score": 8, "reason": "长度和语气接近，但少了点随意感", "diff": "生成里多了一个逗号"},
                ensure_ascii=False,
            )
        else:
            idx = 0
            # 让回复随请求数轮换，报告里能看出差异
            idx = getattr(self.server, "count", 0)
            self.server.count = idx + 1
            content = FAKE_REPLIES[idx % len(FAKE_REPLIES)]

        payload = {
            "id": "chatcmpl-mock",
            "object": "chat.completion",
            "model": model,
            "choices": [
                {"index": 0, "message": {"role": "assistant", "content": content},
                 "finish_reason": "stop"}
            ],
            "usage": {"prompt_tokens": 10, "completion_tokens": 10, "total_tokens": 20},
        }

        # 流式：按 SSE 逐字吐，最后 [DONE]。用来离线验证通话的「边收边合成」链路。
        if body.get("stream"):
            idx2 = getattr(self.server, "stream_count", 0)
            self.server.stream_count = idx2 + 1
            content = STREAM_REPLIES[idx2 % len(STREAM_REPLIES)]
            self.send_response(200)
            self._cors()
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            head = {
                "id": "chatcmpl-mock",
                "object": "chat.completion.chunk",
                "model": model,
                "choices": [{"index": 0, "delta": {"role": "assistant"}, "finish_reason": None}],
            }
            self.wfile.write(f"data: {json.dumps(head, ensure_ascii=False)}\n\n".encode("utf-8"))
            # 一次吐 2 个字，模拟真实的分片节奏
            for i in range(0, len(content), 2):
                piece = content[i:i + 2]
                chunk = {
                    "id": "chatcmpl-mock",
                    "object": "chat.completion.chunk",
                    "model": model,
                    "choices": [{"index": 0, "delta": {"content": piece}, "finish_reason": None}],
                }
                self.wfile.write(f"data: {json.dumps(chunk, ensure_ascii=False)}\n\n".encode("utf-8"))
                self.wfile.flush()
                time.sleep(0.02)
            tail = {
                "id": "chatcmpl-mock",
                "object": "chat.completion.chunk",
                "model": model,
                "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
            }
            self.wfile.write(f"data: {json.dumps(tail, ensure_ascii=False)}\n\n".encode("utf-8"))
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
            return

        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    srv = HTTPServer(("127.0.0.1", PORT), Handler)
    srv.count = 0
    srv.stream_count = 0
    print(f"mock openai listening on http://127.0.0.1:{PORT}/v1")
    srv.serve_forever()

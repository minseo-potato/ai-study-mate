"""교안 의미 검색. 쪽을 조각내 임베딩해 두고, 지금 이야기와 뜻이 가까운 조각을 찾는다.

키워드가 겹치지 않아도(예: '자리 바꾸기'와 '교환') 찾을 수 있게 하려는 것이다.
API 키가 없거나(데모 모드) 임베딩이 아직 없거나 호출이 실패하면 None을 돌려주고, 부르는 쪽은 키워드 검색만 쓴다.
"""
import asyncio
import hashlib
import math
import os
from array import array
from collections import OrderedDict

import httpx

from ai import demo_mode
from db import connect

CHUNK = 1200        # 조각 하나의 글자 수
OVERLAP = 200       # 조각끼리 겹치는 글자 수(문장이 잘려도 뜻을 잃지 않게)
DIMENSIONS = 512    # 벡터 길이. 짧게 받아도 검색 품질은 거의 같고 저장·계산이 가볍다.
BATCH = 64
MAX_CHUNKS = 3000   # 스터디 하나에서 임베딩할 조각 수

_running: dict[int, asyncio.Task] = {}
_queries: OrderedDict[str, list[float] | None] = OrderedDict()


def model() -> str:
    """임베딩 모델. OPENAI_EMBEDDING_MODEL=off 이면 쓰지 않는다."""
    name = os.getenv("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small").strip()
    return "" if name.lower() in ("", "off", "0", "none") else name


def enabled() -> bool:
    return bool(model()) and not demo_mode() and bool(os.getenv("OPENAI_API_KEY", "").strip())


def page_hash(body: str) -> str:
    return hashlib.sha1(body.encode("utf-8", "replace")).hexdigest()


def chunks(body: str) -> list[tuple[int, str]]:
    """(시작 위치, 글) 조각들. 짧은 쪽은 한 조각이다."""
    body = body.strip()
    if len(body) <= CHUNK:
        return [(0, body)] if body else []
    step = CHUNK - OVERLAP
    return [(i, body[i:i + CHUNK]) for i in range(0, len(body) - OVERLAP, step)]


def _pack(vector: list[float]) -> bytes:
    norm = math.sqrt(sum(x * x for x in vector)) or 1.0
    return array("f", (x / norm for x in vector)).tobytes()


def _unpack(blob: bytes) -> array:
    out = array("f")
    out.frombytes(blob)
    return out


async def _embed(texts: list[str], timeout: float) -> list[list[float]]:
    body = {"model": model(), "input": texts}
    if model().startswith("text-embedding-3"):
        body["dimensions"] = DIMENSIONS
    async with httpx.AsyncClient(timeout=timeout) as client:
        response = await client.post(
            os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1").rstrip("/") + "/embeddings",
            headers={"Authorization": f"Bearer {os.getenv('OPENAI_API_KEY', '')}"}, json=body)
        response.raise_for_status()
    data = sorted(response.json()["data"], key=lambda d: d["index"])
    return [d["embedding"] for d in data]


async def index_study(study_id: int) -> int:
    """아직 임베딩이 없거나 내용이 바뀐 쪽을 임베딩한다. 새로 만든 조각 수를 돌려준다."""
    if not enabled():
        return 0
    name = model()
    with connect() as db:
        pages = [(r["page_no"], r["body"]) for r in db.execute("SELECT page_no,body FROM pages WHERE study_id=? ORDER BY page_no", (study_id,))]
        done = {(r["page_no"], r["page_hash"]) for r in db.execute(
            "SELECT DISTINCT page_no,page_hash FROM page_vectors WHERE study_id=? AND model=?", (study_id, name))}
        # 바뀌었거나 지워진 쪽, 다른 모델로 만든 조각은 지운다.
        current = {(n, page_hash(b)) for n, b in pages}
        db.execute("DELETE FROM page_vectors WHERE study_id=? AND model!=?", (study_id, name))
        for page_no, digest in done - current:
            db.execute("DELETE FROM page_vectors WHERE study_id=? AND page_no=? AND page_hash=?", (study_id, page_no, digest))
    todo = [(n, page_hash(b), start, text) for n, b in pages if (n, page_hash(b)) not in done
            for start, text in chunks(b)][:MAX_CHUNKS]
    made = 0
    for i in range(0, len(todo), BATCH):
        part = todo[i:i + BATCH]
        vectors = await _embed([t for *_, t in part], timeout=60)
        with connect() as db:
            # 그사이 교안이 바뀌었으면 옛 내용의 조각은 넣지 않는다.
            live = {(r["page_no"], page_hash(r["body"])) for r in db.execute(
                "SELECT page_no,body FROM pages WHERE study_id=?", (study_id,))}
            rows = [(study_id, n, start, digest, name, _pack(v)) for (n, digest, start, _), v in zip(part, vectors)
                    if (n, digest) in live]
            db.executemany("INSERT OR REPLACE INTO page_vectors(study_id,page_no,start,page_hash,model,vector) "
                           "VALUES(?,?,?,?,?,?)", rows)
            made += len(rows)
    return made


def schedule(study_id: int) -> None:
    """교안을 올리거나 바꾼 뒤 뒤에서 임베딩을 만든다. 같은 스터디는 한 번에 하나만 돈다."""
    if not enabled():
        return
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        return
    task = _running.get(study_id)
    if task and not task.done():
        task.add_done_callback(lambda _: schedule(study_id))  # 도는 중에 또 바뀌었으면 끝난 뒤 한 번 더
        return

    async def run():
        try:
            await index_study(study_id)
        except Exception:
            pass  # 실패해도 키워드 검색으로 계속 쓸 수 있다. 다음 검색 때 다시 시도한다.
        finally:
            _running.pop(study_id, None)

    _running[study_id] = loop.create_task(run())


async def query_vector(text: str) -> array | None:
    """검색할 말의 벡터. 같은 말은 다시 부르지 않는다. 실패하면 None."""
    text = " ".join(text.split())[:3000]
    if not text or not enabled():
        return None
    key = f"{model()}\n{text}"
    if key in _queries:
        _queries.move_to_end(key)
        found = _queries[key]
    else:
        try:
            found = _unpack(_pack((await _embed([text], timeout=8))[0]))
        except Exception:
            found = None
        _queries[key] = found
        while len(_queries) > 512:
            _queries.popitem(last=False)
    return found


def vectors(db, study_id: int, pages: list[dict]) -> dict[int, list[tuple[int, array]]] | None:
    """쪽마다 (시작 위치, 벡터) 조각들. 고를 쪽 중 하나라도 임베딩이 없거나 옛 내용이면 None(만들기를 예약한다)."""
    if not pages or not enabled():
        return None
    wanted = {p["page_no"]: page_hash(p["body"]) for p in pages}
    found: dict[int, list] = {}
    for r in db.execute("SELECT page_no,start,page_hash,vector FROM page_vectors WHERE study_id=? AND model=?",
                        (study_id, model())):
        if wanted.get(r["page_no"]) == r["page_hash"]:
            found.setdefault(r["page_no"], []).append((r["start"], _unpack(r["vector"])))
    if any(n not in found and p["body"].strip() for n, p in ((p["page_no"], p) for p in pages)):
        schedule(study_id)
        return None
    return found


def similarity(a: array, b: array) -> float:
    return sum(x * y for x, y in zip(a, b))

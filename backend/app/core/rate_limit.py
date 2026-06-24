from __future__ import annotations

import hashlib
from dataclasses import dataclass
from threading import Lock
from time import monotonic


@dataclass
class _Bucket:
    starts_at: float
    count: int


_lock = Lock()
_buckets: dict[str, _Bucket] = {}


def _bucket_key(scope: str, parts: list[str]) -> str:
    raw = "\x1f".join([scope, *parts]).encode("utf-8", errors="ignore")
    return f"{scope}:{hashlib.sha256(raw).hexdigest()}"


def check_rate_limit(
    scope: str,
    parts: list[str],
    *,
    max_attempts: int,
    window_seconds: int,
) -> tuple[bool, int]:
    """Return (allowed, retry_after_seconds) for a small per-process limiter."""
    now = monotonic()
    key = _bucket_key(scope, parts)

    with _lock:
        bucket = _buckets.get(key)
        if bucket is None or now - bucket.starts_at >= window_seconds:
            _buckets[key] = _Bucket(starts_at=now, count=1)
            _cleanup(now, window_seconds)
            return True, 0

        bucket.count += 1
        retry_after = max(1, int(window_seconds - (now - bucket.starts_at)))
        return bucket.count <= max_attempts, retry_after


def _cleanup(now: float, window_seconds: int) -> None:
    if len(_buckets) < 5000:
        return
    expired = [
        key for key, bucket in _buckets.items() if now - bucket.starts_at >= window_seconds
    ]
    for key in expired:
        _buckets.pop(key, None)

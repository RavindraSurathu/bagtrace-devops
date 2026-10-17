"""Storage layer: MySQL in every environment, in-memory for tests and quick demos."""

from __future__ import annotations

import os
import threading
import time
from datetime import datetime, timezone

STATUSES = ("CHECKED_IN", "SCREENED", "LOADED", "OFFLOADED", "ARRIVED", "DELETED")


def _per_bag_weight(msg) -> int | None:
    """A BSM .W element carries the total weight for all pieces; store it per bag."""
    if not msg.weight_kg or not msg.tags:
        return None
    return round(msg.weight_kg / len(msg.tags))


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")


class MemoryStore:
    def __init__(self) -> None:
        self._bags: dict[str, dict] = {}
        self._events: list[dict] = []
        self._lock = threading.Lock()

    def ping(self) -> bool:
        return True

    def apply_message(self, msg) -> list[dict]:
        with self._lock:
            out = []
            for tag in msg.tags:
                if msg.action == "DEL":
                    bag = self._bags.get(tag)
                    if bag:
                        bag.update(status="DELETED", updated_at=_now())
                        out.append(dict(bag))
                else:
                    bag = {
                        "tag": tag,
                        "flight": msg.flight,
                        "flight_date": msg.flight_date,
                        "origin": msg.airport,
                        "destination": msg.destination,
                        "passenger": msg.passenger,
                        "weight_kg": _per_bag_weight(msg),
                        "status": "CHECKED_IN",
                        "updated_at": _now(),
                    }
                    if tag in self._bags and msg.action == "CHG":
                        bag["status"] = self._bags[tag]["status"]
                    self._bags[tag] = bag
                    out.append(dict(bag))
                self._events.append({"tag": tag, "event": f"BSM_{msg.action}", "created_at": _now()})
            return out

    def list_bags(self, flight: str | None = None, limit: int = 200) -> list[dict]:
        bags = [b for b in self._bags.values() if not flight or b["flight"] == flight]
        return sorted(bags, key=lambda b: b["updated_at"], reverse=True)[:limit]

    def get_bag(self, tag: str) -> dict | None:
        bag = self._bags.get(tag)
        if not bag:
            return None
        events = [e for e in self._events if e["tag"] == tag]
        return {**bag, "events": events}

    def set_status(self, tag: str, status: str) -> dict | None:
        with self._lock:
            bag = self._bags.get(tag)
            if not bag:
                return None
            bag.update(status=status, updated_at=_now())
            self._events.append({"tag": tag, "event": status, "created_at": _now()})
            return dict(bag)

    def stats(self) -> dict:
        counts = {s: 0 for s in STATUSES}
        for bag in self._bags.values():
            counts[bag["status"]] += 1
        flights = len({b["flight"] for b in self._bags.values()})
        return {"total": len(self._bags), "flights": flights, "by_status": counts}


class MySQLStore:
    def __init__(self) -> None:
        import pymysql  # imported here so tests do not need the driver

        self._pymysql = pymysql
        self._cfg = dict(
            host=os.getenv("DB_HOST", "localhost"),
            port=int(os.getenv("DB_PORT", "3306")),
            user=os.getenv("DB_USER", "bagtrace"),
            password=os.getenv("DB_PASSWORD", ""),
            database=os.getenv("DB_NAME", "bagtrace"),
            cursorclass=pymysql.cursors.DictCursor,
            autocommit=True,
            connect_timeout=5,
        )

    def _conn(self, retries: int = 5):
        delay = 1
        for attempt in range(retries):
            try:
                return self._pymysql.connect(**self._cfg)
            except self._pymysql.err.OperationalError:
                if attempt == retries - 1:
                    raise
                time.sleep(delay)
                delay = min(delay * 2, 8)

    def ping(self) -> bool:
        try:
            with self._conn(retries=1) as conn, conn.cursor() as cur:
                cur.execute("SELECT 1")
            return True
        except Exception:
            return False

    def apply_message(self, msg) -> list[dict]:
        with self._conn() as conn, conn.cursor() as cur:
            for tag in msg.tags:
                if msg.action == "DEL":
                    cur.execute("UPDATE bags SET status='DELETED' WHERE tag=%s", (tag,))
                else:
                    cur.execute(
                        """INSERT INTO bags (tag, flight, flight_date, origin, destination, passenger, weight_kg, status)
                           VALUES (%s,%s,%s,%s,%s,%s,%s,'CHECKED_IN')
                           ON DUPLICATE KEY UPDATE flight=VALUES(flight), flight_date=VALUES(flight_date),
                             origin=VALUES(origin), destination=VALUES(destination),
                             passenger=VALUES(passenger), weight_kg=VALUES(weight_kg)""",
                        (tag, msg.flight, msg.flight_date, msg.airport, msg.destination, msg.passenger, _per_bag_weight(msg)),
                    )
                cur.execute("INSERT INTO bag_events (tag, event) VALUES (%s,%s)", (tag, f"BSM_{msg.action}"))
            if not msg.tags:
                return []
            marks = ",".join(["%s"] * len(msg.tags))
            cur.execute(f"SELECT * FROM bags WHERE tag IN ({marks})", msg.tags)
            return [self._row(r) for r in cur.fetchall()]

    def list_bags(self, flight: str | None = None, limit: int = 200) -> list[dict]:
        with self._conn() as conn, conn.cursor() as cur:
            if flight:
                cur.execute("SELECT * FROM bags WHERE flight=%s ORDER BY updated_at DESC LIMIT %s", (flight, limit))
            else:
                cur.execute("SELECT * FROM bags ORDER BY updated_at DESC LIMIT %s", (limit,))
            return [self._row(r) for r in cur.fetchall()]

    def get_bag(self, tag: str) -> dict | None:
        with self._conn() as conn, conn.cursor() as cur:
            cur.execute("SELECT * FROM bags WHERE tag=%s", (tag,))
            row = cur.fetchone()
            if not row:
                return None
            cur.execute("SELECT tag, event, created_at FROM bag_events WHERE tag=%s ORDER BY id", (tag,))
            events = [self._row(e) for e in cur.fetchall()]
            return {**self._row(row), "events": events}

    def set_status(self, tag: str, status: str) -> dict | None:
        with self._conn() as conn, conn.cursor() as cur:
            cur.execute("UPDATE bags SET status=%s WHERE tag=%s", (status, tag))
            if cur.rowcount == 0:
                cur.execute("SELECT 1 FROM bags WHERE tag=%s", (tag,))
                if not cur.fetchone():
                    return None
            cur.execute("INSERT INTO bag_events (tag, event) VALUES (%s,%s)", (tag, status))
            cur.execute("SELECT * FROM bags WHERE tag=%s", (tag,))
            return self._row(cur.fetchone())

    def stats(self) -> dict:
        with self._conn() as conn, conn.cursor() as cur:
            cur.execute("SELECT status, COUNT(*) AS n FROM bags GROUP BY status")
            counts = {s: 0 for s in STATUSES}
            for row in cur.fetchall():
                counts[row["status"]] = row["n"]
            cur.execute("SELECT COUNT(DISTINCT flight) AS f FROM bags")
            flights = cur.fetchone()["f"]
            return {"total": sum(counts.values()), "flights": flights, "by_status": counts}

    @staticmethod
    def _row(row: dict) -> dict:
        return {k: (v.strftime("%Y-%m-%d %H:%M:%S") if isinstance(v, datetime) else v) for k, v in row.items()}


def make_store():
    if os.getenv("STORAGE", "mysql").lower() == "memory":
        return MemoryStore()
    return MySQLStore()

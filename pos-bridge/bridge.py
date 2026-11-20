#!/usr/bin/env python3
"""Saree POS Local Bridge MVP. Python 3.11+, Windows-friendly, stdlib only."""
from __future__ import annotations
import json
import logging
import os
import sqlite3
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

BASE_URL = os.environ["SAREE_BRIDGE_URL"].rstrip("/")
TOKEN = os.environ["SAREE_BRIDGE_TOKEN"]
RESTAURANT_ID = os.environ["SAREE_RESTAURANT_ID"]
POLL_SECONDS = int(os.getenv("SAREE_POLL_SECONDS", "5"))
STATE_DB = Path(os.getenv("SAREE_BRIDGE_DB", "saree_bridge.sqlite3"))
LOG_LEVEL = os.getenv("SAREE_LOG_LEVEL", "INFO").upper()

logging.basicConfig(level=LOG_LEVEL, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("saree-pos-bridge")


def db():
    conn = sqlite3.connect(STATE_DB)
    conn.execute("""CREATE TABLE IF NOT EXISTS processed_events (
        event_id TEXT PRIMARY KEY,
        processed_at TEXT NOT NULL,
        result TEXT NOT NULL
    )""")
    conn.commit()
    return conn


def request_json(path: str, payload=None):
    data = None if payload is None else json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = Request(
        BASE_URL + path,
        data=data,
        method="GET" if payload is None else "POST",
        headers={
            "Authorization": "Bearer " + TOKEN,
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    with urlopen(req, timeout=25) as response:
        raw = response.read()
        return json.loads(raw.decode("utf-8")) if raw else {}


def print_kitchen_ticket(event: dict):
    """Replace this with a vendor-supported local POS API or tested ESC/POS driver."""
    order = event["order"]
    lines = [
        "===== SAREE / KITCHEN =====",
        f"ORDER: {order.get('number', order.get('id'))}",
        f"TIME: {event.get('occurred_at', '')}",
        f"CUSTOMER: {order.get('customer', {}).get('name', '')}",
        "---------------------------",
    ]
    for item in order.get("items", []):
        lines.append(f"{item.get('quantity', 1)} x {item.get('name', '')}")
        if item.get("notes"):
            lines.append("  NOTE: " + str(item["notes"]))
    lines += [
        "---------------------------",
        f"TOTAL: {order.get('totals', {}).get('grand_total', 0)} YER",
        f"ADDRESS: {order.get('delivery', {}).get('address', '')}",
        "===========================",
    ]
    # Safe MVP output. No direct database writes and no claim that POS accepted it.
    print("\n".join(lines), flush=True)


def acknowledge(job_id: str, status: str, event_id: str, error=None):
    body = {
        "event_id": event_id,
        "status": status,
        "processed_at": datetime.now(timezone.utc).isoformat(),
        "error": error,
    }
    return request_json(f"/pos/v1/bridge/jobs/{job_id}/ack", body)


def process_job(conn, job: dict):
    event = job["payload"]
    event_id = str(event["event_id"])
    seen = conn.execute(
        "SELECT 1 FROM processed_events WHERE event_id=?", (event_id,)
    ).fetchone()
    if seen:
        acknowledge(job["id"], "printed", event_id, "duplicate delivery; already processed locally")
        return

    print_kitchen_ticket(event)
    conn.execute(
        "INSERT INTO processed_events(event_id, processed_at, result) VALUES (?, ?, ?)",
        (event_id, datetime.now(timezone.utc).isoformat(), "ticket_output"),
    )
    conn.commit()
    acknowledge(job["id"], "printed", event_id)


def main():
    if not TOKEN or not RESTAURANT_ID:
        raise SystemExit("Missing SAREE_BRIDGE_TOKEN or SAREE_RESTAURANT_ID")
    conn = db()
    log.info("Saree POS Bridge started for restaurant %s", RESTAURANT_ID)
    while True:
        try:
            result = request_json(
                f"/pos/v1/bridge/jobs?restaurant_id={RESTAURANT_ID}&limit=10"
            )
            for job in result.get("jobs", []):
                try:
                    process_job(conn, job)
                except Exception as exc:
                    log.exception("Job failed: %s", job.get("id"))
                    try:
                        acknowledge(job["id"], "failed", job.get("payload", {}).get("event_id", ""), str(exc))
                    except Exception:
                        log.exception("Could not acknowledge failed job")
        except (HTTPError, URLError, TimeoutError, ValueError) as exc:
            log.warning("Bridge offline or API unavailable; will retry: %s", exc)
        except Exception:
            log.exception("Unexpected bridge error")
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()

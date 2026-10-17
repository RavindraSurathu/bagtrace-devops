"""BagTrace API: ingests baggage source messages and tracks bags by tag and flight."""

from __future__ import annotations

import logging
import os
import time

from flask import Flask, Response, g, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

from bsm import BSMError, parse_bsm
from storage import STATUSES, make_store

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("bagtrace")

REQUESTS = Counter("bagtrace_http_requests_total", "HTTP requests", ["method", "endpoint", "status"])
LATENCY = Histogram("bagtrace_http_request_seconds", "Request latency", ["endpoint"])
MESSAGES = Counter("bagtrace_bsm_messages_total", "Baggage messages processed", ["action", "result"])


def create_app(store=None) -> Flask:
    app = Flask(__name__)
    app.config["STORE"] = store or make_store()

    def db():
        return app.config["STORE"]

    @app.before_request
    def _start_timer():
        g.start = time.perf_counter()

    @app.after_request
    def _record(resp):
        endpoint = request.url_rule.rule if request.url_rule else "unmatched"
        REQUESTS.labels(request.method, endpoint, resp.status_code).inc()
        LATENCY.labels(endpoint).observe(time.perf_counter() - g.get("start", time.perf_counter()))
        return resp

    @app.get("/health")
    def health():
        ok = db().ping()
        return jsonify(status="ok" if ok else "degraded", database="up" if ok else "down"), (200 if ok else 503)

    @app.get("/health/live")
    def live():
        return jsonify(status="ok")

    @app.get("/metrics")
    def metrics():
        return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

    @app.post("/api/bsm")
    def ingest_bsm():
        payload = request.get_json(silent=True)
        text = payload.get("message") if isinstance(payload, dict) else request.get_data(as_text=True)
        try:
            msg = parse_bsm(text)
        except BSMError as exc:
            MESSAGES.labels("unknown", "rejected").inc()
            return jsonify(error=str(exc)), 400
        bags = db().apply_message(msg)
        MESSAGES.labels(msg.action, "accepted").inc()
        log.info("BSM %s flight=%s tags=%s", msg.action, msg.flight, ",".join(msg.tags))
        return jsonify(message=msg.to_dict(), bags=bags), 201

    @app.get("/api/bags")
    def list_bags():
        flight = (request.args.get("flight") or "").upper() or None
        return jsonify(bags=db().list_bags(flight=flight))

    @app.get("/api/bags/<tag>")
    def get_bag(tag: str):
        bag = db().get_bag(tag)
        if not bag:
            return jsonify(error=f"No bag with tag {tag}"), 404
        return jsonify(bag)

    @app.patch("/api/bags/<tag>")
    def update_bag(tag: str):
        status = ((request.get_json(silent=True) or {}).get("status") or "").upper()
        if status not in STATUSES:
            return jsonify(error=f"Status must be one of: {', '.join(STATUSES)}"), 400
        bag = db().set_status(tag, status)
        if not bag:
            return jsonify(error=f"No bag with tag {tag}"), 404
        return jsonify(bag)

    @app.get("/api/stats")
    def stats():
        return jsonify(db().stats())

    return app


if __name__ == "__main__":
    create_app().run(host="0.0.0.0", port=int(os.getenv("PORT", "8080")))

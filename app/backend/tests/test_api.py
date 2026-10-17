import pytest

from app import create_app
from storage import MemoryStore

BSM = """BSM
.V/1LHYD
.F/AI101/18OCT/DXB/Y
.N/0098765432001
.W/K/1/22
.P/1RAO/PRIYA
ENDBSM"""


@pytest.fixture()
def client():
    return create_app(MemoryStore()).test_client()


def test_health_reports_database(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["database"] == "up"


def test_ingest_then_lookup(client):
    resp = client.post("/api/bsm", data=BSM, content_type="text/plain")
    assert resp.status_code == 201
    assert resp.get_json()["bags"][0]["status"] == "CHECKED_IN"

    bag = client.get("/api/bags/0098765432").get_json()
    assert bag["flight"] == "AI101"
    assert bag["events"][0]["event"] == "BSM_ADD"


def test_total_weight_is_split_across_bags(client):
    two_bags = BSM.replace("0098765432001", "0098765432002").replace(".W/K/1/22", ".W/K/2/40")
    bags = client.post("/api/bsm", data=two_bags).get_json()["bags"]
    assert [b["weight_kg"] for b in bags] == [20, 20]


def test_json_body_is_accepted(client):
    resp = client.post("/api/bsm", json={"message": BSM})
    assert resp.status_code == 201


def test_filter_by_flight(client):
    client.post("/api/bsm", data=BSM)
    assert len(client.get("/api/bags?flight=ai101").get_json()["bags"]) == 1
    assert client.get("/api/bags?flight=QF1").get_json()["bags"] == []


def test_status_update_and_validation(client):
    client.post("/api/bsm", data=BSM)
    assert client.patch("/api/bags/0098765432", json={"status": "loaded"}).get_json()["status"] == "LOADED"
    assert client.patch("/api/bags/0098765432", json={"status": "LOST"}).status_code == 400
    assert client.patch("/api/bags/0000000000", json={"status": "LOADED"}).status_code == 404


def test_delbsm_marks_bag_deleted(client):
    client.post("/api/bsm", data=BSM)
    client.post("/api/bsm", data=BSM.replace("BSM\n", "BSM\nDEL\n", 1))
    assert client.get("/api/bags/0098765432").get_json()["status"] == "DELETED"
    assert client.get("/api/stats").get_json()["by_status"]["DELETED"] == 1


def test_bad_message_returns_400(client):
    resp = client.post("/api/bsm", data="not a bsm")
    assert resp.status_code == 400
    assert "BSM" in resp.get_json()["error"]


def test_metrics_endpoint(client):
    client.get("/health")
    assert b"bagtrace_http_requests_total" in client.get("/metrics").data

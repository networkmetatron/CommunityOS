#!/usr/bin/env python3
"""Minimal Maps download API for CommunityOS (Maps app only)."""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

DATA = Path(os.environ.get("MAPS_DATA", "/data"))
PMTILES = os.environ.get("PMTILES_BIN", "/usr/local/bin/pmtiles")
def _load_source_url() -> str:
    # Precedence: env → mounted/packaged config → last-resort pin
    env = (os.environ.get("PMTILES_SOURCE_URL") or "").strip()
    if env:
        return env
    for candidate in (
        Path("/config/maps-source.env"),
        Path("/opt/communityos/config/maps-source.env"),
        Path(__file__).resolve().parent.parent / "config" / "maps-source.env",
    ):
        try:
            if candidate.is_file():
                for line in candidate.read_text().splitlines():
                    line = line.strip()
                    if line.startswith("PMTILES_SOURCE_URL="):
                        val = line.split("=", 1)[1].strip()
                        if val.startswith("'") and val.endswith("'"):
                            val = val[1:-1]
                        if val.startswith('"') and val.endswith('"'):
                            val = val[1:-1]
                        if val:
                            return val
        except Exception:
            pass
    # Last-resort pin (prefer updating config/maps-source.env)
    return "https://build.protomaps.com/20260807.pmtiles"


SOURCE = _load_source_url()
MARTIN = os.environ.get("MARTIN_CONTAINER", "communityos-martin")
HOST = os.environ.get("MAPS_API_HOST", "0.0.0.0")
PORT = int(os.environ.get("MAPS_API_PORT", "8099"))

JOBS: dict[str, dict] = {}
LOCK = threading.Lock()

PRESETS = [
    {
        "id": "los-angeles",
        "name": "Los Angeles",
        "bbox": [-118.95, 33.55, -117.55, 34.85],
        "maxzoom": 14,
    },
    {
        "id": "california",
        "name": "California",
        "bbox": [-124.5, 32.5, -114.1, 42.1],
        "maxzoom": 12,
    },
    {
        "id": "united-states",
        "name": "United States (lower 48)",
        "bbox": [-125.0, 24.0, -66.5, 49.5],
        "maxzoom": 10,
    },
    {
        "id": "new-york",
        "name": "New York City",
        "bbox": [-74.3, 40.45, -73.65, 41.0],
        "maxzoom": 14,
    },
]


def safe_name(name: str) -> str:
    name = (name or "map").strip().lower()
    name = re.sub(r"[^a-z0-9._-]+", "-", name)
    name = re.sub(r"-+", "-", name).strip("-")
    return name[:64] or "map"


def estimate_mb(bbox: list[float], maxzoom: int) -> float:
    """Rough heuristic for planning — not exact."""
    min_lon, min_lat, max_lon, max_lat = bbox
    # degrees² → crude area factor
    area = max(0.01, abs(max_lon - min_lon) * abs(max_lat - min_lat))
    # zoom growth is aggressive; tuned near ~88MB for LA @ z14
    zoom_factor = 2 ** max(0, maxzoom - 8)
    return round(max(1.0, area * 0.35 * zoom_factor), 1)


def list_datasets() -> list[dict]:
    DATA.mkdir(parents=True, exist_ok=True)
    out = []
    for p in sorted(DATA.glob("*.pmtiles")) + sorted(DATA.glob("*.mbtiles")):
        out.append(
            {
                "name": p.stem,
                "file": p.name,
                "size_mb": round(p.stat().st_size / (1024 * 1024), 1),
            }
        )
    return out


def restart_martin() -> bool:
    """Restart Martin via Docker Engine API (no docker CLI required)."""
    import http.client
    import socket

    class DockerSock(http.client.HTTPConnection):
        def connect(self):
            self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.sock.connect("/var/run/docker.sock")

    try:
        conn = DockerSock("localhost")
        conn.request("POST", f"/containers/{MARTIN}/restart?t=30")
        resp = conn.getresponse()
        ok = resp.status in (204, 200, 304)
        resp.read()
        conn.close()
        return ok
    except Exception:
        return False


def run_job(job_id: str, name: str, bbox: list[float], maxzoom: int, source: str) -> None:
    dest = DATA / f"{name}.pmtiles"
    partial = DATA / f".{name}.pmtiles.partial"
    with LOCK:
        JOBS[job_id].update(status="running", progress=5, message="Starting extract…")
    try:
        DATA.mkdir(parents=True, exist_ok=True)
        if not Path(PMTILES).exists():
            raise RuntimeError(f"pmtiles CLI not found at {PMTILES}")
        bbox_s = ",".join(str(x) for x in bbox)
        cmd = [
            PMTILES,
            "extract",
            source,
            str(partial),
            f"--bbox={bbox_s}",
            f"--maxzoom={int(maxzoom)}",
        ]
        with LOCK:
            JOBS[job_id].update(progress=15, message="Downloading / extracting tiles (internet required)…")
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=3600 * 6)
        if proc.returncode != 0:
            err = (proc.stderr or proc.stdout or "extract failed").strip()
            raise RuntimeError(err[:500])
        with LOCK:
            JOBS[job_id].update(progress=80, message="Verifying archive…")
        verify = subprocess.run(
            [PMTILES, "verify", str(partial)],
            capture_output=True,
            text=True,
            timeout=300,
        )
        if verify.returncode != 0:
            raise RuntimeError((verify.stderr or verify.stdout or "verify failed").strip()[:500])
        partial.replace(dest)
        with LOCK:
            JOBS[job_id].update(progress=90, message="Refreshing tile server…")
        restarted = restart_martin()
        with LOCK:
            JOBS[job_id].update(
                status="done",
                progress=100,
                message="Dataset ready" + ("" if restarted else " — run: sudo communityos app restart maps"),
                file=dest.name,
                martin_restarted=restarted,
            )
    except Exception as e:
        try:
            if partial.exists():
                partial.unlink()
        except Exception:
            pass
        with LOCK:
            JOBS[job_id].update(status="error", progress=100, message=str(e))


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        return

    def _json(self, code: int, obj: dict | list) -> None:
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:
        self._json(204, {})

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path in ("/health", "/maps-api/health"):
            self._json(200, {"ok": True})
            return
        if path in ("/presets", "/maps-api/presets"):
            presets = []
            for p in PRESETS:
                presets.append(
                    {
                        **p,
                        "estimated_mb": estimate_mb(p["bbox"], p["maxzoom"]),
                    }
                )
            self._json(200, {"presets": presets, "source_default": SOURCE})
            return
        if path in ("/datasets", "/maps-api/datasets"):
            self._json(200, {"datasets": list_datasets()})
            return
        if path.startswith("/jobs/") or path.startswith("/maps-api/jobs/"):
            job_id = path.rstrip("/").split("/")[-1]
            with LOCK:
                job = JOBS.get(job_id)
            if not job:
                self._json(404, {"error": "job not found"})
                return
            self._json(200, job)
            return
        self._json(404, {"error": "not found"})

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if path not in ("/download", "/maps-api/download"):
            self._json(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            data = json.loads(raw.decode() or "{}")
        except json.JSONDecodeError:
            self._json(400, {"error": "invalid JSON"})
            return

        name = safe_name(str(data.get("name") or data.get("id") or "map"))
        bbox = data.get("bbox")
        maxzoom = int(data.get("maxzoom") or 14)
        source = str(data.get("source") or SOURCE).strip()

        if not isinstance(bbox, list) or len(bbox) != 4:
            self._json(400, {"error": "bbox must be [minLon,minLat,maxLon,maxLat]"})
            return
        try:
            bbox = [float(x) for x in bbox]
        except (TypeError, ValueError):
            self._json(400, {"error": "bbox values must be numbers"})
            return
        if maxzoom < 0 or maxzoom > 18:
            self._json(400, {"error": "maxzoom must be 0–18"})
            return
        if (DATA / f"{name}.pmtiles").exists() and not data.get("overwrite"):
            self._json(409, {"error": f"dataset '{name}' already exists", "hint": "choose another name or set overwrite"})
            return
        # Guardrail: refuse enormous world-like downloads by default
        area = abs(bbox[2] - bbox[0]) * abs(bbox[3] - bbox[1])
        if area > 4000 and maxzoom > 8 and not data.get("confirm_large"):
            self._json(
                400,
                {
                    "error": "region/zoom looks very large",
                    "estimated_mb": estimate_mb(bbox, maxzoom),
                    "hint": "lower maxzoom or set confirm_large=true",
                },
            )
            return

        job_id = uuid.uuid4().hex[:12]
        with LOCK:
            JOBS[job_id] = {
                "id": job_id,
                "name": name,
                "bbox": bbox,
                "maxzoom": maxzoom,
                "estimated_mb": estimate_mb(bbox, maxzoom),
                "status": "queued",
                "progress": 0,
                "message": "Queued",
            }
        threading.Thread(
            target=run_job, args=(job_id, name, bbox, maxzoom, source), daemon=True
        ).start()
        self._json(202, {"job_id": job_id, **JOBS[job_id]})


def main() -> None:
    DATA.mkdir(parents=True, exist_ok=True)
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"maps-api listening on {HOST}:{PORT}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()

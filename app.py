"""
Tiny Flask hello-world app used to exercise the jenkins-shared-lib pipeline.
Listens on 0.0.0.0:8080 (matching the Dockerfile and the Helm chart values).
"""

from __future__ import annotations

import os
import socket

from flask import Flask, jsonify

app = Flask(__name__)

APP_NAME = os.environ.get("APP_NAME", "flask-app-jenkins")
APP_VERSION = os.environ.get("APP_VERSION", "0.1.0")


@app.get("/")
def index():
    return jsonify(
        message="Hello, World!",
        app=APP_NAME,
        version=APP_VERSION,
        host=socket.gethostname(),
    )


@app.get("/healthz")
def healthz():
    return jsonify(status="ok"), 200


@app.get("/readyz")
def readyz():
    return jsonify(status="ready"), 200


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    app.run(host="0.0.0.0", port=port)

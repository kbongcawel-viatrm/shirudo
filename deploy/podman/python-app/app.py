# SPDX-License-Identifier: BSD-2-Clause
"""Minimal Python workload used to exercise the vulnerability workflow."""
from flask import Flask, jsonify

app = Flask(__name__)

@app.get("/")
def index():
    return jsonify(service="shirudo-python-demo", status="ok")

@app.get("/healthz")
def healthz():
    return jsonify(status="healthy")

if __name__ == "__main__":
    # Production deployment should use a production WSGI server.
    app.run(host="0.0.0.0", port=8080)

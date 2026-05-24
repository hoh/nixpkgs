import json
import socket
import time
import urllib.error
import urllib.request
from pathlib import Path


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def read_json(port, path, timeout=90, headers=None):
    url = f"http://127.0.0.1:{port}{path}"
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            request = urllib.request.Request(url, headers=headers or {})
            with urllib.request.urlopen(request, timeout=5) as response:
                return json.loads(response.read())
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            last_error = error
            time.sleep(1)
    raise AssertionError(f"{url} did not become ready: {last_error}")


def post_json(port, path, payload, headers=None):
    request_headers = {"Content-Type": "application/json"}
    request_headers.update(headers or {})
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}{path}",
        data=json.dumps(payload).encode(),
        headers=request_headers,
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=5) as response:
        return json.loads(response.read())


def auth_headers(port):
    password_path = (
        Path.home() / ".unsloth" / "studio" / "auth" / ".bootstrap_password"
    )
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if password_path.is_file():
            password = password_path.read_text().strip()
            break
        time.sleep(1)
    else:
        raise AssertionError(f"missing bootstrap password at {password_path}")

    token = post_json(
        port,
        "/api/auth/login",
        {"username": "unsloth", "password": password},
    )
    headers = {"Authorization": f"Bearer {token['access_token']}"}
    if token.get("must_change_password"):
        token = post_json(
            port,
            "/api/auth/change-password",
            {
                "current_password": password,
                "new_password": "nixpkgs-test-password",
            },
            headers=headers,
        )
        headers = {"Authorization": f"Bearer {token['access_token']}"}
    return headers


def read_authenticated_system(port):
    return read_json(port, "/api/system", headers=auth_headers(port))

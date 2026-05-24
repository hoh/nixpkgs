{
  lib,
  cudaPackages,
  gcc,
  llama-cpp,
  python,
  runCommand,
  unsloth-cli,
  unsloth-zoo,
  writableTmpDirAsHomeHook,
}:

let
  basePythonPackages = python.pkgs;
  gpuPython =
    let
      self = python.override {
        packageOverrides = final: prev: {
          torch = basePythonPackages.torchWithCuda;
          triton = basePythonPackages.triton-cuda;
        };
        inherit self;
      };
    in
    self;
in
{
  smoke = runCommand "unsloth-cli-smoke" { nativeBuildInputs = [ unsloth-cli ]; } ''
    unsloth --help > /dev/null
    unsloth studio --help > /dev/null
    touch $out
  '';

  llama-server-runtime =
    runCommand "unsloth-cli-llama-server-runtime" { nativeBuildInputs = [ unsloth-cli ]; }
      ''
        llama_server=${lib.escapeShellArg (lib.getExe' llama-cpp "llama-server")}

        test -x "$llama_server"
        grep -F "$llama_server" ${lib.escapeShellArg "${unsloth-cli}/bin/unsloth"} > /dev/null

        mkdir sitecustomize
        cat > sitecustomize/sitecustomize.py <<'PY'
        import os
        from pathlib import Path

        Path(os.environ["UNSLOTH_ENV_CAPTURE"]).write_text(
            os.environ.get("LLAMA_SERVER_PATH", "") + "\n" + os.environ.get("PATH", "")
        )
        PY

        export UNSLOTH_ENV_CAPTURE="$PWD/env"
        PYTHONPATH="$PWD/sitecustomize" unsloth --help > /dev/null

        test "$(head -n 1 "$UNSLOTH_ENV_CAPTURE")" = "$llama_server"
        grep -F "$(dirname "$llama_server")" "$UNSLOTH_ENV_CAPTURE" > /dev/null

        touch $out
      '';

  signal-cleanup =
    runCommand "unsloth-cli-signal-cleanup"
      {
        nativeBuildInputs = [
          python
          unsloth-cli
          writableTmpDirAsHomeHook
        ];
      }
      ''
        python - <<'PY'
        import json
        import os
        import signal
        import socket
        import subprocess
        import time
        import urllib.error
        import urllib.request
        from pathlib import Path

        def free_port():
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.bind(("127.0.0.1", 0))
                return sock.getsockname()[1]

        def wait_for_health(port, timeout=90):
            url = f"http://127.0.0.1:{port}/api/health"
            deadline = time.monotonic() + timeout
            last_error = None
            while time.monotonic() < deadline:
                try:
                    with urllib.request.urlopen(url, timeout=5) as response:
                        return json.loads(response.read())
                except (urllib.error.URLError, TimeoutError, OSError) as error:
                    last_error = error
                    time.sleep(1)
            raise AssertionError(f"{url} did not become ready: {last_error}")

        port = free_port()
        pid_file = Path.home() / ".unsloth" / "studio" / "studio.pid"
        process = subprocess.Popen(
            [
                "unsloth",
                "studio",
                "--host",
                "127.0.0.1",
                "--port",
                str(port),
                "--silent",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        try:
            health = wait_for_health(port)
            assert health["status"] == "healthy", health

            deadline = time.monotonic() + 30
            while not pid_file.is_file() and time.monotonic() < deadline:
                time.sleep(0.5)
            assert pid_file.is_file(), f"missing PID file at {pid_file}"
            assert pid_file.read_text().strip() == str(process.pid)

            stop = subprocess.run(
                ["unsloth", "studio", "stop"],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=30,
            )
            assert stop.returncode == 0, stop.stdout
            process.wait(timeout=30)

            deadline = time.monotonic() + 10
            while pid_file.exists() and time.monotonic() < deadline:
                time.sleep(0.5)
            assert not pid_file.exists(), "SIGTERM handler did not remove PID file"
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=30)
            output = process.stdout.read() if process.stdout is not None else ""
            if process.returncode not in (0, -signal.SIGTERM, 128 + signal.SIGTERM, 143):
                raise AssertionError(
                    f"unsloth studio exited with {process.returncode}\n{output}"
                )
        PY

        touch $out
      '';

  cuda = {
    studio-server-via-cli =
      (
        # FIXME: Replace python3.pkgs with python3Packages once possible, as to unbreak splicing.
        # Cf. https://github.com/NixOS/nixpkgs/pull/394838#issuecomment-3319287038
        cudaPackages.writeGpuTestPython.override { python3Packages = gpuPython.pkgs; }
          {
            name = "unsloth-cli-studio-server-cuda";
            gpuCheckArgs.nativeBuildInputs = [ writableTmpDirAsHomeHook ];
            libraries = ps: [
              ps.unsloth-cli
              ps.unsloth-zoo
            ];
          }
          ''
            import json
            import os
            import signal
            import socket
            import subprocess
            import sys
            import time
            import urllib.error
            import urllib.request
            from pathlib import Path

            import torch

            assert torch.cuda.is_available(), "CUDA is not available"
            assert torch.ones(1, device="cuda").is_cuda

            os.environ["CC"] = "${lib.getExe' gcc "cc"}"
            os.environ["CXX"] = "${lib.getExe' gcc "cxx"}"
            os.environ["HF_HUB_OFFLINE"] = "1"
            os.environ["TRANSFORMERS_OFFLINE"] = "1"
            os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"

            def free_port():
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                    sock.bind(("127.0.0.1", 0))
                    return sock.getsockname()[1]

            def read_json(port, path, timeout=90):
                url = f"http://127.0.0.1:{port}{path}"
                deadline = time.monotonic() + timeout
                last_error = None
                while time.monotonic() < deadline:
                    try:
                        with urllib.request.urlopen(url, timeout=5) as response:
                            return json.loads(response.read())
                    except (urllib.error.URLError, TimeoutError, OSError) as error:
                        last_error = error
                        time.sleep(1)
                raise AssertionError(f"{url} did not become ready: {last_error}")

            port = free_port()
            unsloth = Path(sys.executable).with_name("unsloth")
            assert unsloth.is_file(), f"missing CLI executable at {unsloth}"

            process = subprocess.Popen(
                [
                    str(unsloth),
                    "studio",
                    "--host",
                    "127.0.0.1",
                    "--port",
                    str(port),
                    "--silent",
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            try:
                health = read_json(port, "/api/health")
                system = read_json(port, "/api/system")

                assert health["status"] == "healthy", health
                assert health["chat_only"] is False, health
                assert system["device_backend"] == "cuda", system
                assert system["gpu"]["available"] is True, system
                assert system["gpu"]["devices"], system
            finally:
                process.terminate()
                try:
                    process.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=30)

                output = process.stdout.read() if process.stdout is not None else ""
                if process.returncode not in (0, -signal.SIGTERM, 128 + signal.SIGTERM, 143):
                    raise AssertionError(
                        f"unsloth studio exited with {process.returncode}\n{output}"
                    )
          ''
      ).gpuCheck;
  };
}

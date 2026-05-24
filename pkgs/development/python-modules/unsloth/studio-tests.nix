{
  lib,
  cudaPackages,
  gcc,
  llama-cpp,
  python,
  runCommand,
  unsloth-studio,
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
  smoke = runCommand "unsloth-studio-smoke" { nativeBuildInputs = [ unsloth-studio ]; } ''
    unsloth-studio --help > /dev/null
    touch $out
  '';

  audio-base64-runtime =
    runCommand "unsloth-studio-audio-base64-runtime"
      {
        nativeBuildInputs = [
          python
          unsloth-studio
          writableTmpDirAsHomeHook
        ];
      }
      ''
        python - <<'PY'
        import base64
        import io
        import wave

        import studio.backend.run  # Adds studio/backend for upstream absolute imports.
        from routes.inference import _decode_audio_base64

        buffer = io.BytesIO()
        with wave.open(buffer, "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(16000)
            wav.writeframes(bytes(3200))

        audio = _decode_audio_base64(base64.b64encode(buffer.getvalue()).decode())

        assert audio.shape == (1600,), audio.shape
        PY

        touch $out
      '';

  unstructured-seed-runtime =
    runCommand "unsloth-studio-unstructured-seed-runtime"
      {
        nativeBuildInputs = [
          python
          unsloth-studio
          writableTmpDirAsHomeHook
        ];
      }
      ''
        python - <<'PY'
        from pathlib import Path

        import studio.backend.run  # Adds studio/backend for upstream absolute imports.
        import data_designer_unstructured_seed
        import mammoth
        import pymupdf4llm
        from data_designer.plugins.plugin import PluginType
        from data_designer.plugins.registry import PluginRegistry
        from routes.data_recipe.seed import _read_preview_rows_from_unstructured_file

        plugin_names = PluginRegistry().get_plugin_names(PluginType.SEED_READER)
        assert "unstructured" in plugin_names, plugin_names

        source = Path("seed.txt")
        source.write_text("First paragraph.\n\nSecond paragraph.", encoding = "utf-8")

        rows = _read_preview_rows_from_unstructured_file(
            path = source,
            preview_size = 2,
            chunk_size = 1200,
            chunk_overlap = 0,
        )

        assert rows == [{"chunk_text": "First paragraph.\n\nSecond paragraph."}], rows
        assert data_designer_unstructured_seed is not None
        assert mammoth is not None
        assert pymupdf4llm is not None
        PY

        touch $out
      '';

  data-recipe-runtime =
    runCommand "unsloth-studio-data-recipe-runtime"
      {
        nativeBuildInputs = [
          python
          unsloth-studio
          writableTmpDirAsHomeHook
        ];
      }
      ''
        export DISABLE_DATA_DESIGNER_PLUGINS=true
        python - <<'PY'
        import studio.backend.run  # Adds studio/backend for upstream absolute imports.
        from core.data_recipe.service import build_config_builder, validate_recipe
        from data_designer.config import DataDesignerConfigBuilder
        from data_designer.engine.validation import validate_data_designer_config

        recipe = {
            "columns": [
                {
                    "name": "test_id",
                    "column_type": "sampler",
                    "sampler_type": "uuid",
                    "params": {"prefix": "id_", "short_form": True},
                }
            ]
        }

        builder = build_config_builder(recipe)
        assert isinstance(builder, DataDesignerConfigBuilder)
        config = builder.build()
        assert config.columns[0].name == "test_id"
        validate_recipe(recipe)
        assert callable(validate_data_designer_config)
        PY

        touch $out
      '';

  transformers-runtime-no-install =
    runCommand "unsloth-studio-transformers-runtime-no-install"
      {
        nativeBuildInputs = [
          python
          unsloth-studio
          writableTmpDirAsHomeHook
        ];
      }
      ''
        python - <<'PY'
        import os
        import sys
        from pathlib import Path

        import studio.backend.run  # Adds studio/backend for upstream absolute imports.
        from utils import transformers_version as tv

        home = Path.home()
        tv.activate_transformers_for_subprocess("unsloth/gemma-4-E2B")
        tv.ensure_transformers_version("unsloth/gemma-4-E2B")

        assert not (home / ".unsloth" / "studio" / ".venv_t5_530").exists()
        assert not (home / ".unsloth" / "studio" / ".venv_t5_550").exists()
        assert not any(".venv_t5" in path for path in sys.path), sys.path
        assert ".venv_t5" not in os.environ.get("PYTHONPATH", "")

        try:
            tv._install_to_dir("transformers==5.5.0", str(home / "target"))
        except RuntimeError as exc:
            assert "packaged by Nix" in str(exc)
        else:
            raise AssertionError("_install_to_dir did not fail with the Nix message")

        assert not (home / "target").exists()
        PY

        touch $out
      '';

  llama-server-runtime =
    runCommand "unsloth-studio-llama-server-runtime" { nativeBuildInputs = [ unsloth-studio ]; }
      ''
        llama_server=${lib.escapeShellArg (lib.getExe' llama-cpp "llama-server")}

        test -x "$llama_server"
        grep -F "$llama_server" ${lib.escapeShellArg "${unsloth-studio}/bin/unsloth-studio"} > /dev/null

        mkdir sitecustomize
        cat > sitecustomize/sitecustomize.py <<'PY'
        import os
        from pathlib import Path

        Path(os.environ["UNSLOTH_ENV_CAPTURE"]).write_text(
            os.environ.get("LLAMA_SERVER_PATH", "") + "\n" + os.environ.get("PATH", "")
        )
        PY

        export UNSLOTH_ENV_CAPTURE="$PWD/env"
        PYTHONPATH="$PWD/sitecustomize" unsloth-studio --help > /dev/null

        test "$(head -n 1 "$UNSLOTH_ENV_CAPTURE")" = "$llama_server"
        grep -F "$(dirname "$llama_server")" "$UNSLOTH_ENV_CAPTURE" > /dev/null

        touch $out
      '';

  cuda = {
    studio-server =
      (
        # FIXME: Replace python3.pkgs with python3Packages once possible, as to unbreak splicing.
        # Cf. https://github.com/NixOS/nixpkgs/pull/394838#issuecomment-3319287038
        cudaPackages.writeGpuTestPython.override { python3Packages = gpuPython.pkgs; }
          {
            name = "unsloth-studio-server-cuda";
            gpuCheckArgs.nativeBuildInputs = [ writableTmpDirAsHomeHook ];
            libraries = ps: [
              ps.unsloth-studio
              ps.unsloth-zoo
            ];
          }
          ''
            import importlib.util
            import os

            import torch

            assert torch.cuda.is_available(), "CUDA is not available"
            assert torch.ones(1, device="cuda").is_cuda

            os.environ["CC"] = "${lib.getExe' gcc "cc"}"
            os.environ["CXX"] = "${lib.getExe' gcc "cxx"}"
            os.environ["HF_HUB_OFFLINE"] = "1"
            os.environ["TRANSFORMERS_OFFLINE"] = "1"
            os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
            # stdenv sets SSL_CERT_FILE to a fake path in builders. httpx
            # treats that as an explicit CA file and fails during import.
            os.environ.pop("SSL_CERT_FILE", None)

            support_spec = importlib.util.spec_from_file_location(
                "studio_server_test_support",
                "${./studio_server_test_support.py}",
            )
            support = importlib.util.module_from_spec(support_spec)
            assert support_spec.loader is not None
            support_spec.loader.exec_module(support)

            import studio.backend.run as studio_run

            port = support.free_port()
            studio_run.run_server(host="127.0.0.1", port=port, silent=True)
            try:
                health = support.read_json(port, "/api/health")
                system = support.read_authenticated_system(port)

                assert health["status"] == "healthy", health
                assert health["chat_only"] is False, health
                assert system["device_backend"] == "cuda", system
                assert system["gpu"]["available"] is True, system
                assert system["gpu"]["devices"], system
            finally:
                studio_run._graceful_shutdown(studio_run._server)
                if studio_run._shutdown_event is not None:
                    studio_run._shutdown_event.set()
          ''
      ).gpuCheck;
  };
}

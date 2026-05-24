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
        from pathlib import Path

        import studio.backend.run  # Adds studio/backend for upstream absolute imports.
        from utils import transformers_version as tv

        home = Path.home()
        tv.activate_transformers_for_subprocess("unsloth/gemma-4-E2B")
        tv.ensure_transformers_version("unsloth/gemma-4-E2B")

        assert not (home / ".unsloth" / "studio" / ".venv_t5_530").exists()
        assert not (home / ".unsloth" / "studio" / ".venv_t5_550").exists()

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

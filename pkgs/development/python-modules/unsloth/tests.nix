{
  lib,
  cudaPackages,
  fetchFromGitHub,
  fetchFromHuggingFace,
  gcc,
  python,
  runCommand,
  unsloth,
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

  qloraModel = fetchFromHuggingFace {
    repoId = "unsloth/Llama-3.2-1B-Instruct";
    rev = "5a8abab4a5d6f164389b1079fb721cfab8d7126c";
    hash = "sha256-LW6+gV1X5ogCFb8vQfhL++JqtnFHqZCmxWYEfyXiWiY=";
  };

  # Test files are absent from the PyPI package, so fetch the upstream tests at
  # a pinned revision and patch only the nixpkgs-specific incompatibilities.
  rawTestSrc = fetchFromGitHub {
    owner = "unslothai";
    repo = "unsloth";
    rev = "cb78f0e83dc2d61fb1571b6e904eb2f064510d63";
    hash = "sha256-0oR3m8jnjSdfjH+NslW6SsVj+0cQ4VUhKXZ38U/VBy0=";
    postFetch = ''
      mv $out/tests $TMPDIR/tests
      rm -rf $out/*
      mv $TMPDIR/tests $out/tests
    '';
  };

  testSrc = runCommand "unsloth-tests" { } ''
    cp -r ${rawTestSrc} "$out"
    chmod -R +w "$out"

    patch -d "$out" -p1 < ${./qlora-train-and-merge.patch}
    substituteInPlace "$out/tests/qlora/test_unsloth_qlora_train_and_merge.py" \
      --replace-fail "@@QLORA_MODEL@@" "${qloraModel}"
  '';
in
{
  core-license-split = runCommand "unsloth-core-license-split" { } ''
    site="${unsloth}/${python.sitePackages}"

    test -d "$site/unsloth"
    test ! -e "$site/unsloth_cli"
    test ! -e "$site/studio"
    test ! -e "$site/unsloth/kernels/moe"
    test ! -e "${unsloth}/bin/unsloth"
    test ! -e "${unsloth}/COPYING"

    touch $out
  '';

  cuda = {
    qlora-train-and-merge =
      (
        # FIXME: Replace python3.pkgs with python3Packages once possible, as to unbreak splicing.
        # Cf. https://github.com/NixOS/nixpkgs/pull/394838#issuecomment-3319287038
        cudaPackages.writeGpuTestPython.override { python3Packages = gpuPython.pkgs; }
          {
            # Triton and related runtime caches write into HOME. Builders use
            # /homeless-shelter by default, so provide a writable temporary HOME.
            gpuCheckArgs.nativeBuildInputs = [ writableTmpDirAsHomeHook ];
            libraries = ps: [
              ps.unsloth
              ps.unsloth-zoo
            ];
          }
          # Run the upstream QLoRA train-and-merge test from a pinned checkout.
          # Keep the upstream script as close to upstream as possible and patch
          # only the nixpkgs-specific incompatibilities: use a pinned public
          # model, switch to float16 to avoid a load-time OOM on this GPU path,
          # and patch the merged save so copies from the read-only Nix store are
          # made writable before Unsloth mutates them. Attempts to restore more
          # of the deleted upstream lines still fail on this NVIDIA path:
          # both the pre-training and post-training response checks hit the same
          # Unsloth fast-generation tensor-shape mismatch with this public
          # model, while merged-model reload still succeeds. The patch comments
          # explain those two remaining deletions inline.
          ''
            import os
            import runpy
            import sys

            import torch;

            assert torch.cuda.is_available(), "CUDA is not available"

            os.environ["CC"] = "${lib.getExe' gcc "cc"}"
            os.environ["CXX"] = "${lib.getExe' gcc "cxx"}"
            os.environ["HF_HUB_OFFLINE"] = "1"
            os.environ["TRANSFORMERS_OFFLINE"] = "1"

            sys.path.insert(0, "${testSrc}")

            # Unsloth resolved a direct local path more reliably than a seeded
            # Hugging Face cache in this offline test setup.
            runpy.run_path(
                "${testSrc}/tests/qlora/test_unsloth_qlora_train_and_merge.py",
                run_name="__main__",
            )
          ''
      ).gpuCheck;
  };
}

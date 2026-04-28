{
  lib,
  testers,
  fetchFromHuggingFace,
  fetchFromHuggingFaceGGUF,
  runWithHuggingFaceCache,
  runCommand,
  python3,
  ...
}:
let
  fetchTestRepository = testers.invalidateFetcherByDrvHash fetchFromHuggingFace;
  fetchTestGGUF = testers.invalidateFetcherByDrvHash fetchFromHuggingFaceGGUF;

  huggingFaceHubPython = python3.withPackages (ps: [
    ps.huggingface-hub
  ]);

  fakeRepository = runCommand "fetchFromHuggingFace-fake-repository" { } ''
    mkdir -p "$out"
    touch "$out/placeholder"
  '';

  fakeRepositoryWithMetadata = fakeRepository // {
    repoId = "kitten/not-a-cacheable-repository";
    rev = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef";
  };

  assertCacheEntry =
    {
      cacheDir,
      rev,
      source,
      ref ? "main",
    }:
    ''
      ref_relpath=${lib.escapeShellArg ref}
      snapshot_rev=${lib.escapeShellArg rev}
      test -d "$HF_HOME/hub/${cacheDir}"
      test "$(cat "$HF_HOME/hub/${cacheDir}/refs/$ref_relpath")" = "$snapshot_rev"
      test "$(readlink "$HF_HOME/hub/${cacheDir}/snapshots/$snapshot_rev")" = "${source}"
    '';

  failsDrv = source: if (builtins.tryEval source.drvPath).success then "0" else "1";
in
{
  metadata =
    let
      model = fetchFromHuggingFace {
        owner = "kitten";
        repo = "named-model";
        rev = "0123456789abcdef0123456789abcdef01234567";
        hash = lib.fakeHash;
      };
      dataset = fetchFromHuggingFace {
        repoId = "kitten/named-dataset";
        domain = "hf.example.test";
        repoType = "dataset";
        rev = "0123456789abcdef0123456789abcdef01234567";
        hash = lib.fakeHash;
        passthru.marker = "kept";
      };
      tagged = fetchFromHuggingFace {
        repoId = "kitten/tagged-model";
        tag = "v1.0";
        hash = lib.fakeHash;
      };
    in
    runCommand "fetchFromHuggingFace-metadata-test" { } ''
      test "${model.repoId}" = "kitten/named-model"
      test "${model.owner}" = "kitten"
      test "${model.repo}" = "named-model"
      test "${toString model.isHuggingFaceRepository}" = "1"
      test "${dataset.gitRepoUrl}" = "https://hf.example.test/datasets/kitten/named-dataset.git"
      test "${dataset.meta.homepage}" = "https://hf.example.test/datasets/kitten/named-dataset"
      test "${dataset.repoType}" = "dataset"
      test "${dataset.marker}" = "kept"
      test "${tagged.rev}" = "refs/tags/v1.0"
      test "${tagged.tag}" = "v1.0"
      touch "$out"
    '';

  argumentValidation = runCommand "fetchFromHuggingFace-argument-validation-test" { } ''
    test "${
      failsDrv (fetchFromHuggingFace {
        repoId = "kitten/missing-rev";
        hash = lib.fakeHash;
      })
    }" = "1"
    test "${
      failsDrv (fetchFromHuggingFace {
        repoId = "kitten/both-revisions";
        rev = "0123456789abcdef0123456789abcdef01234567";
        tag = "v1.0";
        hash = lib.fakeHash;
      })
    }" = "1"
    test "${
      failsDrv (fetchFromHuggingFace {
        repoId = "kitten/one";
        owner = "kitten";
        repo = "two";
        rev = "0123456789abcdef0123456789abcdef01234567";
        hash = lib.fakeHash;
      })
    }" = "1"
    test "${
      failsDrv (fetchFromHuggingFace {
        repoId = "kitten/model";
        repoType = "collection";
        rev = "0123456789abcdef0123456789abcdef01234567";
        hash = lib.fakeHash;
      })
    }" = "1"
    test "${
      failsDrv (fetchFromHuggingFace {
        repoId = "kitten/$(touch pwned)";
        rev = "0123456789abcdef0123456789abcdef01234567";
        hash = lib.fakeHash;
      })
    }" = "1"
    test "${
      failsDrv (fetchFromHuggingFace {
        repoId = "kitten/..";
        rev = "0123456789abcdef0123456789abcdef01234567";
        hash = lib.fakeHash;
      })
    }" = "1"
    test "${
      failsDrv (fetchFromHuggingFaceGGUF {
        repoId = "kitten/model";
        file = "../model.gguf";
        rev = "0123456789abcdef0123456789abcdef01234567";
        hash = lib.fakeHash;
      })
    }" = "1"
    test "${
      failsDrv (fetchFromHuggingFaceGGUF {
        modelRef = "kitten/model:Q4_K_M";
        repoId = "kitten/model";
        rev = "0123456789abcdef0123456789abcdef01234567";
        hash = lib.fakeHash;
      })
    }" = "1"
    test "${
      failsDrv (fetchFromHuggingFaceGGUF {
        modelRef = "kitten/model";
        rev = "0123456789abcdef0123456789abcdef01234567";
        hash = lib.fakeHash;
      })
    }" = "1"
    test "${
      failsDrv (fetchFromHuggingFaceGGUF {
        modelRef = "kitten/model:bad/quant";
        rev = "0123456789abcdef0123456789abcdef01234567";
        hash = lib.fakeHash;
      })
    }" = "1"
    test "${
      failsDrv (fetchFromHuggingFaceGGUF {
        modelRef = "kitten/model:Q4_K_M:extra";
        rev = "0123456789abcdef0123456789abcdef01234567";
        hash = lib.fakeHash;
      })
    }" = "1"
    test "${
      failsDrv (fetchFromHuggingFaceGGUF {
        repoId = "kitten/model";
        file = "model.gguf";
        rev = "0123456789abcdef0123456789abcdef01234567";
        hash = lib.fakeHash;
        mmprojHash = lib.fakeHash;
        mmprojFile = "";
      })
    }" = "1"
    touch "$out"
  '';

  simple = fetchTestRepository {
    owner = "hf-internal-testing";
    repo = "tiny-random-gpt2";
    rev = "71034c5d8bde858ff824298bdedc65515b97d2b9";
    hash = "sha256-8K9B/C62GW5lXC0c8QQpQ9QAE1UMoG+kYqvGhnWIp64=";
  };

  rootDir = fetchTestRepository {
    repoId = "hf-internal-testing/tiny-random-BertModel";
    rev = "fc08ad9cc33be9aef4f55cc80e16ef5ae3d5981c";
    rootDir = "onnx";
    hash = "sha256-ETm2DT9jvVJ5W3MP8T0RiulNUlXlA2chtc9AVI+u6n4=";
  };

  ggufFile =
    let
      source = fetchTestGGUF {
        repoId = "ybelkada/tiny-random-llama-Q4_K_M-GGUF";
        file = "tiny-random-llama.Q4_K_M.gguf";
        rev = "429fe92916dae4839bfefb46bd0f61f50cc02c73";
        hash = "sha256-vqnHG1Hgbl3jrECLolnd3Ai+P7XfuwVAokIVWybn1QI=";
      };
    in
    runCommand "fetchFromHuggingFaceGGUF-file-test" { } ''
      test -f ${source}
      test "$(head -c 4 ${source})" = "GGUF"
      touch "$out"
    '';

  ggufModelRef =
    let
      source = fetchTestGGUF {
        modelRef = "ybelkada/tiny-random-llama-Q4_K_M-GGUF:Q4_K_M";
        rev = "429fe92916dae4839bfefb46bd0f61f50cc02c73";
        hash = "sha256-vqnHG1Hgbl3jrECLolnd3Ai+P7XfuwVAokIVWybn1QI=";
      };
    in
    runCommand "fetchFromHuggingFaceGGUF-modelRef-test" { } ''
      test -f ${source}
      test "$(head -c 4 ${source})" = "GGUF"
      test "${source.modelRef}" = "ybelkada/tiny-random-llama-Q4_K_M-GGUF:Q4_K_M"
      test "${source.repoId}" = "ybelkada/tiny-random-llama-Q4_K_M-GGUF"
      test "${source.quant}" = "Q4_K_M"
      touch "$out"
    '';

  ggufWithMMProj =
    let
      source = fetchTestGGUF {
        modelRef = "ybelkada/tiny-random-llama-Q4_K_M-GGUF:Q4_K_M";
        rev = "429fe92916dae4839bfefb46bd0f61f50cc02c73";
        hash = "sha256-vqnHG1Hgbl3jrECLolnd3Ai+P7XfuwVAokIVWybn1QI=";
        mmprojFile = "tiny-random-llama.Q4_K_M.gguf";
        mmprojHash = "sha256-vqnHG1Hgbl3jrECLolnd3Ai+P7XfuwVAokIVWybn1QI=";
        passthru.marker = "kept";
      };
    in
    runCommand "fetchFromHuggingFaceGGUF-mmproj-test" { } ''
      test -d ${source}
      test -L ${source}/model.gguf
      test -L ${source}/mmproj.gguf
      test "$(readlink ${source}/model.gguf)" = "${source.model}"
      test "$(readlink ${source}/mmproj.gguf)" = "${source.mmproj}"
      test "${source.modelPath}" = "${source}/model.gguf"
      test "${source.mmprojPath}" = "${source}/mmproj.gguf"
      test "${source.repoId}" = "ybelkada/tiny-random-llama-Q4_K_M-GGUF"
      test "${source.modelRef}" = "ybelkada/tiny-random-llama-Q4_K_M-GGUF:Q4_K_M"
      test "${source.model.quant}" = "Q4_K_M"
      test "${source.marker}" = "kept"
      test "${toString source.isHuggingFaceGGUF}" = "1"
      test "${toString source.isHuggingFaceRepository}" = ""
      test "$(head -c 4 ${source}/model.gguf)" = "GGUF"
      test "$(head -c 4 ${source}/mmproj.gguf)" = "GGUF"
      touch "$out"
    '';

  cacheLayout = runWithHuggingFaceCache {
    name = "fetchFromHuggingFace-cache-layout";
    repositories = [
      {
        repoId = "gpt2";
        src = fakeRepository;
        rev = "deadbeef";
      }
      {
        repoId = "gpt2";
        src = fakeRepository;
        rev = "deadbeef";
        ref = "refs/tags/v1";
      }
      {
        repoId = "kitten/dataset";
        src = fakeRepository;
        rev = "cafebabe";
        repoType = "dataset";
        ref = "refs/pr/1";
      }
      {
        repoId = "kitten/demo-space";
        src = fakeRepository;
        rev = "feedface";
        repoType = "space";
      }
      {
        repoId = "kitten/tagged-model";
        src = fakeRepository;
        rev = "refs/tags/v1.0";
      }
    ];
    extraEnv.FETCH_HUGGING_FACE_TEST_VALUE = "value with spaces";
    command = ''
      test "$FETCH_HUGGING_FACE_TEST_VALUE" = "value with spaces"
      test "$HF_DATASETS_OFFLINE" = "1"

      ${assertCacheEntry {
        cacheDir = "models--gpt2";
        rev = "deadbeef";
        source = fakeRepository;
      }}

      ${assertCacheEntry {
        cacheDir = "models--gpt2";
        rev = "deadbeef";
        source = fakeRepository;
        ref = "refs/tags/v1";
      }}

      ${assertCacheEntry {
        cacheDir = "datasets--kitten--dataset";
        rev = "cafebabe";
        source = fakeRepository;
        ref = "refs/pr/1";
      }}

      ${assertCacheEntry {
        cacheDir = "spaces--kitten--demo-space";
        rev = "feedface";
        source = fakeRepository;
      }}

      ${assertCacheEntry {
        cacheDir = "models--kitten--tagged-model";
        rev = "refs/tags/v1.0";
        source = fakeRepository;
      }}

      touch "$out"
    '';
  };

  cacheWithHuggingFaceHub =
    let
      source = fetchTestRepository {
        owner = "hf-internal-testing";
        repo = "tiny-random-gpt2";
        rev = "71034c5d8bde858ff824298bdedc65515b97d2b9";
        hash = "sha256-8K9B/C62GW5lXC0c8QQpQ9QAE1UMoG+kYqvGhnWIp64=";
      };
    in
    runWithHuggingFaceCache {
      name = "fetchFromHuggingFace-huggingface-hub-offline";
      runtimeInputs = [ huggingFaceHubPython ];
      repositories = [ source ];
      command = ''
        python - <<'PY'
        from pathlib import Path
        from huggingface_hub import hf_hub_download, snapshot_download

        model_id = "hf-internal-testing/tiny-random-gpt2"
        config = Path(hf_hub_download(model_id, "config.json", local_files_only=True))
        snapshot = Path(snapshot_download(model_id, local_files_only=True))

        assert config.name == "config.json"
        assert config.parent == snapshot
        assert (snapshot / "pytorch_model.bin").is_file()
        PY

        touch "$out"
      '';
    };

  cacheValidation = runCommand "fetchFromHuggingFace-cache-validation-test" { } ''
    test "${
      failsDrv (runWithHuggingFaceCache {
        name = "fetchFromHuggingFace-reserved-extra-env-name";
        repositories = [
          {
            repoId = "kitten/named-model";
            src = fakeRepository;
            rev = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef";
          }
        ];
        extraEnv.HF_DATASETS_OFFLINE = "0";
        command = ''
          touch "$out"
        '';
      })
    }" = "1"
    test "${
      failsDrv (runWithHuggingFaceCache {
        name = "fetchFromHuggingFace-invalid-extra-env-name";
        repositories = [
          {
            repoId = "kitten/named-model";
            src = fakeRepository;
            rev = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef";
          }
        ];
        extraEnv."bad-name" = "value";
        command = ''
          touch "$out"
        '';
      })
    }" = "1"
    test "${
      failsDrv (runWithHuggingFaceCache {
        name = "fetchFromHuggingFace-non-inferable-direct-derivation";
        repositories = [ fakeRepositoryWithMetadata ];
        command = ''
          touch "$out"
        '';
      })
    }" = "1"
    test "${
      failsDrv (runWithHuggingFaceCache {
        name = "fetchFromHuggingFace-invalid-repo-id";
        repositories = [
          {
            repoId = "broken/repo/id";
            src = fakeRepository;
            rev = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef";
          }
        ];
        command = ''
          touch "$out"
        '';
      })
    }" = "1"
    test "${
      failsDrv (runWithHuggingFaceCache {
        name = "fetchFromHuggingFace-invalid-repo-id-characters";
        repositories = [
          {
            repoId = "kitten/$(touch pwned)";
            src = fakeRepository;
            rev = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef";
          }
        ];
        command = ''
          touch "$out"
        '';
      })
    }" = "1"
    test "${
      failsDrv (runWithHuggingFaceCache {
        name = "fetchFromHuggingFace-invalid-ref";
        repositories = [
          {
            repoId = "kitten/named-model";
            src = fakeRepository;
            rev = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef";
            ref = "../main";
          }
        ];
        command = ''
          touch "$out"
        '';
      })
    }" = "1"
    test "${
      failsDrv (runWithHuggingFaceCache {
        name = "fetchFromHuggingFace-invalid-rev";
        repositories = [
          {
            repoId = "kitten/named-model";
            src = fakeRepository;
            rev = "../deadbeef";
          }
        ];
        command = ''
          touch "$out"
        '';
      })
    }" = "1"
    touch "$out"
  '';
}

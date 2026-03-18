{
  lib,
  autoPatchelfHook,
  bazel_7,
  buildBazelPackage,
  buildPythonPackage,
  clangStdenv,
  cmake,
  fetchFromGitHub,
  ffmpeg,
  git,
  jdk11_headless,
  ninja,
  opencv4,
  perl,
  pkg-config,
  portaudio,
  protobuf,
  python,
  pythonInterpreters,
  stdenv,
  unzip,
  which,
  zip,

  # dependencies
  absl-py,
  flatbuffers,
  matplotlib,
  numpy,
  opencv-contrib-python,
  sounddevice,
}:

let
  pname = "mediapipe";
  version = "0.10.32";
  bazelPython = pythonInterpreters.python312;
  bazelPythonVersion = lib.versions.majorMinor bazelPython.pythonVersion;
  smokeTest = ./smoke-test.py;
  upstreamInstallCheckTests = [
    "mediapipe/tasks/python/test/core/base_options_test.py"
    "mediapipe/tasks/python/test/core/mediapipe_c_utils_test.py"
    "mediapipe/tasks/python/test/core/async_result_dispatcher_test.py"
    "mediapipe/tasks/python/test/core/serial_dispatcher_test.py"
    "mediapipe/tasks/python/test/components/containers/classification_result_test.py"
    "mediapipe/tasks/python/test/components/containers/detections_test.py"
    "mediapipe/tasks/python/test/components/containers/embedding_result_test.py"
    "mediapipe/tasks/python/test/components/containers/landmark_test.py"
  ];

  src = fetchFromGitHub {
    owner = "google-ai-edge";
    repo = "mediapipe";
    tag = "v${version}";
    hash = "sha256-lvfERPropIHSwhhbFrLPGI19kKPiAjRirhTQYHW45wo=";
  };

  bazelBuildTargets = [
    "//mediapipe/tasks/c:libmediapipe.so"
    "//mediapipe/tasks/metadata:image_segmenter_metadata_schema_py"
    "//mediapipe/tasks/metadata:metadata_schema_py"
    "//mediapipe/tasks/metadata:object_detector_metadata_schema_py"
    "//mediapipe/tasks/metadata:schema_py"
  ];

  bazelCommonFlags = [
    "--noenable_bzlmod"
    "--spawn_strategy=standalone"
    "--genrule_strategy=standalone"
    "--action_env=PYTHON_BIN_PATH=${bazelPython.interpreter}"
    "--repo_env=HERMETIC_PYTHON_VERSION=${bazelPythonVersion}"
    "--repo_env=PYTHON_BIN_PATH=${bazelPython.interpreter}"
    "--define=MEDIAPIPE_DISABLE_GPU=1"
    "-c opt"
  ];

  bazel-build = (buildBazelPackage.override { stdenv = clangStdenv; }) rec {
    name = "${pname}-bazel-${version}";
    inherit src;

    bazel = bazel_7;
    bazelTargets = bazelBuildTargets;
    bazelFlags = bazelCommonFlags;

    env = {
      HERMETIC_PYTHON_VERSION = bazelPythonVersion;
      PYTHON_BIN_PATH = bazelPython.interpreter;
    };

    nativeBuildInputs = [
      cmake
      git
      jdk11_headless
      ninja
      perl
      pkg-config
      protobuf
      bazelPython
      unzip
      which
      zip
    ];

    dontUseCmakeConfigure = true;

    buildInputs = [
      ffmpeg
      opencv4
      portaudio
    ];

    removeLocal = false;
    removeRulesCC = false;

    postPatch = ''
      patchShebangs .
      rm -f .bazelversion

      sed -i '/name = "linux_opencv"/,/)/ s|path = "/usr"|path = "${opencv4}"|' WORKSPACE
      sed -i '/name = "linux_ffmpeg"/,/)/ s|path = "/usr"|path = "${lib.getLib ffmpeg}"|' WORKSPACE
      sed -i '/\/\/mediapipe\/tasks\/cc\/metadata\/python:_pywrap_metadata_version/d' \
        mediapipe/tasks/python/metadata/BUILD

      cat > mediapipe/framework/port/ts_project_stub.bzl <<'EOF'
      def ts_project(**kwargs):
          pass
      EOF

      substituteInPlace mediapipe/framework/port/build_config.bzl \
        --replace-fail \
          'load("@npm//@bazel/typescript:index.bzl", "ts_project")' \
          'load("//mediapipe/framework/port:ts_project_stub.bzl", "ts_project")'

      cat > third_party/opencv_linux.BUILD <<'EOF'
      licenses(["notice"])

      cc_library(
          name = "opencv",
          hdrs = glob(["include/opencv4/opencv2/**/*.h*"]),
          includes = ["include/opencv4"],
          srcs = [
              "lib/libopencv_calib3d.so",
              "lib/libopencv_core.so",
              "lib/libopencv_features2d.so",
              "lib/libopencv_highgui.so",
              "lib/libopencv_imgcodecs.so",
              "lib/libopencv_imgproc.so",
              "lib/libopencv_video.so",
              "lib/libopencv_videoio.so",
          ],
          visibility = ["//visibility:public"],
      )
      EOF

      cat > third_party/ffmpeg_linux.BUILD <<'EOF'
      licenses(["notice"])

      cc_library(
          name = "libffmpeg",
          srcs = [
              "lib/libavcodec.so",
              "lib/libavformat.so",
              "lib/libavutil.so",
          ],
          visibility = ["//visibility:public"],
      )
      EOF
    '';

    fetchAttrs = {
      hash = "sha256-FZBnYAbmxf0/eztcqaZiwJCuziTk403L2cWv61H5sYk=";
      bazelFlags = bazelCommonFlags;
      bazelTargets = bazelBuildTargets;

      preInstall = ''
        find "$bazelOut/external" -maxdepth 1 \
          \( \
            -name 'linux_opencv' -o -name '@linux_opencv.marker' -o -name '*linux_opencv*' -o \
            -name 'linux_ffmpeg' -o -name '@linux_ffmpeg.marker' -o -name '*linux_ffmpeg*' -o \
            -name 'system_python' -o -name '@system_python.marker' -o -name '*system_python*' \
          \) -exec rm -rf {} +
      '';
    };

    buildAttrs = {
      preConfigure = ''
        substituteInPlace $bazelOut/external/rules_python/python/private/py_runtime_info.bzl \
          --replace-fail '"#!/usr/bin/env python3"' '"#!${bazelPython.interpreter}"'
        substituteInPlace $bazelOut/external/rules_python/python/private/stage1_bootstrap_template.sh \
          --replace-fail '#!/bin/bash' '#!${clangStdenv.shell}'
        substituteInPlace $bazelOut/external/rules_python/python/private/runtime_env_toolchain.bzl \
          --replace-fail '"#!/usr/bin/env python3"' '"#!${bazelPython.interpreter}"'
        substituteInPlace $bazelOut/external/rules_foreign_cc/foreign_cc/private/framework/toolchains/linux_commands.bzl \
          --replace-fail '#!/usr/bin/env bash' '#!${clangStdenv.shell}'
        substituteInPlace $bazelOut/external/rules_foreign_cc/foreign_cc/private/runnable_binary_wrapper.sh \
          --replace-fail '#!/usr/bin/env bash' '#!${clangStdenv.shell}'
        substituteInPlace $bazelOut/external/rules_foreign_cc/toolchains/prebuilt_toolchains.py \
          --replace-fail '#!/usr/bin/env python3' '#!${bazelPython.interpreter}'
        substituteInPlace $bazelOut/external/XNNPACK/tools/BUILD \
          --replace-fail \
            'load("@rules_python//python:py_binary.bzl", "py_binary")' \
            $'load("@rules_python//python:py_binary.bzl", "py_binary")\n\nexports_files(["update-microkernels.py"], visibility = ["//:__subpackages__"])'
        substituteInPlace $bazelOut/external/XNNPACK/BUILD.bazel \
          --replace-fail \
            'cmd = ("$(location //tools:update_microkernels) " +' \
            'cmd = ("${bazelPython.interpreter} $(location //tools:update-microkernels.py) " +' \
          --replace-fail \
            'tools = ["//tools:update_microkernels"],' \
            'tools = ["//tools:update-microkernels.py"],' \
          --replace-fail \
            'cmd = "$(location generate_build_identifier_py) --output $@ --input_file_list $(location :build_identifier_ukernel_srcs_list)",' \
            'cmd = "${bazelPython.interpreter} $(location scripts/generate-build-identifier.py) --output $@ --input_file_list $(location :build_identifier_ukernel_srcs_list)",' \
          --replace-fail \
            'tools = [":generate_build_identifier_py"],' \
            'tools = ["scripts/generate-build-identifier.py"],'

        mkdir -p $bazelOut/external/local_config_tensorrt/tensorrt/include
        touch $bazelOut/external/@local_config_tensorrt.marker

        cat > $bazelOut/external/local_config_tensorrt/build_defs.bzl <<'EOF'
        def if_tensorrt(if_true, if_false = []):
            return if_false

        def if_tensorrt_exec(if_true, if_false = []):
            return if_false
        EOF

        cat > $bazelOut/external/local_config_tensorrt/BUILD.bazel <<'EOF'
        package(default_visibility = ["//visibility:public"])

        exports_files([
            "build_defs.bzl",
            "LICENSE",
        ])

        filegroup(
            name = "build_defs_bzl",
            srcs = ["build_defs.bzl"],
        )

        config_setting(
            name = "use_static_tensorrt",
            define_values = {"TF_TENSORRT_STATIC": "1"},
        )

        filegroup(
            name = "tensorrt_include",
            srcs = ["tensorrt/include/tensorrt_config.h"],
        )

        filegroup(
            name = "tensorrt_lib",
            srcs = [],
        )

        cc_library(
            name = "tensorrt_headers",
            hdrs = ["tensorrt/include/tensorrt_config.h"],
        )

        cc_library(
            name = "tensorrt",
            deps = [":tensorrt_headers"],
        )

        py_library(
            name = "tensorrt_config_py",
            srcs = ["tensorrt/tensorrt_config.py"],
        )

        cc_library(
            name = "nvinfer_plugin_nms",
        )
        EOF

        touch $bazelOut/external/local_config_tensorrt/LICENSE
        : > $bazelOut/external/local_config_tensorrt/tensorrt/include/tensorrt_config.h
        cat > $bazelOut/external/local_config_tensorrt/tensorrt/tensorrt_config.py <<'EOF'
        tensorrt_config = {}
        EOF
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p $out/mediapipe/tasks/c
        mkdir -p $out/mediapipe/tasks/metadata

        cp bazel-bin/mediapipe/tasks/c/libmediapipe.so \
          $out/mediapipe/tasks/c/
        cp bazel-bin/mediapipe/tasks/metadata/*_generated.py \
          $out/mediapipe/tasks/metadata/

        runHook postInstall
      '';
    };
  };
in
buildPythonPackage {
  inherit pname version src;
  pyproject = false;

  disabled = stdenv.hostPlatform.system != "x86_64-linux";

  dontBuild = true;

  nativeBuildInputs = [ autoPatchelfHook ];

  buildInputs = [
    (lib.getLib stdenv.cc.cc)
    ffmpeg
    opencv4
    portaudio
  ];

  dependencies = [
    absl-py
    flatbuffers
    matplotlib
    numpy
    opencv-contrib-python
    sounddevice
  ];

  installPhase = ''
    runHook preInstall

    sitePackages=$out/${python.sitePackages}

    mkdir -p $sitePackages/mediapipe
    cp mediapipe/__init__.py $sitePackages/mediapipe/__init__.py
    cat >> $sitePackages/mediapipe/__init__.py <<'EOF'

import mediapipe.tasks.python as tasks
from mediapipe.tasks.python.vision.core.image import Image
from mediapipe.tasks.python.vision.core.image import ImageFormat

__version__ = "${version}"
EOF

    cp -r mediapipe/modules $sitePackages/mediapipe/

    mkdir -p $sitePackages/mediapipe/tasks
    cp mediapipe/tasks/__init__.py $sitePackages/mediapipe/tasks/
    cp -r mediapipe/tasks/python $sitePackages/mediapipe/tasks/
    cp -r mediapipe/tasks/metadata $sitePackages/mediapipe/tasks/

    rm -rf $sitePackages/mediapipe/tasks/python/benchmark
    rm -rf $sitePackages/mediapipe/tasks/python/test
    find $sitePackages/mediapipe/tasks/python -type f -name '*_test.py' -delete

    mkdir -p $sitePackages/mediapipe/tasks/c
    cp ${bazel-build}/mediapipe/tasks/c/libmediapipe.so \
      $sitePackages/mediapipe/tasks/c/
    touch $sitePackages/mediapipe/tasks/c/__init__.py

    cp ${bazel-build}/mediapipe/tasks/metadata/*_generated.py \
      $sitePackages/mediapipe/tasks/metadata/

    runHook postInstall
  '';

  doInstallCheck = true;

  preDistPhases = [ "mediapipePrepareCheckEnvPhase" ];
  mediapipePrepareCheckEnvPhase = ''
    export HOME="$TMPDIR/home"
    export MPLCONFIGDIR="$TMPDIR/matplotlib"
    export XDG_CACHE_HOME="$TMPDIR/xdg-cache"
    export XDG_CONFIG_HOME="$TMPDIR/xdg-config"
    mkdir -p "$HOME" "$MPLCONFIGDIR" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
  '';

  installCheckPhase = ''
    runHook preInstallCheck

    buildRoot=$PWD

    export HOME="$TMPDIR/home"
    export MPLCONFIGDIR="$TMPDIR/matplotlib"
    export XDG_CACHE_HOME="$TMPDIR/xdg-cache"
    export XDG_CONFIG_HOME="$TMPDIR/xdg-config"
    mkdir -p "$HOME" "$MPLCONFIGDIR" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"
    export PYTHONPATH="$out/${python.sitePackages}:$PYTHONPATH"
    export EXPECTED_MEDIAPIPE_VERSION="${version}"

    cd "$TMPDIR"
    ${python.interpreter} ${smokeTest}

    # Run a curated upstream subset that matches the Tasks/C-API package we ship.
    # These tests are asset-free and avoid the legacy pybind-only test surface.
    for testFile in ${lib.escapeShellArgs upstreamInstallCheckTests}; do
      ${python.interpreter} "$buildRoot/$testFile"
    done

    runHook postInstallCheck
  '';

  pythonImportsCheck = [
    "mediapipe"
    "mediapipe.tasks.python"
  ];

  meta = {
    description = "Cross-platform framework for building multimodal applied machine learning pipelines";
    downloadPage = "https://github.com/google-ai-edge/mediapipe";
    homepage = "https://developers.google.com/mediapipe";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
}

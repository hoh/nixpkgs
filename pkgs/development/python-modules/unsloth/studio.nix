{
  lib,
  buildPythonPackage,
  makeWrapper,
  python,

  # dependencies
  addict,
  cryptography,
  datasets,
  data-designer,
  data-designer-unstructured-seed,
  ddgs,
  diceware,
  easydict,
  fastapi,
  httpx,
  huggingface-hub,
  julius,
  kernels,
  llama-cpp,
  mammoth,
  matplotlib,
  nest-asyncio,
  numpy,
  pandas,
  pillow,
  psutil,
  pydantic,
  pyjwt,
  python-multipart,
  pymupdf4llm,
  pyyaml,
  sentence-transformers,
  soundfile,
  starlette,
  structlog,
  torch,
  torchaudio,
  torch-c-dlpack-ext,
  torchcodec,
  trl,
  typer,
  unsloth,
  unsloth-zoo,
  uvicorn,

  # tests
  callPackage,
  cudaPackages,
  gcc,
  runCommand,
  writableTmpDirAsHomeHook,
}:

let
  # The sdist includes prebuilt frontend assets that reference bundled Hellix
  # font files without a separate license marker. Remove both the files and the
  # CSS references so the UI falls back to the other packaged font stack.
  removeHellixFonts = ''
    from pathlib import Path
    import re

    font_family = '"Hellix", "Space Grotesk Variable", var(--font-sans)'
    fallback_family = '"Space Grotesk Variable", var(--font-sans)'

    for css in Path("studio/frontend/dist/assets").glob("*.css"):
        text = css.read_text()
        if "Hellix" not in text:
            continue
        text = re.sub(r'@font-face\{font-family:Hellix;[^}]*\}', "", text)
        text = text.replace(font_family, fallback_family)
        css.write_text(text)
  '';

  # Upstream Studio switches transformers versions by installing packages into
  # mutable per-user venv directories at runtime and prepending those directories
  # to sys.path. Nix packages must be immutable and offline, so keep upstream's
  # model-tier detection but validate the Nix-provided transformers without
  # creating fake venv paths or mutating PYTHONPATH.
  patchTransformersRuntimeInstaller = ''
    from pathlib import Path
    import re
    import textwrap

    path = Path("studio/backend/utils/transformers_version.py")
    text = path.read_text()

    text, count = re.subn(
        r"Two separate target directories are maintained:.*?pre-installed by setup\.sh\.\n",
        textwrap.dedent(
            """
            The Nix package keeps this model-tier detection code, but does not create
            per-user venv directories or install Python packages at runtime. Training,
            inference, and export use the immutable transformers package from Nix.
            """
        ),
        text,
        count = 1,
        flags = re.DOTALL,
    )
    if count != 1:
        raise RuntimeError("did not replace transformers version-switching docstring")

    text, count = re.subn(
        r"# Pre-installed directories .*?setup\.ps1\.\n",
        "# Compatibility directory names retained for upstream helper APIs; Nix never creates them.\n",
        text,
        count = 1,
    )
    if count != 1:
        raise RuntimeError("did not replace transformers venv directory comment")

    def replace_function(source: str, name: str, replacement: str) -> str:
        pattern = re.compile(rf"^def {name}\(.*?(?=^def |\Z)", re.DOTALL | re.MULTILINE)
        replacement = textwrap.dedent(replacement).strip() + "\n\n"
        source, count = pattern.subn(replacement, source, count = 1)
        if count != 1:
            raise RuntimeError(f"did not replace {name}")
        return source

    text = replace_function(
        text,
        "activate_transformers_for_subprocess",
        """
        def _version_tuple(value: str) -> tuple[int, ...]:
            parts: list[int] = []
            for part in value.split("."):
                digits = ""
                for char in part:
                    if not char.isdigit():
                        break
                    digits += char
                if digits == "":
                    break
                parts.append(int(digits))
            return tuple(parts)


        def _required_transformers_version_from_packages(packages: tuple[str, ...]) -> str | None:
            for pkg in packages:
                if pkg.startswith("transformers=="):
                    return pkg.split("==", 1)[1]
            return None


        def _ensure_nix_transformers_version(required_version: str | None, label: str) -> None:
            if required_version is None:
                return
            try:
                import transformers
            except Exception as exc:
                raise RuntimeError(
                    f"Could not import Nix-packaged transformers: {exc}"
                ) from exc

            installed = getattr(transformers, "__version__", "")
            if _version_tuple(installed) < _version_tuple(required_version):
                raise RuntimeError(
                    f"{label} requires transformers >= {required_version}, "
                    f"but the Nix package provides {installed}."
                )
            logger.info(
                "Using Nix-packaged transformers %s for %s; no runtime venv activation",
                installed,
                label,
            )


        def _required_transformers_version_for_model(model_name: str) -> tuple[str, str]:
            resolved = _resolve_base_model(model_name)
            tier = get_transformers_tier(resolved)
            if tier == "550":
                return resolved, TRANSFORMERS_550_VERSION
            if tier == "530":
                return resolved, TRANSFORMERS_530_VERSION
            return resolved, TRANSFORMERS_DEFAULT_VERSION


        def activate_transformers_for_subprocess(model_name: str) -> None:
            resolved, required_version = _required_transformers_version_for_model(model_name)
            _ensure_nix_transformers_version(required_version, f"{model_name} (resolved: {resolved})")
        """,
    )

    text = replace_function(
        text,
        "_install_to_dir",
        """
        def _install_to_dir(pkg: str, target_dir: str) -> bool:
            # Runtime Python package installation is disabled in the Nix package.
            raise RuntimeError(
                "Unsloth Studio is packaged by Nix and does not install Python "
                "packages at runtime. Install or update the Nix package to change "
                "Studio's packaged transformers stack."
            )
        """,
    )
    text = replace_function(
        text,
        "_ensure_venv_dir",
        """
        def _ensure_venv_dir(venv_dir: str, packages: tuple[str, ...], label: str) -> bool:
            _ensure_nix_transformers_version(
                _required_transformers_version_from_packages(packages),
                label,
            )
            return True
        """,
    )
    text = replace_function(
        text,
        "_venv_dir_is_valid",
        """
        def _venv_dir_is_valid(venv_dir: str, packages: tuple[str, ...]) -> bool:
            _ensure_nix_transformers_version(
                _required_transformers_version_from_packages(packages),
                Path(venv_dir).name,
            )
            return True
        """,
    )
    text = replace_function(
        text,
        "_venv_t5_is_valid",
        """
        def _venv_t5_is_valid() -> bool:
            return _venv_dir_is_valid(_VENV_T5_550_DIR, _VENV_T5_550_PACKAGES)
        """,
    )
    text = replace_function(
        text,
        "_ensure_venv_t5_530_exists",
        """
        def _ensure_venv_t5_530_exists() -> bool:
            return _ensure_venv_dir(
                _VENV_T5_530_DIR, _VENV_T5_530_PACKAGES, "transformers 5.3.0"
            )
        """,
    )
    text = replace_function(
        text,
        "_ensure_venv_t5_550_exists",
        """
        def _ensure_venv_t5_550_exists() -> bool:
            return _ensure_venv_dir(
                _VENV_T5_550_DIR, _VENV_T5_550_PACKAGES, "transformers 5.5.0"
            )
        """,
    )
    text = replace_function(
        text,
        "_ensure_venv_t5_exists",
        """
        def _ensure_venv_t5_exists() -> bool:
            return _ensure_venv_t5_550_exists()
        """,
    )
    text = replace_function(
        text,
        "_activate_venv",
        """
        def _activate_venv(venv_dir: str, label: str) -> None:
            logger.info("Using Nix-packaged %s; not prepending %s", label, venv_dir)
        """,
    )
    text = replace_function(
        text,
        "_deactivate_5x",
        """
        def _deactivate_5x() -> None:
            for d in (_VENV_T5_530_DIR, _VENV_T5_550_DIR):
                while d in sys.path:
                    sys.path.remove(d)
            pythonpath = os.environ.get("PYTHONPATH")
            if pythonpath:
                paths = [p for p in pythonpath.split(os.pathsep) if p not in (_VENV_T5_530_DIR, _VENV_T5_550_DIR)]
                if paths:
                    os.environ["PYTHONPATH"] = os.pathsep.join(paths)
                else:
                    os.environ.pop("PYTHONPATH", None)
        """,
    )
    text = replace_function(
        text,
        "ensure_transformers_version",
        """
        def ensure_transformers_version(model_name: str) -> None:
            resolved, required_version = _required_transformers_version_for_model(model_name)
            _ensure_nix_transformers_version(required_version, f"{model_name} (resolved: {resolved})")
        """,
    )

    path.write_text(text)
  '';
in

buildPythonPackage (finalAttrs: {
  pname = "unsloth-studio";
  inherit (unsloth) version src;
  pyproject = false;

  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  env.MPLCONFIGDIR = "/tmp/matplotlib";

  postPatch = ''
    # Remove frontend fonts that are bundled without a separate license marker.
    rm -rf \
      "studio/frontend/dist/Hellix font official" \
      "studio/frontend/dist/fonts"

    ${python.interpreter} -c ${lib.escapeShellArg removeHellixFonts}

    # Studio serves the checked-in build from frontend/dist. Dropping the
    # sources and package-manager metadata keeps the runtime output smaller and
    # avoids shipping files that are not used by the packaged application.
    find studio/frontend -mindepth 1 -maxdepth 1 ! -name dist -exec rm -rf {} +
    ${python.interpreter} -c ${lib.escapeShellArg patchTransformersRuntimeInstaller}

    # The Nix package provides the runtime environment; do not ship upstream
    # mutable venv/pip setup helpers.
    rm -f \
      studio/install_llama_prebuilt.py \
      studio/install_python_stack.py \
      studio/setup.bat \
      studio/setup.ps1 \
      studio/setup.sh

    rm -rf studio/backend/tests
  '';

  installPhase = ''
    runHook preInstall

    site="$out/${python.sitePackages}"
    install -d "$site" "$out/bin" "$out/share/licenses/${finalAttrs.pname}"

    cp -r studio "$site/"

    install -Dm644 COPYING "$out/share/licenses/${finalAttrs.pname}/COPYING"
    install -Dm644 studio/LICENSE.AGPL-3.0 "$out/share/licenses/${finalAttrs.pname}/LICENSE.AGPL-3.0"

    cat > "$out/bin/unsloth-studio" <<EOF
    #!${python.interpreter}
    import runpy
    runpy.run_module("studio.backend.run", run_name="__main__")
    EOF
    chmod +x "$out/bin/unsloth-studio"

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/unsloth-studio" \
      --set-default LLAMA_SERVER_PATH ${lib.escapeShellArg (lib.getExe' llama-cpp "llama-server")} \
      --prefix PATH : ${lib.escapeShellArg (lib.makeBinPath [ llama-cpp ])}
  '';

  dependencies = [
    addict
    cryptography
    datasets
    data-designer
    data-designer-unstructured-seed
    ddgs
    diceware
    easydict
    fastapi
    httpx
    huggingface-hub
    julius
    kernels
    mammoth
    matplotlib
    nest-asyncio
    numpy
    pandas
    pillow
    psutil
    pydantic
    pyjwt
    python-multipart
    pymupdf4llm
    pyyaml
    sentence-transformers
    soundfile
    starlette
    structlog
    torch
    torchaudio
    torch-c-dlpack-ext
    torchcodec
    trl
    typer
    unsloth
    unsloth-zoo
    uvicorn
  ];

  # Studio ships as part of the unsloth sdist and does not have its own tests.
  doCheck = false;

  pythonImportsCheck = [
    "studio"
    "studio.backend.main"
    "studio.backend.run"
  ];

  passthru.tests = callPackage ./studio-tests.nix {
    unsloth-studio = finalAttrs.finalPackage;
    inherit
      cudaPackages
      gcc
      llama-cpp
      python
      runCommand
      unsloth-zoo
      writableTmpDirAsHomeHook
      ;
  };

  meta = {
    description = "AGPL-licensed Unsloth Studio UI and backend";
    homepage = "https://github.com/unslothai/unsloth";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [ hoh ];
    mainProgram = "unsloth-studio";
    platforms = lib.platforms.linux;
  };
})

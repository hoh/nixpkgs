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
  # mutable per-user venv directories at runtime. Nix packages must be immutable
  # and offline, so keep upstream's model-tier detection but make the install
  # hooks validate the Nix-provided transformers instead of invoking pip/uv.
  patchTransformersRuntimeInstaller = ''
    from pathlib import Path
    import re
    import textwrap

    path = Path("studio/backend/utils/transformers_version.py")
    text = path.read_text()

    def replace_function(source: str, name: str, replacement: str) -> str:
        pattern = re.compile(rf"^def {name}\(.*?(?=^def |\Z)", re.DOTALL | re.MULTILINE)
        replacement = textwrap.dedent(replacement).strip() + "\n\n"
        source, count = pattern.subn(replacement, source, count = 1)
        if count != 1:
            raise RuntimeError(f"did not replace {name}")
        return source
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
            # Validate packaged transformers instead of creating mutable venvs.
            required_version = None
            for pkg in packages:
                if pkg.startswith("transformers=="):
                    required_version = pkg.split("==", 1)[1]
                    break

            if required_version is None:
                return True

            def version_tuple(value: str) -> tuple[int, ...]:
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

            try:
                import transformers
            except Exception as exc:
                raise RuntimeError(
                    f"Could not import Nix-packaged transformers: {exc}"
                ) from exc

            installed = getattr(transformers, "__version__", "")
            if version_tuple(installed) < version_tuple(required_version):
                raise RuntimeError(
                    f"{label} requires transformers >= {required_version}, "
                    f"but the Nix package provides {installed}."
                )
            logger.info(
                "Using Nix-packaged transformers %s for %s; not installing into %s",
                installed,
                label,
                venv_dir,
            )
            return True
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

    # The unstructured seed plugin is bundled in the Studio tree rather than
    # shipped as a separate PyPI distribution. Data Designer discovers plugins
    # through importlib.metadata entry points, so install minimal dist-info
    # metadata next to the copied package.
    cp -r \
      studio/backend/plugins/data-designer-unstructured-seed/src/data_designer_unstructured_seed \
      "$site/"
    plugin_dist="$site/data_designer_unstructured_seed-0.1.0.dist-info"
    install -d "$plugin_dist"
    cat > "$plugin_dist/METADATA" <<EOF
    Metadata-Version: 2.1
    Name: data-designer-unstructured-seed
    Version: 0.1.0
    EOF
    cat > "$plugin_dist/entry_points.txt" <<EOF
    [data_designer.plugins]
    unstructured = data_designer_unstructured_seed.plugin:unstructured_seed_plugin
    EOF
    touch "$plugin_dist/RECORD"

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
  };
})

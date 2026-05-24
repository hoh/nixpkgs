{
  lib,
  buildPythonPackage,
  makeWrapper,
  python,

  # dependencies
  llama-cpp,
  pydantic,
  pyyaml,
  typer,
  unsloth,
  unsloth-studio,

  # tests
  callPackage,
  cudaPackages,
  gcc,
  runCommand,
  unsloth-zoo,
  writableTmpDirAsHomeHook,
}:

let
  # Upstream's CLI expects Studio to live in a user-managed venv and allows the
  # setup/update commands to mutate that venv. In nixpkgs the CLI and Studio are
  # packaged together, so patch the CLI to call the packaged backend directly,
  # reject mutable setup/update flows, and install signal handlers for the
  # in-process server path.
  nixPackagedStudioPatch = ''
    from pathlib import Path

    path = Path("unsloth_cli/commands/studio.py")
    text = path.read_text()
    text = text.replace("import os\n", "import os\nimport signal\n")

    def delete_between(text, start, end):
        begin = text.index(start)
        finish = text.index(end, begin)
        return text[:begin] + text[finish:]

    signal_helper = (
        "def _install_studio_signal_handlers() -> None:\n"
        "    from studio.backend.run import _graceful_shutdown, _server, _shutdown_event\n"
        "\n"
        "    def _signal_handler(signum, frame):\n"
        "        _graceful_shutdown(_server)\n"
        "        if _shutdown_event is not None:\n"
        "            _shutdown_event.set()\n"
        "\n"
        "    signal.signal(signal.SIGINT, _signal_handler)\n"
        "    signal.signal(signal.SIGTERM, _signal_handler)\n"
        "    if hasattr(signal, \"SIGBREAK\"):\n"
        "        signal.signal(signal.SIGBREAK, _signal_handler)\n"
        "\n"
    )

    text = delete_between(
        text,
        "    # Always use the studio venv if it exists and we're not already in it\n",
        "    from studio.backend.run import run_server\n",
    )
    text = delete_between(
        text,
        "    # \u2500\u2500 1. Venv re-exec (same pattern as studio_default) \u2500",
        "    from studio.backend.run import run_server, _resolve_external_ip\n",
    )
    text = text.replace(
        "\n\n# \u2500\u2500 unsloth studio (server) \u2500",
        "\n" + signal_helper + "\n# \u2500\u2500 unsloth studio (server) \u2500",
    )
    text = text.replace(
        "    run_server(**run_kwargs)\n\n    from studio.backend.run import _shutdown_event\n",
        "    run_server(**run_kwargs)\n    _install_studio_signal_handlers()\n\n    from studio.backend.run import _shutdown_event\n",
    )
    text = text.replace(
        "    app = run_server(**run_kwargs)\n    actual_port = getattr(app.state, \"server_port\", port) or port\n",
        "    app = run_server(**run_kwargs)\n    _install_studio_signal_handlers()\n    actual_port = getattr(app.state, \"server_port\", port) or port\n",
    )

    setup_start = text.index("def _run_setup_script(*, verbose: bool = False) -> None:\n")
    setup_end = text.index("\n\n@studio_app.command(hidden = True)", setup_start)
    setup_replacement = """def _run_setup_script(*, verbose: bool = False) -> None:
        \"\"\"Report that the mutable upstream installer is disabled in Nix.\"\"\"
        typer.echo(
            "Unsloth Studio is managed by Nix; install or update the Nix package instead.",
            err = True,
        )
        raise typer.Exit(1)
    """
    text = text[:setup_start] + setup_replacement + text[setup_end:]

    update_start = text.index("    # Ensure SKIP_STUDIO_BASE is not inherited")
    update_end = text.index("\n\n\n# \u2500\u2500 unsloth studio reset-password", update_start)
    text = text[:update_start] + "    _run_setup_script(verbose = verbose)" + text[update_end:]

    path.write_text(text)
  '';
in

buildPythonPackage (finalAttrs: {
  pname = "unsloth-cli";
  inherit (unsloth) version src;
  pyproject = false;

  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  postPatch = ''
    ${python.interpreter} -c ${lib.escapeShellArg nixPackagedStudioPatch}
  '';

  installPhase = ''
    runHook preInstall

    site="$out/${python.sitePackages}"
    install -d "$site" "$out/bin" "$out/share/licenses/${finalAttrs.pname}"

    cp -r unsloth_cli "$site/"

    install -Dm644 COPYING "$out/share/licenses/${finalAttrs.pname}/COPYING"
    install -Dm644 studio/LICENSE.AGPL-3.0 "$out/share/licenses/${finalAttrs.pname}/LICENSE.AGPL-3.0"

    cat > "$out/bin/unsloth" <<EOF
    #!${python.interpreter}
    from unsloth_cli import app
    app()
    EOF
    chmod +x "$out/bin/unsloth"

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/unsloth" \
      --set-default LLAMA_SERVER_PATH ${lib.escapeShellArg (lib.getExe' llama-cpp "llama-server")} \
      --prefix PATH : ${lib.escapeShellArg (lib.makeBinPath [ llama-cpp ])}
  '';

  dependencies = [
    pydantic
    pyyaml
    typer
    unsloth-studio
  ];

  # The CLI ships as part of the unsloth sdist and does not have its own tests.
  doCheck = false;

  pythonImportsCheck = [ "unsloth_cli" ];

  passthru.tests = callPackage ./cli-tests.nix {
    unsloth-cli = finalAttrs.finalPackage;
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
    description = "AGPL-licensed Unsloth command-line interface";
    homepage = "https://github.com/unslothai/unsloth";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [ hoh ];
    mainProgram = "unsloth";
  };
})

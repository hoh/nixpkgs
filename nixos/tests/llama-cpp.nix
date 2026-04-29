{ lib, pkgs, ... }:

let
  modelRef = "unsloth/Qwen3.6-27B-GGUF:UD-Q4_K_XL";

  modelDrv = pkgs.runCommand "llama-cpp-test-model" { } ''
    mkdir -p "$out"
    touch "$out/model.gguf" "$out/mmproj.gguf"
  '';

  model = modelDrv // {
    inherit modelRef;
    modelPath = "${modelDrv}/model.gguf";
    mmprojPath = "${modelDrv}/mmproj.gguf";
  };

  llamaCpp = pkgs.runCommand "llama-cpp-test-server" { } ''
    mkdir -p "$out/bin"
    cat > "$out/bin/llama-server" <<'EOF'
    #!${pkgs.runtimeShell}
    printf '%s\n' "$@" > /var/lib/llama-cpp/args
    sleep infinity
    EOF
    chmod +x "$out/bin/llama-server"
  '';
in
{
  name = "llama-cpp";

  meta.maintainers = with lib.maintainers; [ newam ];

  nodes.machine = {
    services.llama-cpp = {
      enable = true;
      package = llamaCpp;
      inherit model;
    };
  };

  testScript = ''
    machine.wait_for_unit("llama-cpp.service")
    machine.wait_until_succeeds("test -f /var/lib/llama-cpp/args")

    machine.succeed("grep -Fx -- '-m' /var/lib/llama-cpp/args")
    machine.succeed("grep -Fx -- '${model}/model.gguf' /var/lib/llama-cpp/args")
    machine.succeed("grep -Fx -- '--mmproj' /var/lib/llama-cpp/args")
    machine.succeed("grep -Fx -- '${model}/mmproj.gguf' /var/lib/llama-cpp/args")
    machine.succeed("grep -Fx -- '--alias' /var/lib/llama-cpp/args")
    machine.succeed("grep -Fx -- '${modelRef}' /var/lib/llama-cpp/args")
  '';
}

{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  cfg = config.services.llama-cpp;

  hasExtraFlag =
    flags:
    builtins.any (
      extraFlag: builtins.any (flag: extraFlag == flag || lib.hasPrefix "${flag}=" extraFlag) flags
    ) cfg.extraFlags;

  modelPath = cfg.model.modelPath or cfg.model;

  alias =
    if cfg.alias != null then
      cfg.alias
    else if
      hasExtraFlag [
        "-a"
        "--alias"
      ]
    then
      null
    else
      cfg.model.modelRef or null;

  mmproj =
    if cfg.mmproj != null then
      cfg.mmproj
    else if
      hasExtraFlag [
        "-mm"
        "-mmu"
        "--mmproj"
        "--mmproj-auto"
        "--mmproj-url"
        "--no-mmproj"
        "--no-mmproj-auto"
      ]
    then
      null
    else
      cfg.model.mmprojPath or null;

  modelsPresetFile =
    if cfg.modelsPreset != null then
      pkgs.writeText "llama-models.ini" (lib.generators.toINI { } cfg.modelsPreset)
    else
      null;
in
{

  options = {

    services.llama-cpp = {
      enable = lib.mkEnableOption "LLaMA C++ server";

      package = lib.mkPackageOption pkgs "llama-cpp" { };

      model = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        example = "/models/mistral-instruct-7b/ggml-model-q4_0.gguf";
        description = ''
          Model path.

          If this is a `fetchFromHuggingFaceGGUF` result, its `modelRef`
          attribute is used automatically as the llama-server alias. Its
          `modelPath` and `mmprojPath` attributes are also used automatically
          when available.
        '';
        default = null;
      };

      mmproj = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        example = "/models/mistral-instruct-7b/mmproj-F16.gguf";
        description = ''
          Multimodal projector path passed to llama-server with
          `--mmproj`.

          If unset, this defaults to the `mmprojPath` attribute of
          {option}`services.llama-cpp.model` when available.
        '';
        default = null;
      };

      alias = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        example = "unsloth/Qwen3.6-27B-GGUF:UD-Q4_K_XL";
        description = ''
          Model alias passed to llama-server with `--alias`.

          If unset, this defaults to the `modelRef` attribute of
          {option}`services.llama-cpp.model` when available.
        '';
        default = null;
      };

      modelsDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        example = "/models/";
        description = "Models directory.";
        default = null;
      };

      modelsPreset = lib.mkOption {
        type = lib.types.nullOr (lib.types.attrsOf lib.types.attrs);
        default = null;
        description = ''
          Models preset configuration as a Nix attribute set.
          This is converted to an INI file and passed to llama-server via `--models-preset`.
          See llama-server documentation for available options.
        '';
        example = lib.literalExpression ''
          {
            "Qwen3-Coder-Next" = {
              hf-repo = "unsloth/Qwen3-Coder-Next-GGUF";
              hf-file = "Qwen3-Coder-Next-UD-Q4_K_XL.gguf";
              alias = "unsloth/Qwen3-Coder-Next";
              fit = "on";
              seed = "3407";
              temp = "1.0";
              top-p = "0.95";
              min-p = "0.01";
              top-k = "40";
              jinja = "on";
            };
          }
        '';
      };

      extraFlags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "Extra flags passed to llama-server.";
        example = [
          "-c"
          "4096"
          "-ngl"
          "32"
          "--numa"
          "numactl"
        ];
        default = [ ];
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        example = "0.0.0.0";
        description = "IP address the LLaMA C++ server listens on.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "Listen port for LLaMA C++ server.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open ports in the firewall for LLaMA C++ server.";
      };
    };

  };

  config = lib.mkIf cfg.enable {
    systemd.services.llama-cpp = {
      description = "LLaMA C++ server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "idle";
        KillSignal = "SIGINT";
        StateDirectory = "llama-cpp";
        CacheDirectory = "llama-cpp";
        WorkingDirectory = "/var/lib/llama-cpp";
        Environment = [ "LLAMA_CACHE=/var/cache/llama-cpp" ];
        ExecStart =
          let
            args = [
              "--host"
              cfg.host
              "--port"
              (toString cfg.port)
            ]
            ++ lib.optionals (cfg.model != null) [
              "-m"
              modelPath
            ]
            ++ lib.optionals (mmproj != null) [
              "--mmproj"
              mmproj
            ]
            ++ lib.optionals (alias != null) [
              "--alias"
              alias
            ]
            ++ lib.optionals (cfg.modelsDir != null) [
              "--models-dir"
              cfg.modelsDir
            ]
            ++ lib.optionals (cfg.modelsPreset != null) [
              "--models-preset"
              modelsPresetFile
            ]
            ++ cfg.extraFlags;
          in
          "${cfg.package}/bin/llama-server ${utils.escapeSystemdExecArgs args}";
        Restart = "on-failure";
        RestartSec = 300;

        # for GPU acceleration
        PrivateDevices = false;

        # hardening
        DynamicUser = true;
        CapabilityBoundingSet = "";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        NoNewPrivileges = true;
        PrivateMounts = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        MemoryDenyWriteExecute = true;
        LockPersonality = true;
        RemoveIPC = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
        SystemCallErrorNumber = "EPERM";
        ProtectProc = "invisible";
        ProtectHostname = true;
        ProcSubset = "pid";
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
    };

  };

  meta.maintainers = with lib.maintainers; [ newam ];
}

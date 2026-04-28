{
  lib,
  runCommand,
}:

{
  name,
  command,
  repositories,
  runtimeInputs ? [ ],
  extraEnv ? { },
  ...
}@args:

let
  inherit (lib)
    assertMsg
    concatLines
    concatStringsSep
    escapeShellArg
    isDerivation
    mapAttrsToList
    removeAttrs
    splitString
    ;

  repoPrefixes = {
    model = "models";
    dataset = "datasets";
    space = "spaces";
  };

  validPathPart = part: part != "." && part != ".." && builtins.match "[A-Za-z0-9._-]+" part != null;

  validCachePath = path: path != "" && builtins.all validPathPart (splitString "/" path);

  reservedEnvNames = [
    "HOME"
    "HF_HOME"
    "HF_DATASETS_OFFLINE"
    "HF_HUB_OFFLINE"
    "TRANSFORMERS_OFFLINE"
  ];

  extraArgs = removeAttrs args [
    "name"
    "command"
    "repositories"
    "runtimeInputs"
    "extraEnv"
  ];

  conflictingEnvNames = builtins.filter (envName: builtins.elem envName reservedEnvNames) (
    builtins.attrNames extraEnv
  );

  invalidEnvNames = builtins.filter (
    envName: builtins.match "[A-Za-z_][A-Za-z0-9_]*" envName == null
  ) (builtins.attrNames extraEnv);

  mkEnvExport = envName: value: "export ${envName}=${escapeShellArg (toString value)}";

  normalizeRepository =
    repository:
    let
      repositoryIsDerivation = isDerivation repository;
      repositoryAttrs = builtins.isAttrs repository && !repositoryIsDerivation;
      source =
        if repositoryIsDerivation then
          repository
        else if repositoryAttrs then
          repository.src or null
        else
          null;
      inferredRepository =
        if source != null && (source.isHuggingFaceRepository or false) then
          if source ? repoId then
            {
              repoId = source.repoId;
              repoType = source.repoType or "model";
            }
          else if source ? owner && source ? repo then
            {
              repoId = "${source.owner}/${source.repo}";
              repoType = source.repoType or "model";
            }
          else
            null
        else
          null;
      repoId =
        if repositoryAttrs && repository ? repoId then
          repository.repoId
        else if inferredRepository != null then
          inferredRepository.repoId
        else
          null;
      rev =
        if repositoryAttrs && repository ? rev then
          repository.rev
        else if source != null && source ? rev then
          source.rev
        else
          null;
      repoType =
        if repositoryAttrs && repository ? repoType then
          repository.repoType
        else if inferredRepository != null then
          inferredRepository.repoType
        else
          "model";
      ref = if repositoryAttrs then repository.ref or "main" else "main";
    in
    assert (
      assertMsg (source != null)
        "runWithHuggingFaceCache requires each repository to be either a fetchFromHuggingFace derivation or an attrset with `src`."
    );
    assert (
      assertMsg (repoId != null)
        "runWithHuggingFaceCache could not infer `repoId`; pass `repoId = \"repo\"` or `repoId = \"owner/repo\"` explicitly."
    );
    assert (
      assertMsg (rev != null) "runWithHuggingFaceCache could not infer `rev`; pass `rev` explicitly."
    );
    {
      inherit
        ref
        repoId
        repoType
        rev
        source
        ;
    };

  mkRepositorySetup =
    rawRepository:
    let
      repository = normalizeRepository rawRepository;
      inherit (repository)
        ref
        repoId
        repoType
        rev
        source
        ;
      parts = splitString "/" repository.repoId;
      validRepoId =
        builtins.length parts >= 1 && builtins.length parts <= 2 && builtins.all validPathPart parts;
      repoCacheId = builtins.concatStringsSep "--" parts;
      cacheDir = "${repoPrefixes.${repoType}}--${repoCacheId}";
    in
    assert (
      assertMsg validRepoId "runWithHuggingFaceCache requires `repoId` to be in the form `repo` or `owner/repo` using only letters, digits, '.', '_' and '-', got `${repository.repoId}`."
    );
    assert (
      assertMsg (validCachePath ref) "runWithHuggingFaceCache requires `ref` to be a relative cache path whose components use only letters, digits, '.', '_' and '-', got `${ref}`."
    );
    assert (
      assertMsg (validCachePath rev) "runWithHuggingFaceCache requires `rev` to be a relative cache path whose components use only letters, digits, '.', '_' and '-', got `${rev}`."
    );
    assert (lib.assertOneOf "repoType" repoType (builtins.attrNames repoPrefixes));
    ''
      repo_cache="$HF_HOME/hub"/${escapeShellArg cacheDir}
      mkdir -p "$repo_cache/refs" "$repo_cache/snapshots"
      ref_relpath=${escapeShellArg ref}
      snapshot_rev=${escapeShellArg rev}
      ref_path="$repo_cache/refs/$ref_relpath"
      snapshot_path="$repo_cache/snapshots/$snapshot_rev"
      mkdir -p "$(dirname "$ref_path")"
      mkdir -p "$(dirname "$snapshot_path")"
      printf '%s' "$snapshot_rev" > "$ref_path"
      if test -e "$snapshot_path"; then
        test "$(readlink "$snapshot_path")" = ${escapeShellArg (toString source)}
      else
        ln -s ${escapeShellArg (toString source)} "$snapshot_path"
      fi
    '';
in

# Bridge Nix-fetched Hugging Face snapshots into the cache layout expected by
# huggingface_hub and transformers so callers can keep plain `repoId`
# identifiers, pass `fetchFromHuggingFace` results directly, and run in offline
# mode with pinned revisions.
assert (
  assertMsg (conflictingEnvNames == [ ])
    "runWithHuggingFaceCache manages HOME, HF_HOME, HF_DATASETS_OFFLINE, HF_HUB_OFFLINE, and TRANSFORMERS_OFFLINE itself; remove them from `extraEnv`."
);
assert (
  assertMsg (invalidEnvNames == [ ])
    "runWithHuggingFaceCache requires extraEnv names to be valid shell variable names; invalid names: ${concatStringsSep ", " invalidEnvNames}."
);
runCommand name
  (
    extraArgs
    // {
      nativeBuildInputs = (extraArgs.nativeBuildInputs or [ ]) ++ runtimeInputs;
    }
  )
  ''
    export HOME="$PWD/.home"
    export HF_HOME="$HOME/.cache/huggingface"
    export HF_DATASETS_OFFLINE=1
    export HF_HUB_OFFLINE=1
    export TRANSFORMERS_OFFLINE=1

    mkdir -p "$HF_HOME/hub"

    ${concatLines (map mkRepositorySetup repositories)}
    ${concatLines (mapAttrsToList mkEnvExport extraEnv)}

    ${command}
  ''

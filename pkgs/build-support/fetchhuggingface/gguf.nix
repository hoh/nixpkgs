{
  lib,
  fetchFromHuggingFace,
  runCommand,
}:

let
  inherit (lib)
    assertMsg
    escapeShellArg
    makeOverridable
    optionalAttrs
    removeAttrs
    splitString
    ;

  validRelativePath =
    path:
    path != "" && builtins.all (part: part != "" && part != "." && part != "..") (splitString "/" path);

  validQuant = quant: quant != "" && builtins.match "[A-Za-z0-9._+-]+" quant != null;

  parseModelRef =
    modelRef:
    let
      parts = splitString ":" modelRef;
      partsLength = builtins.length parts;
    in
    assert (
      assertMsg (
        partsLength >= 1 && partsLength <= 2
      ) "fetchFromHuggingFaceGGUF requires `modelRef` to be in the form `repoId` or `repoId:quant`."
    );
    {
      repoId = builtins.elemAt parts 0;
      quant = if partsLength == 2 then builtins.elemAt parts 1 else null;
    };

  fetchOne =
    {
      file ? null,
      quant ? null,
      rootDir ? "",
      preFetch ? "",
      postCheckout ? "",
      postFetch ? "",
      ...
    }@args:

    let
      passthruAttrs = removeAttrs args [
        "file"
        "quant"
        "rootDir"
        "preFetch"
        "postCheckout"
        "postFetch"
      ];
    in
    assert (
      assertMsg (file != null || quant != null)
        "fetchFromHuggingFaceGGUF requires either `file` or `modelRef` with a quant suffix such as `repoId:Q4_K_M`."
    );
    assert (
      assertMsg (file == null || validRelativePath file)
        "fetchFromHuggingFaceGGUF requires `file` to be a relative path without empty, '.', or '..' components."
    );
    assert (
      assertMsg (quant == null || validQuant quant)
        "fetchFromHuggingFaceGGUF requires the quant in `modelRef` to contain only letters, digits, '.', '_', '+', and '-'."
    );
    assert (
      assertMsg (rootDir == "")
        "fetchFromHuggingFaceGGUF does not support `rootDir`; select a file in a subdirectory with `file` instead."
    );
    fetchFromHuggingFace (
      passthruAttrs
      // {
        inherit rootDir;
        fetchLFS = true;
        preFetch = ''
          export GIT_LFS_SKIP_SMUDGE=1
          ${preFetch}
        '';
        postCheckout = ''
          export GIT_ATTR_SOURCE=HEAD

          cd "$dir"

          selected_rel=${if file == null then "\"\"" else escapeShellArg file}
          selected_quant=${if quant == null then "\"\"" else escapeShellArg quant}
          if test -z "$selected_rel"; then
            matches_file="$(mktemp)"
            find . -type f -name '*.gguf' | sed 's,^\./,,' | while IFS= read -r candidate; do
              candidate_name="$(basename "$candidate")"
              case "$candidate_name" in
                "$selected_quant".gguf|*-"$selected_quant".gguf|*."$selected_quant".gguf|*_"$selected_quant".gguf)
                  printf '%s\n' "$candidate"
                  ;;
              esac
            done > "$matches_file"

            match_count="$(wc -l < "$matches_file" | tr -d ' ')"
            if test "$match_count" -ne 1; then
              if test "$match_count" -eq 0; then
                echo "fetchFromHuggingFaceGGUF: no .gguf file matched quant '$selected_quant'" >&2
              else
                echo "fetchFromHuggingFaceGGUF: quant '$selected_quant' matched multiple .gguf files:" >&2
                sed 's/^/  /' "$matches_file" >&2
              fi
              exit 1
            fi

            selected_rel="$(cat "$matches_file")"
          fi

          if ! test -f "$selected_rel"; then
            echo "fetchFromHuggingFaceGGUF: requested file '$selected_rel' was not found" >&2
            exit 1
          fi

          printf '%s\n' "$selected_rel" > .nix-hf-selected-gguf

          unset GIT_LFS_SKIP_SMUDGE
          git lfs pull -I "$selected_rel" -X ""

          ${postCheckout}
        '';
        postFetch = ''
          selected_rel="$(cat "$out/.nix-hf-selected-gguf")"
          selected_name="$(basename "$selected_rel")"
          tmp_dir="$(mktemp -d)"

          mv "$out/$selected_rel" "$tmp_dir/$selected_name"
          rm -rf "$out"
          mkdir -p "$(dirname "$out")"
          mv "$tmp_dir/$selected_name" "$out"
          rmdir "$tmp_dir"

          ${postFetch}
        '';
      }
    )
    // {
      inherit file quant;
      isHuggingFaceGGUF = true;
      isHuggingFaceRepository = false;
    };
in

makeOverridable (
  {
    modelRef ? null,
    repoId ? null,
    owner ? null,
    repo ? null,
    file ? null,
    mmprojHash ? null,
    mmprojFile ? "mmproj-F16.gguf",
    passthru ? { },
    ...
  }@args:

  let
    parsedModelRef = if modelRef == null then null else parseModelRef modelRef;
    modelRefArgs =
      if modelRef == null then
        { }
      else
        {
          repoId = parsedModelRef.repoId;
          quant = parsedModelRef.quant;
        };
    baseArgs = removeAttrs args [
      "modelRef"
      "mmprojHash"
      "mmprojFile"
    ];
    modelArgs =
      (
        if modelRef == null then
          baseArgs
        else
          removeAttrs baseArgs [
            "repoId"
            "owner"
            "repo"
          ]
      )
      // modelRefArgs;
    model =
      fetchOne modelArgs
      // optionalAttrs (modelRef != null) {
        inherit modelRef;
      };
    mmproj = fetchOne (
      removeAttrs modelArgs [
        "hash"
        "sha256"
        "outputHash"
        "outputHashAlgo"
        "outputHashMode"
      ]
      // {
        file = mmprojFile;
        hash = mmprojHash;
      }
    );
    combined =
      runCommand "${model.name}-with-mmproj"
        {
          preferLocalBuild = true;
          allowSubstitutes = false;
          meta = model.meta;
          inherit passthru;
        }
        ''
          mkdir -p "$out"
          ln -s ${model} "$out/model.gguf"
          ln -s ${mmproj} "$out/mmproj.gguf"
        '';
  in
  assert (
    assertMsg (modelRef == null || (repoId == null && owner == null && repo == null))
      "fetchFromHuggingFaceGGUF requires `modelRef` to be used instead of `repoId`/`owner`/`repo`, not together with them."
  );
  assert (
    assertMsg (mmprojHash == null || validRelativePath mmprojFile)
      "fetchFromHuggingFaceGGUF requires `mmprojFile` to be a relative path without empty, '.', or '..' components when `mmprojHash` is provided."
  );
  if mmprojHash == null then
    model
  else
    combined
    // {
      inherit
        file
        modelRef
        model
        mmproj
        mmprojFile
        ;
      inherit (model)
        repoId
        repoType
        rev
        ;
      tag = model.tag or null;
      meta = model.meta;
      isHuggingFaceGGUF = true;
      isHuggingFaceRepository = false;
      modelPath = "${combined}/model.gguf";
      mmprojPath = "${combined}/mmproj.gguf";
    }
    // optionalAttrs (model ? owner) {
      inherit (model) owner repo;
    }
)

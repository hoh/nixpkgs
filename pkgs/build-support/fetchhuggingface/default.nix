{
  lib,
  repoRevToNameMaybe,
  fetchgit,
}:

let
  inherit (lib)
    assertOneOf
    makeOverridable
    optionalAttrs
    removeAttrs
    splitString
    ;

  # Hugging Face repositories are always fetched through Git and many model
  # repositories store their weights in Git LFS, so this helper always uses
  # fetchgit and defaults to `fetchLFS = true`. `repoType` only changes the
  # path prefix on huggingface.co.
  repoPrefixes = {
    model = "";
    dataset = "datasets/";
    space = "spaces/";
  };

  validRepoIdPart =
    part: part != "." && part != ".." && builtins.match "[A-Za-z0-9._-]+" part != null;
in

makeOverridable (
  {
    repoId ? null,
    owner ? null,
    repo ? null,
    tag ? null,
    rev ? null,
    name ? null,
    domain ? "huggingface.co",
    repoType ? "model",
    fetchSubmodules ? false,
    leaveDotGit ? null,
    deepClone ? false,
    fetchLFS ? true,
    rootDir ? "",
    sparseCheckout ? null,
    passthru ? { },
    meta ? { },
    ... # For hash agility and additional fetchgit arguments
  }@args:

  assert (
    lib.assertMsg (lib.xor (tag == null) (
      rev == null
    )) "fetchFromHuggingFace requires one of either `rev` or `tag` to be provided (not both)."
  );

  assert (assertOneOf "repoType" repoType (builtins.attrNames repoPrefixes));

  let
    ownerProvided = owner != null;
    repoProvided = repo != null;
    repoIdFromOwnerRepo = if ownerProvided && repoProvided then "${owner}/${repo}" else null;
    normalizedRepoId = if repoId != null then repoId else repoIdFromOwnerRepo;
    repoIdParts = if normalizedRepoId == null then [ ] else splitString "/" normalizedRepoId;
    validRepoId =
      let
        length = builtins.length repoIdParts;
      in
      length >= 1 && length <= 2 && builtins.all validRepoIdPart repoIdParts;
    derivedOwner = if builtins.length repoIdParts == 2 then builtins.elemAt repoIdParts 0 else null;
    derivedRepo = if builtins.length repoIdParts == 2 then builtins.elemAt repoIdParts 1 else null;
    position = (
      if args.meta.description or null != null then
        builtins.unsafeGetAttrPos "description" args.meta
      else if tag != null then
        builtins.unsafeGetAttrPos "tag" args
      else
        builtins.unsafeGetAttrPos "rev" args
    );
    baseUrl = "https://${domain}/${repoPrefixes.${repoType}}${normalizedRepoId}";
    gitRepoUrl = "${baseUrl}.git";
    newMeta =
      meta
      // {
        homepage = meta.homepage or baseUrl;
      }
      // optionalAttrs (position != null) {
        # to indicate where derivation originates, similar to make-derivation.nix's mkDerivation
        position = "${position.file}:${toString position.line}";
      };
    passthruAttrs = removeAttrs args [
      "repoId"
      "owner"
      "repo"
      "tag"
      "rev"
      "name"
      "domain"
      "repoType"
      "passthru"
      "meta"
    ];
    # Keep the normalized revision visible on the result so callers and tests
    # can reuse the fetcher output without having to re-derive the git ref
    # handling themselves.
    revWithTag = fetchgit.getRevWithTag {
      inherit tag rev;
    };
    finalName =
      if name != null then
        name
      else
        repoRevToNameMaybe normalizedRepoId (lib.revOrTag rev tag) "huggingface";
  in
  assert (
    lib.assertMsg (
      ownerProvided == repoProvided
    ) "fetchFromHuggingFace requires `owner` and `repo` to be provided together."
  );
  assert (
    lib.assertMsg (
      normalizedRepoId != null
    ) "fetchFromHuggingFace requires either `repoId` or both `owner` and `repo`."
  );
  assert (
    lib.assertMsg (
      repoId == null || !ownerProvided || repoId == repoIdFromOwnerRepo
    ) "fetchFromHuggingFace received conflicting `repoId` and `owner`/`repo` values."
  );
  assert (
    lib.assertMsg validRepoId "fetchFromHuggingFace requires `repoId` to be in the form `repo` or `owner/repo` using only letters, digits, '.', '_' and '-'."
  );
  fetchgit (
    passthruAttrs
    // {
      inherit
        deepClone
        fetchLFS
        fetchSubmodules
        leaveDotGit
        rootDir
        sparseCheckout
        tag
        rev
        ;
      name = finalName;
      url = gitRepoUrl;
      meta = newMeta;
      passthru = {
        inherit gitRepoUrl;
        isHuggingFaceRepository = true;
      }
      // passthru;
    }
  )
  // {
    meta = newMeta;
    inherit
      tag
      repoType
      ;
    inherit gitRepoUrl;
    isHuggingFaceRepository = true;
    repoId = normalizedRepoId;
    rev = revWithTag;
  }
  // optionalAttrs (derivedOwner != null) {
    owner = derivedOwner;
    repo = derivedRepo;
  }
)

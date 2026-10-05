# GitHub-backed maintainer roster (nixpkgs-style githubId + email).
# Display names are never handwritten here. scripts/check-packages.py --sync
# queries api.github.com and writes maintainers.resolved.json.
let
  root = ../.;
  list = builtins.fromJSON (builtins.readFile (root + "/maintainers.json"));
  resolved = builtins.fromJSON (builtins.readFile (root + "/maintainers.resolved.json"));
  resolvedUser = handle:
    if builtins.hasAttr handle resolved && builtins.isAttrs resolved.${handle}
    then resolved.${handle}
    else throw "maintainer '${handle}' missing from maintainers.resolved.json. Run: python3 scripts/check-packages.py --sync";
  debianLine = handle:
    let
      entry = list.${handle} or (throw "unknown GitHub maintainer '${handle}'. Add them to maintainers.json and sync from GitHub.");
      res = resolvedUser handle;
      name = res.name or "";
      email = entry.email or "";
    in
      if name == "" then throw "GitHub user '${handle}' has no public name"
      else if email == "" then throw "maintainer '${handle}' missing email in maintainers.json"
      else "${name} <${email}>";
in {
  inherit list resolved debianLine;
  requireHandles = pname: handles:
    if handles == null || handles == []
    then throw "package '${pname}' must set sileo.maintainers to GitHub usernames"
    else handles;
}

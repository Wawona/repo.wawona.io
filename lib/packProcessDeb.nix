# Pack one upstream program as a process .deb.
# A new toolkit is pname, version, homepage, files. Not a copied dpkg script.
{ lib, mkDebFromBins }:
{ pname
, version
, target
, homepage
, description
, files
, depends ? null
, maintainers ? [ "aspauldingcode" ]
}:
mkDebFromBins {
  inherit pname version target files;
  sileo = {
    package = pname;
    inherit description homepage maintainers;
    section = "Utilities";
  } // lib.optionalAttrs (target == "android") {
    architecture = "aarch64";
  } // lib.optionalAttrs (depends != null) {
    depends = depends;
  };
  meta = { inherit description homepage; };
}

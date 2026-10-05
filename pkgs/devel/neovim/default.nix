{ pkgs, mkWawonaPackage, target ? "ios" }:

mkWawonaPackage rec {
  pname = "neovim";
  version = "0.9.1";

  src = pkgs.fetchFromGitHub {
    owner = "neovim";
    repo = "neovim";
    rev = "v${version}";
    sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  # Neovim has complex dependencies, will need more work
  buildInputs = with pkgs; [ libuv libtermkey msgpack-c libvterm unibilium ];

  sileo = {
    package = "io.wawona.neovim";
    architecture = "iphoneos-arm64";
    description = "Hyperextensible Vim-based text editor for iOS";
    maintainers = [ "aspauldingcode" ];
  };
}

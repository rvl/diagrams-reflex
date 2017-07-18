{ reflex-platform,  pkgs ? import <nixpkgs> {}, ... }: reflex-platform.ghcjs.override {
  overrides = self: super: {
    reflex-dom-contrib = self.callPackage ./reflex-dom-contrib.nix {
      inherit (pkgs) fetchFromGitHub;
    };
  };
}

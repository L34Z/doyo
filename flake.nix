{
  description = "Odin project";

  # Pinned to the same channel as the system flake so the dev shell reuses
  # store paths you already have instead of downloading a second toolchain.
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

  outputs = { nixpkgs, ... }:
    let
      forAll = f: nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ]
        (s: f nixpkgs.legacyPackages.${s});
    in {
      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            odin
            ols # Odin language server
            gdb
          ];
        };
      });
    };
}

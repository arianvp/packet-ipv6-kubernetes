{ pkgs ? import (import ./nix/sources.nix).nixpkgs {}}:
pkgs.mkShell {
  name = "packet-kubernetes";
  buildInputs = [ (pkgs.terraform_0_13) ];
}

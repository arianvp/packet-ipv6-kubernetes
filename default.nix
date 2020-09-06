{ pkgs ? import (import ./nix/sources.nix).nixpkgs {}}:
let
  kubectl = pkgs.stdenv.mkDerivation {
    name = "kubectl";
    src = pkgs.fetchurl {
      url = "https://storage.googleapis.com/kubernetes-release/release/v1.19.0/bin/linux/amd64/kubectl";
      sha256 = "03x77fz6xvqyxclicp523c50mis3a03rqqwsk4rzazs80lphvfvr";
    };
    dontUnpack = true;
    dontBuild = true;
    installPhase = ''
      cp $src kubectl
      install -Dm0755 kubectl -t $out/bin
    '';
  };
  calicoctl = pkgs.stdenv.mkDerivation {
    name = "calicoctl";
    src = pkgs.fetchurl {
      url = "https://github.com/projectcalico/calicoctl/releases/download/v3.16.0/calicoctl";
      sha256 = "14qv4wv8ndz9g7v2bq8w1fgzw14dfhn5byzp5jqp6q26z9vp0qx7";
    };
    dontUnpack = true;
    dontBuild = true;
    installPhase = ''
      cp $src calicoctl
      install -Dm0755 calicoctl -t $out/bin
    '';
  };
in
pkgs.mkShell {
  name = "packet-kubernetes";
  buildInputs = [ pkgs.terraform_0_13 kubectl calicoctl ];
}

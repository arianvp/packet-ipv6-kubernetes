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
  kubeadm = pkgs.stdenv.mkDerivation {
    name = "kubeadm";
    src = pkgs.fetchurl {
      url = "https://storage.googleapis.com/kubernetes-release/release/v1.19.0/bin/linux/amd64/kubeadm";
      sha256 = "17v5v08f3j3vzcqhgmrkiag82ak4zbjbkakrwvv4g21d632pvkl8";
    };
    dontUnpack = true;
    dontBuild = true;
    installPhase = ''
      cp $src kubeadm
      install -Dm0755 kubeadm -t $out/bin
    '';
  };
in
pkgs.mkShell {
  name = "packet-kubernetes";
  buildInputs = [ pkgs.terraform_0_13 kubectl kubeadm ];
}

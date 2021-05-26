{ pkgs ? import <nixpkgs> {} }:

let
  cobalt-fn = {rustPlatform, fetchFromGitHub, lib}: rustPlatform.buildRustPackage rec {
    pname = "cobalt";
    version = "0.16.4";
    src = fetchFromGitHub {
      owner = "cobalt-org";
      repo = "cobalt.rs";
      rev = "v${version}";
      hash = "sha256-TldwdAOf2tFZq1NywoKdbsHPhzYDfXZsYUPAQqN63rU=";
    };
    cargoSha256 = "sha256-03WMT9Wrfa/CnPLXLZK7wc9kn65BzQcDefGQDDxltoc=";
  };
  cobalt = pkgs.callPackage cobalt-fn {};
in pkgs.mkShell {
  buildInputs = [
    cobalt
  ];
}

{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  outputs =
    {
      flake-utils,
      nixpkgs,
      self,
    }:
    let
      pname = "deepobs";
      version = "1.1.2";
      src = ./.;
      mac-linux =
        pkgs: when-mac: when-linux:
        if pkgs.stdenv.isDarwin then
          when-mac
        else if pkgs.stdenv.isLinux then
          when-linux
        else
          throw "Unrecognized OS";
      pypi-os =
        pkgs: architecture: mac-version: linux-years-and-versions:
        mac-linux pkgs "macosx_${mac-version}_${architecture}" (
          builtins.concatStringsSep "." (
            builtins.map (
              v:
              "manylinux${if v ? year then v.year else ""}${
                if v ? version then "_${v.version}" else ""
              }_${architecture}"
            ) linux-years-and-versions
          )
        );
      python-version = "311";
      version-hash = s: if builtins.hasAttr python-version s then s.${python-version} else "";
      jaxlib = pkgs: pypkgs: pypkgs.jaxlib-bin;
      jax =
        pkgs: pypkgs:
        (pypkgs.jax.overridePythonAttrs {
          dependencies = [ (jaxlib pkgs pypkgs) ];
          doCheck = false;
        }).override
          { jaxlib = jaxlib pkgs pypkgs; };
      tensorflow =
        pkgs: pypkgs:
        let
          pname = "tensorflow";
          version = "2.16.1";
          format = "wheel";
        in
        pypkgs.buildPythonPackage {
          inherit pname version format;
          src = pypkgs.fetchPypi {
            inherit pname version format;
            sha256 = mac-linux pkgs (version-hash {
              "311" = "sha256-+KW4PKS/GBPaFY9jR5z9+EjAdh5RICWEF7OpYHSkifU=";
              "312" = "sha256-CcrDxqj7+FqblUkbWAhhVN0AoJlW7TGCO7RcZgXw6IE=";
            }) "sha256-kwxhEAzOOly2PTD+Z3ZQRAUhToOYomypaCIuy4uPlAQ=";
            python = "cp${python-version}";
            dist = "cp${python-version}";
            abi = "cp${python-version}";
            platform = pypi-os pkgs "x86_64" "10_15" [
              { version = "2_17"; }
              { year = "2014"; }
            ];
          };
        };
      matplotlib2tikz =
        pkgs: pypkgs:
        let
          pname = "matplotlib2tikz";
          version = "0.7.5";
        in
        pypkgs.buildPythonPackage {
          inherit pname version;
          pyproject = true;
          build-system = with pypkgs; [ setuptools ];
          dontCheckRuntimeDeps = true;
          src = pypkgs.fetchPypi {
            inherit pname version;
            sha256 = "sha256-rdCNfeSimX8ZSxxxDZOzg786/tazPkTkBYmZB5jYmE0=";
          };
        };
      dependencies =
        pkgs: pypkgs:
        (builtins.map (f: f pkgs pypkgs) [
          jax
          matplotlib2tikz
          tensorflow
        ])
        ++ (with pypkgs; [
          astunparse
          gast
          matplotlib
          numpy
          pandas
          pillow
          protobuf
          requests
          seaborn
          termcolor
          typing-extensions
          wrapt
        ]);
      python =
        pkgs: pypkgs:
        pypkgs.python.withPackages (
          pypkgs: dependencies pkgs pypkgs ++ [ (self.lib.with-pkgs pkgs pypkgs) ]
        );
    in
    (
      {
        lib.with-pkgs =
          pkgs: pypkgs:
          pypkgs.buildPythonPackage {
            inherit pname version src;
            pyproject = true;
            build-system = with pypkgs; [ setuptools ];
            dontCheckRuntimeDeps = true;
            dependencies = dependencies pkgs pypkgs;
          };
      }
      // (flake-utils.lib.eachDefaultSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowBroken = true;
          };
          pypkgs = pkgs."python${python-version}Packages";
        in
        {
          apps = builtins.mapAttrs (k: v: {
            type = "app";
            program = "${
              pkgs.stdenv.mkDerivation {
                pname = "run";
                version = "ad-hoc";
                inherit src;
                buildPhase = ":";
                installPhase = ''
                  mkdir -p $out/bin
                  echo '#!{pkgs.bash}/bin/bash' > $out/bin/run
                  echo '${v}' >> $out/bin/run
                  chmod +x $out/bin/run
                  wrapProgram $out/bin/run --prefix PATH : ${
                    nixpkgs.lib.makeBinPath ([ (python pkgs pypkgs) ] ++ (with pkgs; [ wget ]))
                  }
                '';
                nativeBuildInputs = with pkgs; [ makeWrapper ];
              }
            }/bin/run";
          }) { prepare-data = "source ${./.}/deepobs/scripts/deepobs_prepare_data.sh"; };
          devShells.default = pkgs.mkShell { packages = [ (python pkgs pypkgs) ]; };
          packages.default = self.lib.with-pkgs pkgs pypkgs;
        }
      ))
    );
}

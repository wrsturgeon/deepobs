{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };
  outputs = { flake-utils, nixpkgs, self }: flake-utils.lib.eachDefaultSystem (system:
    let
      pname = "deepobs";
      version = "1.1.2";
      python-version = "311";
      src = ./.;
      pkgs = import nixpkgs { inherit system; };
      pypkgs = pkgs."python${python-version}Packages";
      matplotlib2tikz = let
        pname = "matplotlib2tikz";
	version = "0.7.5";
      in pypkgs.buildPythonPackage {
	inherit pname version;
        pyproject = true;
	build-system = with pypkgs; [ setuptools ];
	dontCheckRuntimeDeps = true;
	src = pypkgs.fetchPypi {
	  inherit pname version;
	  sha256 = "sha256-rdCNfeSimX8ZSxxxDZOzg786/tazPkTkBYmZB5jYmE0=";
	};
      };
      python = pypkgs.python.withPackages (p: [ matplotlib2tikz ] ++ (with p; [
        matplotlib
	numpy
	pandas
	pillow
	seaborn
	tensorflow
      ]));
    in {
      apps = builtins.mapAttrs (k: v: { type = "app"; program = "${
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
	    wrapProgram $out/bin/run --prefix PATH : ${nixpkgs.lib.makeBinPath ([ python ] ++ (with pkgs; [ wget ]))}
	  '';
	  nativeBuildInputs = with pkgs; [ makeWrapper ];
	}
      }/bin/run"; }) {
        prepare-data = "source ${./.}/deepobs/scripts/deepobs_prepare_data.sh";
      };
      devShells.default = pkgs.mkShell {
        packages = [ python ];
      };
    }
  );
}

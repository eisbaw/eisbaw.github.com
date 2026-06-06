{
  description = "blog.radix63.dk — eisbaw's blog, built on niche";

  inputs.niche.url = "github:eisbaw/niche";
  inputs.nixpkgs.follows = "niche/nixpkgs";

  outputs = { self, niche, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      site = niche.lib.mkSite {
        inherit pkgs;
        contentDir = ./content;
        siteConfig = import ./site-config.nix;
        themeDir = ./theme; # niche's fancy-sidebar + a MathJax include
      };
    in {
      # GitHub Pages serves this; wrap the niche output to add the
      # custom-domain CNAME and the .nojekyll marker.
      packages.${system}.default = pkgs.runCommand "blog" { } ''
        mkdir -p $out
        cp -rL ${site}/. $out/
        chmod -R u+w $out
        printf 'blog.radix63.dk\n' > $out/CNAME
        touch $out/.nojekyll
      '';

      devShells.${system}.default = niche.devShells.${system}.default;
    };
}

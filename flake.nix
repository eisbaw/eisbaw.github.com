{
  description = "blog.radix63.dk — a Hello World site as a Nix derivation, deployed via GitHub Actions";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      indexHtml = pkgs.writeText "index.html" ''
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Hello from Nix — radix63</title>
          <style>
            body { font-family: system-ui, sans-serif; display: grid; place-items: center;
                   min-height: 100vh; margin: 0; background: #0e1116; color: #e6edf3; }
            main { text-align: center; max-width: 40rem; padding: 1rem; }
            h1 { font-size: 2.4rem; margin: 0 0 .6rem; line-height: 1.2; }
            p  { opacity: .7; }
            code { background: #1b2129; padding: .15em .4em; border-radius: 4px; }
          </style>
        </head>
        <body>
          <main>
            <h1>hello world from nix built via gh actions</h1>
            <p>This page is a <code>nix</code> derivation, built and deployed to
               <code>blog.radix63.dk</code> by GitHub Actions.</p>
          </main>
        </body>
        </html>
      '';
    in {
      packages.${system}.default = pkgs.runCommand "site" { } ''
        mkdir -p $out
        cp ${indexHtml} $out/index.html
        printf 'blog.radix63.dk\n' > $out/CNAME
        touch $out/.nojekyll
      '';
    };
}

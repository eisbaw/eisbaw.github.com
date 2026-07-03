# figures.nix — Build SVG figures from TikZ sources.
#
# Produces a derivation with SVG files in $out/.
# Used by the niche post as its assets/ directory.
#
# Pipeline: .tex -> pdflatex -> .pdf -> pdf2svg -> .svg

{ pkgs ? import <nixpkgs> {} }:

let
  texlive = pkgs.texlive.combine {
    inherit (pkgs.texlive)
      scheme-small
      standalone
      pgf          # tikz
      xcolor
      tools        # calc
      ec           # European Computer Modern fonts
      cm-super     # Type1 CM fonts (avoids mktexpk)
      ;
  };

  figureNames = [ "pipeline" "nix-layer" "theme-structure" ];
  figuresDir = ./figures;

  buildFigure = name: pkgs.runCommand "figure-${name}" {
    nativeBuildInputs = [ texlive pkgs.pdf2svg ];
    HOME = "/tmp";
  } ''
    mkdir -p $out
    cp ${figuresDir}/${name}.tex .
    pdflatex -interaction=nonstopmode ${name}.tex
    pdf2svg ${name}.pdf $out/${name}.svg
  '';

in pkgs.runCommand "niche-figures" {} (
  ''
    mkdir -p $out
    # Hand-authored title sprite: copied verbatim, not built from TikZ.
    # It rides along here (rather than a plain assets/ dir) because niche's
    # mkPost.nix cannot merge figures.nix output into a post that also has an
    # assets/ dir: it copies assets/ read-only from the store first, then the
    # figures copy hits EACCES. Routing the sprite through figures.nix keeps
    # a single asset source. Fix belongs upstream in niche's mkPost.nix.
    cp ${figuresDir}/sprite.svg $out/sprite.svg
  '' + builtins.concatStringsSep "\n" (map (name:
    "cp ${buildFigure name}/${name}.svg $out/${name}.svg"
  ) figureNames)
)

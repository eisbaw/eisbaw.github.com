# figures.nix — Build SVG figures from TikZ sources.
#
# Produces a derivation with SVG files in $out/.
# Used by the about-blog post as its assets/ directory.
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

in pkgs.runCommand "about-blog-figures" {} (
  ''
    mkdir -p $out
  '' + builtins.concatStringsSep "\n" (map (name:
    "cp ${buildFigure name}/${name}.svg $out/${name}.svg"
  ) figureNames)
)

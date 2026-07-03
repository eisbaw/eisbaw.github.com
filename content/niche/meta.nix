{
  slug = "niche";
  title = "Niche: a Nix-native blog engine";
  date = "2026-06-23";
  tags = [ "nix" "rust" "architecture" ];
  # Optional animated pixel sprite shown before the title (post page + index).
  title_icon = "sprite.svg";
  summary = "The engine behind this blog: a small Rust binary wrapped by a Nix flake, built as a compiler toolchain — compile each post, link cross-references, compose the site. Nix is the config language and the build cache; there is no YAML.";
  authors = [ "eisbaw" ];
}

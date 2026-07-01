{
  slug = "cached-windows-vm-layers";
  title = "Docker-style cached layers, but for a Windows VirtualBox VM";
  date = "2026-07-01";
  tags = [ "virtualbox" "windows" "ci" "build-systems" "caching" "iac" ];
  title_icon = "sprite.svg";
  summary = "A small bash library turns a VirtualBox Windows VM into a stack of cacheable snapshot layers. Each toolchain install is its own layer, keyed on the installer's hash. Second run is near-instant. Vagrant does not do this.";
  authors = [ "eisbaw" ];
}

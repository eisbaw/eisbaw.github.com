{
  slug = "router-out-of-memory";
  title = "The router that ran out of memory without leaking buffers";
  date = "2026-07-15";
  tags = [ "kernel" "linux" "debugging" "networking" "memory" ];
  # Optional animated pixel sprite shown before the title (post page + index).
  title_icon = "sprite.svg";
  summary = "A Linksys MX4200 bled 12-16 MB of RAM per minute and it looked exactly like an ath11k buffer leak. It wasn't. The receive rings never grew. The bug was page-frag lifetime mixing: a bounded set of buffers pinning an expanding pile of physical pages. Here is how I found the bytes, why my first traces lied, and the source fix that stopped it.";
  authors = [ "eisbaw" ];
}

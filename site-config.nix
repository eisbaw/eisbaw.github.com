{
  site_name = "radix63";
  base_url = "https://blog.radix63.dk";
  language = "en";
  posts_per_page = 20;

  nav = [
    { label = "Home"; url = "/"; }
    { label = "Archive"; url = "/archive/"; }
    { label = "Source"; url = "https://github.com/eisbaw/eisbaw.github.com"; external = true; }
  ];

  feed = {
    enable = true;
    title = "radix63";
    description = "63, just to annoy you";
  };

  author = {
    name = "eisbaw";
    email = "wabsie@gmail.com";
  };
}

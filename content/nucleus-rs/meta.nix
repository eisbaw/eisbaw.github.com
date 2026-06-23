{
  slug = "nucleus-rs";
  title = "Nucleus-rs: porting for ~free";
  date = "2026-06-23";
  tags = [ "rust" "compilers" "parallelism" "petri-nets" "embedded" ];
  summary = "Write a parallel algorithm once, with no workers, buffers, or barriers in it. A separate schedule maps it onto threads, an MPI cluster, or a microcontroller — so trying a new decomposition, a new transport, or a whole new platform becomes a small edit instead of a rewrite. The compiler synthesises the communication and proves it can't deadlock.";
  authors = [ "eisbaw" ];
}

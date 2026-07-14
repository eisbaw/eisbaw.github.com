From the euclid post, I wanted to test that no two composites a unit distance
apart share any prime factors. It seemed like I was doing half in BASH and half
in Haskell, when I realized something interesting: flip the arguments of
Haskell's `$`-operator, and you've got something very similar to UNIX pipes :).

Of course, a quick Google search proved I was not the first to think of this,
but it's still a neat trick. And since I am learning Haskell, I put this in for
my own notes:

<script src="https://gist.github.com/2605824.js?file=pipes.hs"></script>

Besides being in a more readable "cook-book" -- this is how you do it step for
step -- style, `stddev1` also allows me to comment out any trailing part of the
line without altering the first steps. Since `$` is just <span class="gloss" tabindex="0">syntax-sugar<span class="gloss-card"><span class="gc-head"><span class="gc-chip">x</span><span class="gc-name">Syntactic sugar</span></span><span class="gc-body">Notation that is easier to read or write but adds no new capability to the language.</span></span></span> for
avoiding parens, `stddev2` should be more familiar to many C++/Java programmers
(i.e. `sqrt((1/n) * sum(more nested stuff))`). The difference is only notational
of course, somewhat similar to that of polish vs <span class="gloss" tabindex="0">reverse-polish notation<span class="gloss-card"><span class="gc-head"><span class="gc-chip">x</span><span class="gc-name">Reverse Polish notation</span></span><span class="gc-body">Postfix notation where the operator follows its operands, so no parentheses are needed.</span><span class="gc-foot"><a href="https://en.wikipedia.org/wiki/Reverse_Polish_notation" target="_blank" rel="noopener">en.wikipedia.org</a></span></span></span>.

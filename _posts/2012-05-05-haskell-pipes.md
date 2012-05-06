---
layout: post
title: Unix-like pipes in Haskell
tags : [notes, Haskell, shell, pipes]
---
{% include JB/setup %}

From the euclid post, I wanted to test that no two composites a unit distance apart share any prime factors.
It seemed like I was doing half in BASH and half in Haskell, when I realized something interesting: 
Flip the arguments of Haskell's $-operator, and you've got something very similar to UNIX-pipes :).

Of course, a quick Google search proved I was not the first to think of this, but its still a neat trick. 
And since I am learning Haskell, I put this is for my own notes:

<script src="https://gist.github.com/2605824.js?file=pipes.hs"> </script>

Besides being more in a more readable "cook-book" -- this is how you do it step for step -- style, `stddev1` also allows me to comment out any trailing part of the line without altering the first steps. Since $ is just syntax-sugar for avoiding parens, `stddev2` should be more familiar to many C++/Java programmers (i.e. `sqrt((1/n) * sum(more nested stuff))`). The difference is only notational of course, somewhat similar to that of polish vs reverse-polish notation.



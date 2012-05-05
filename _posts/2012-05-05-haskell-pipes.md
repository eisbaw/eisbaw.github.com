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
And since I am learning Haskell, I put this is for my own notes.

<script src="https://gist.github.com/2605824.js?file=pipes.hs"></script>



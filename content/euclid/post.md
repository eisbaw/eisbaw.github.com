First post.
To test the combination of <span class="gloss" tabindex="0">MathJax<span class="gloss-card"><span class="gc-head"><span class="gc-chip">x</span><span class="gc-name">MathJax</span></span><span class="gc-body">A JavaScript display engine that renders LaTeX and MathML as crisp math in the browser.</span><span class="gc-foot"><a href="https://www.mathjax.org/" target="_blank" rel="noopener">mathjax.org</a></span></span></span> and a static-site engine, a small
"hello-world" proof is appropriate.

#### Theorem 1 (Euclid)

> There are infinitely many primes.

#### Proof

Suppose that $p_1 < p_2 < \dots < p_n$ are all of the primes.
Let $P = \prod_{i=1}^n p_i$ and let $p$ be a prime dividing $P$. Now define $Q=P+1$.

Then $Q$ is either prime or not:

- If $Q$ is prime, we have another prime.
- If $Q$ is <span class="gloss" tabindex="0">composite<span class="gloss-card"><span class="gc-head"><span class="gc-chip">x</span><span class="gc-name">Composite</span></span><span class="gc-body">A whole number greater than one with more than two divisors, i.e. one that is not prime.</span></span></span>, $\exists p\in \mathbb{P} : p | Q$. Since we assume $|\mathbb{P}|$ is finite, this $p \in \mathbb{P}$ must divide both $P$ and $Q$. Thus $p$ must also divide $Q-P=1$, but $1/p$ is not integer so $p$ does not divide 1. Hence this $p$ can not be in our list; but $Q$ is still composite, so some other prime factor not in our finite list, must exist.

Either way, there is another prime which we did not have in the list initially.

This also shows that two composite numbers a unit-distance apart, can not share any prime factors.

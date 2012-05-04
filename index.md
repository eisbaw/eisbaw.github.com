---
layout: page
title: about:blog
tagline: $\mathtt{this.blog}\subseteq\text{Notes}\cup\text{Programming}\cup\text{CS}\cup\text{HW}$ 
---
{% include JB/setup %}

A personal blog of miscellanea that might be useful for other people too.  
This is a [jekyll](https://github.com/mojombo/jekyll/wiki) blog using [mathjax](http://www.mathjax.org/) for increased prettyness. It is graciously hosted at [github](https://github.com/eisbaw/eisbaw.github.com) for free.


# Latest blog entries:

<ul class="posts">
  {% for post in site.posts %}
    <li><span>{{ post.date | date_to_string }}</span> &raquo; <a href="{{ BASE_PATH }}{{ post.url }}">{{ post.title }}</a></li>
  {% endfor %}
</ul>




/* firstmate-config guide shell. Single source of truth for navigation.
 * Each page is plain HTML with an <article>; this script wraps it with the
 * header, sidebar, "on this page" index, copy buttons, and prev/next links.
 * Works from file:// - no fetches, no build step, no dependencies. */
(function () {
  'use strict';

  var NAV = [
    { group: 'Get started', pages: [
      ['index.html', 'Overview'],
      ['install.html', 'Installation and first run'],
      ['update.html', 'Update and recovery']
    ]},
    { group: 'Concepts', pages: [
      ['architecture.html', 'Architecture and startup'],
      ['roles-skills.html', 'Roles and skills'],
      ['dispatch.html', 'Dispatch routing'],
      ['safety.html', 'Safety and trust boundaries']
    ]},
    { group: 'Reference', pages: [
      ['config.html', 'Configuration and files'],
      ['cli.html', 'CLI reference'],
      ['board.html', 'Task board'],
      ['bots.html', 'Bots']
    ]}
  ];

  var root = document.documentElement;
  var KEY = 'fmc-guide-theme';
  function storedTheme() { try { return localStorage.getItem(KEY); } catch (e) { return null; } }
  function applyTheme(t) { root.setAttribute('data-theme', t); }
  applyTheme(storedTheme() || (window.matchMedia && matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'));

  function el(tag, attrs, children) {
    var n = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      if (k === 'text') n.textContent = attrs[k]; else n.setAttribute(k, attrs[k]);
    });
    (children || []).forEach(function (c) { n.appendChild(c); });
    return n;
  }

  function init() {
    var article = document.querySelector('article');
    if (!article) return;
    var current = location.pathname.split('/').pop() || 'index.html';
    var flat = [];
    NAV.forEach(function (g) { g.pages.forEach(function (p) { flat.push(p); }); });
    var idx = flat.findIndex(function (p) { return p[0] === current; });

    // --- header ---
    var menuBtn = el('button', { type: 'button', 'class': 'iconbtn menu-btn', 'aria-label': 'Toggle navigation', 'aria-expanded': 'false', 'aria-controls': 'sidebar', text: 'Menu' });
    var brand = el('a', { 'class': 'brand', href: 'index.html' }, [
      el('span', { 'class': 'mark', 'aria-hidden': 'true', text: '>' }),
      el('span', { text: 'firstmate-config' }),
      el('small', { text: 'guide' })
    ]);
    var REPO = 'https://github.com/inkayat/firstmate-config';
    var gh = el('a', { 'class': 'iconbtn gh', href: REPO, text: 'GitHub' });
    var themeBtn = el('button', { type: 'button', 'class': 'iconbtn', 'aria-label': 'Toggle color theme' });
    function themeLabel() { themeBtn.textContent = root.getAttribute('data-theme') === 'dark' ? 'Light' : 'Dark'; }
    themeLabel();
    themeBtn.addEventListener('click', function () {
      var next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
      applyTheme(next);
      try { localStorage.setItem(KEY, next); } catch (e) { /* private mode: keep session-only */ }
      themeLabel();
    });
    var header = el('header', { 'class': 'topbar' }, [menuBtn, brand, el('span', { 'class': 'spacer' }), gh, themeBtn]);

    // --- sidebar ---
    var sidebar = el('nav', { 'class': 'sidebar', id: 'sidebar', 'aria-label': 'Guide pages' });
    NAV.forEach(function (g) {
      sidebar.appendChild(el('h2', { text: g.group }));
      var ul = el('ul');
      g.pages.forEach(function (p) {
        var a = el('a', { href: p[0], text: p[1] });
        if (p[0] === current) a.setAttribute('aria-current', 'page');
        ul.appendChild(el('li', {}, [a]));
      });
      sidebar.appendChild(ul);
    });
    sidebar.appendChild(el('a', { 'class': 'repo-link', href: REPO, text: 'Repository on GitHub' }));

    // --- headings: anchors + on-this-page ---
    var heads = Array.prototype.slice.call(article.querySelectorAll('h2[id]'));
    heads.forEach(function (h) {
      h.appendChild(el('a', { 'class': 'anchor', href: '#' + h.id, 'aria-label': 'Link to this section', text: '#' }));
    });
    var tocLinks = [];
    var toc = el('aside', { 'class': 'toc', 'aria-label': 'On this page' });
    var mobileToc = el('details', { 'class': 'toc-mobile' }, [el('summary', { text: 'On this page' })]);
    if (heads.length) {
      toc.appendChild(el('h2', { text: 'On this page' }));
      var tul = el('ul'); var mul = el('ul');
      heads.forEach(function (h) {
        var label = h.firstChild.textContent.trim();
        var a = el('a', { href: '#' + h.id, text: label });
        tocLinks.push(a);
        tul.appendChild(el('li', {}, [a]));
        mul.appendChild(el('li', {}, [el('a', { href: '#' + h.id, text: label })]));
      });
      toc.appendChild(tul);
      mobileToc.appendChild(mul);
      article.insertBefore(mobileToc, article.children[1] || null);
    }

    // --- code blocks: copy buttons; tables: scroll wrappers ---
    Array.prototype.forEach.call(article.querySelectorAll('pre'), function (pre) {
      if (pre.classList.contains('out') || pre.hasAttribute('data-nocopy')) return;
      var btn = el('button', { type: 'button', 'class': 'copy', text: 'Copy' });
      btn.addEventListener('click', function () {
        var text = pre.querySelector('code') ? pre.querySelector('code').innerText : pre.innerText;
        var done = function () { btn.textContent = 'Copied'; btn.classList.add('done'); setTimeout(function () { btn.textContent = 'Copy'; btn.classList.remove('done'); }, 1400); };
        if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, function () { btn.textContent = 'Press Ctrl/Cmd+C'; });
        else { var r = document.createRange(); r.selectNodeContents(pre); var s = getSelection(); s.removeAllRanges(); s.addRange(r); btn.textContent = 'Selected'; }
      });
      pre.appendChild(btn);
    });
    Array.prototype.forEach.call(article.querySelectorAll('table'), function (t) {
      var cols = t.querySelectorAll('thead th').length;
      if (cols >= 3) t.classList.add(cols >= 4 ? 'cols-4' : 'cols-3');
      var w = el('div', { 'class': 'table-wrap', tabindex: '0', role: 'region', 'aria-label': 'Table, scrolls horizontally' });
      t.parentNode.insertBefore(w, t); w.appendChild(t);
    });

    // --- prev / next ---
    var pager = el('nav', { 'class': 'pager', 'aria-label': 'Previous and next page' });
    if (idx > 0) pager.appendChild(el('a', { 'class': 'prev', href: flat[idx - 1][0] }, [el('small', { text: 'Previous' }), el('span', { text: flat[idx - 1][1] })]));
    if (idx >= 0 && idx < flat.length - 1) pager.appendChild(el('a', { 'class': 'next', href: flat[idx + 1][0] }, [el('small', { text: 'Next' }), el('span', { text: flat[idx + 1][1] })]));
    article.appendChild(pager);
    article.appendChild(el('p', { 'class': 'pagefoot', text: 'This guide describes firstmate-config as it exists on the main branch. The repository README and the files it links remain the source of truth.' }));

    // --- assemble shell ---
    var main = document.querySelector('main') || el('main', { id: 'content' });
    if (!main.parentNode) { article.parentNode.insertBefore(main, article); main.appendChild(article); }
    var scrim = el('div', { 'class': 'scrim' });
    var shell = el('div', { 'class': 'shell' }, [sidebar, main, toc]);
    var skip = el('a', { 'class': 'skip', href: '#content', text: 'Skip to content' });
    var legacy = document.querySelector('noscript'); if (legacy) legacy.remove();
    document.body.insertBefore(skip, document.body.firstChild);
    document.body.insertBefore(header, skip.nextSibling);
    document.body.insertBefore(shell, header.nextSibling);
    document.body.insertBefore(scrim, shell.nextSibling);
    main.id = 'content';

    // --- mobile drawer ---
    function setNav(open) {
      document.body.classList.toggle('nav-open', open);
      menuBtn.setAttribute('aria-expanded', String(open));
    }
    menuBtn.addEventListener('click', function () { setNav(!document.body.classList.contains('nav-open')); });
    scrim.addEventListener('click', function () { setNav(false); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') setNav(false); });

    // --- scrollspy ---
    if (tocLinks.length && 'IntersectionObserver' in window) {
      var byId = {}; tocLinks.forEach(function (a) { byId[a.getAttribute('href').slice(1)] = a; });
      var obs = new IntersectionObserver(function (entries) {
        entries.forEach(function (en) {
          if (en.isIntersecting) {
            tocLinks.forEach(function (a) { a.classList.remove('active'); });
            byId[en.target.id].classList.add('active');
          }
        });
      }, { rootMargin: '-72px 0px -70% 0px' });
      heads.forEach(function (h) { obs.observe(h); });
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();

// Flixor Landing Page Interactions
(function () {
  const root = document.documentElement;
  const themeToggle = document.getElementById('themeToggle');
  const mobileNav = document.getElementById('mobileNav');
  const navToggle = document.querySelector('.nav-toggle');
  const year = document.getElementById('year');

  // Year in footer
  if (year) year.textContent = new Date().getFullYear();

  // Theme: load preference
  const stored = localStorage.getItem('flixor.theme');
  if (stored === 'light') {
    root.setAttribute('data-theme', 'light');
    if (themeToggle) themeToggle.textContent = '☀️';
  }

  // Theme: toggle
  themeToggle?.addEventListener('click', () => {
    const isLight = root.getAttribute('data-theme') === 'light';
    const next = isLight ? null : 'light';
    if (next) {
      root.setAttribute('data-theme', next);
      localStorage.setItem('flixor.theme', next);
      themeToggle.textContent = '☀️';
    } else {
      root.removeAttribute('data-theme');
      localStorage.removeItem('flixor.theme');
      themeToggle.textContent = '🌙';
    }
  });

  // Mobile nav toggle
  navToggle?.addEventListener('click', () => {
    const expanded = navToggle.getAttribute('aria-expanded') === 'true';
    navToggle.setAttribute('aria-expanded', String(!expanded));
    mobileNav.style.display = expanded ? 'none' : 'flex';
  });

  // Close mobile nav on link click
  mobileNav?.querySelectorAll('a').forEach((a) => {
    a.addEventListener('click', () => {
      if (window.innerWidth < 960) {
        mobileNav.style.display = 'none';
        navToggle?.setAttribute('aria-expanded', 'false');
      }
    });
  });

  // Header shadow on scroll
  const header = document.querySelector('.site-header');
  const onScroll = () => {
    const scrolled = window.scrollY > 6;
    header?.classList.toggle('scrolled', scrolled);
    if (scrolled) {
      header?.style.setProperty('box-shadow', '0 8px 24px rgba(0,0,0,.18)');
      header?.style.setProperty('backdrop-filter', 'saturate(110%) blur(8px)');
    } else {
      header?.style.removeProperty('box-shadow');
      header?.style.removeProperty('backdrop-filter');
    }
  };
  window.addEventListener('scroll', onScroll, { passive: true });
  onScroll();
})();


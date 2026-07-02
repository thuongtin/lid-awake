if (typeof gsap !== 'undefined' && typeof ScrollTrigger !== 'undefined') {
  gsap.registerPlugin(ScrollTrigger);

  const mm = gsap.matchMedia();

  mm.add('(prefers-reduced-motion: no-preference)', () => {
    gsap.defaults({ ease: 'power2.out', duration: 0.7 });

    function reveal(selector, vars = {}) {
      gsap.utils.toArray(selector).forEach((el) => {
        gsap.from(el, {
          y: 24,
          autoAlpha: 0,
          scrollTrigger: {
            trigger: el,
            start: 'top 85%',
            toggleActions: 'play none none none',
          },
          ...vars,
        });
      });
    }

    function revealBatch(selector, vars = {}, batchVars = {}) {
      const { y = 24, scale, duration = 0.5, stagger = 0.08 } = vars;
      const hidden = { y, autoAlpha: 0 };
      const shown = { y: 0, autoAlpha: 1, duration, stagger };
      if (scale !== undefined) {
        hidden.scale = scale;
        shown.scale = 1;
      }

      gsap.set(selector, hidden);
      ScrollTrigger.batch(selector, {
        start: 'top 88%',
        once: true,
        onEnter: (batch) => gsap.to(batch, shown),
        ...batchVars,
      });
    }

    // Header + hero: entrance on load, not scroll-linked (already in the first viewport).
    gsap.from('.site-header', { y: -20, autoAlpha: 0, duration: 0.6, ease: 'power2.out' });

    const heroTl = gsap.timeline({ defaults: { ease: 'power3.out' } });
    heroTl
      .from('.hero-copy .eyebrow', { y: 16, autoAlpha: 0, duration: 0.5 })
      .from('.hero-title span', { y: 22, autoAlpha: 0, duration: 0.6, stagger: 0.08 }, '-=0.3')
      .from('.hero-subtitle', { y: 18, autoAlpha: 0, duration: 0.5 }, '-=0.3')
      .from('.hero-actions > *', { y: 14, autoAlpha: 0, duration: 0.5, stagger: 0.08 }, '-=0.25')
      .from('.hero-footnote', { autoAlpha: 0, duration: 0.4 }, '-=0.2')
      .from('.hero-terminal', { y: 24, autoAlpha: 0, duration: 0.6 }, '-=0.5')
      .from('.terminal-chrome .dot', {
        scale: 0, autoAlpha: 0, duration: 0.35, stagger: 0.06, ease: 'back.out(2)',
      }, '-=0.35');

    // Features.
    reveal('.features .eyebrow, .features h2');
    revealBatch('.feature-card', { scale: 0.97 });

    // How it works.
    reveal('.how .eyebrow, .how h2, .how-intro');
    gsap.timeline({
      scrollTrigger: {
        trigger: '.trust-flow',
        start: 'top 80%',
        toggleActions: 'play none none none',
      },
      defaults: { ease: 'power2.out', duration: 0.5 },
    })
      .from('.trust-flow .flow-node:nth-child(1)', { y: 16, autoAlpha: 0 })
      .from('.trust-flow .flow-arrow:nth-child(2)', { autoAlpha: 0, duration: 0.3 }, '-=0.15')
      .from('.trust-flow .flow-node:nth-child(3)', { y: 16, autoAlpha: 0 }, '-=0.1')
      .from('.trust-flow .flow-arrow:nth-child(4)', { autoAlpha: 0, duration: 0.3 }, '-=0.15')
      .from('.trust-flow .flow-node:nth-child(5)', { y: 16, autoAlpha: 0 }, '-=0.1');
    reveal('.flow-note');
    revealBatch('.does-col li', { y: 14, duration: 0.4, stagger: 0.06 });
    revealBatch('.doesnt-col li', { y: 14, duration: 0.4, stagger: 0.06 });
    reveal('.trust-note');

    // Specs.
    reveal('.specs .eyebrow, .specs h2');
    revealBatch('.specs-table tr', { y: 12, duration: 0.4, stagger: 0.06 });

    // Install.
    reveal('.install-card', { y: 30, scale: 0.98 });

    // CTA banner.
    gsap.timeline({
      scrollTrigger: {
        trigger: '.cta-banner',
        start: 'top 82%',
        toggleActions: 'play none none none',
      },
      defaults: { ease: 'power2.out', duration: 0.55 },
    })
      .from('.cta-banner h2', { y: 20, autoAlpha: 0 })
      .from('.cta-banner p', { y: 16, autoAlpha: 0 }, '-=0.3')
      .from('.cta-banner .cta-actions > *', { y: 14, autoAlpha: 0, stagger: 0.08 }, '-=0.25');

    // Footer.
    revealBatch('.footer-brand, .footer-col', { y: 20, duration: 0.5, stagger: 0.08 });
    reveal('.footer-bottom');

    if (document.fonts && document.fonts.ready) {
      document.fonts.ready.then(() => ScrollTrigger.refresh());
    }
  });
}

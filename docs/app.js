const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      }
    });
  },
  { threshold: 0.15 }
);

document.querySelectorAll(".section, .hero, .feature-card, .showcase-card, .install-card, .usage-card, .community-card").forEach((el) => {
  el.classList.add("reveal");
  observer.observe(el);
});

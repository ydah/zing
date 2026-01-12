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

document.querySelectorAll(".copy-button").forEach((button) => {
  button.addEventListener("click", async () => {
    const text = button.getAttribute("data-copy");
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
      button.textContent = "Copied";
      setTimeout(() => {
        button.textContent = "Copy";
      }, 1200);
    } catch (err) {
      button.textContent = "Failed";
      setTimeout(() => {
        button.textContent = "Copy";
      }, 1200);
    }
  });
});

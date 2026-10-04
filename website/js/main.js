document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
      e.preventDefault();
      const targetId = this.getAttribute('href');
      if (targetId === '#') return;

      const targetElement = document.querySelector(targetId);
      if (targetElement) {
        targetElement.scrollIntoView({
          behavior: 'smooth',
          block: 'start'
        });
      }
    });
  });
});

console.log('%c✨ Usage Meter%c\nBuilt with ❤️ by f-is-h\nhttps://github.com/sirpooya/osx-usage-meter', 'color: #CC785C; font-size: 16px; font-weight: bold;', 'color: #666; font-size: 12px;');

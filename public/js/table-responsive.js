(() => {
  const MOBILE_BREAKPOINT = 760;
  let resizeRafId = null;

  const getHeaderLabels = (table) =>
    Array.from(table.querySelectorAll('thead th')).map((header) =>
      String(header.textContent || '').trim().replace(/\s+/g, ' ')
    );

  const applyLabels = (table) => {
    const labels = getHeaderLabels(table);
    if (!labels.length) {
      return;
    }

    const rows = table.querySelectorAll('tbody tr');
    rows.forEach((row) => {
      const cells = Array.from(row.children).filter((child) => child.tagName === 'TD');
      if (!cells.length) {
        return;
      }

      if (cells.length === 1 && cells[0].colSpan > 1) {
        cells[0].removeAttribute('data-label');
        return;
      }

      cells.forEach((cell, index) => {
        const label = labels[index] || `Field ${index + 1}`;
        cell.setAttribute('data-label', label);
      });
    });
  };

  const updateResponsiveState = () => {
    const mobileMode = window.innerWidth <= MOBILE_BREAKPOINT;
    const wraps = document.querySelectorAll('.table-wrap');

    wraps.forEach((wrap) => {
      const table = wrap.querySelector('table');
      if (!table) {
        return;
      }

      if (wrap.dataset.labelsBound !== '1') {
        applyLabels(table);
        wrap.dataset.labelsBound = '1';
      }

      wrap.classList.toggle('mobile-cards', mobileMode);
    });
  };

  const onResize = () => {
    if (resizeRafId != null) {
      cancelAnimationFrame(resizeRafId);
    }

    resizeRafId = requestAnimationFrame(() => {
      updateResponsiveState();
      resizeRafId = null;
    });
  };

  window.addEventListener('resize', onResize, { passive: true });
  updateResponsiveState();
})();

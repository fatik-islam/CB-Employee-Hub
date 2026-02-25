(() => {
  const ISO_DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
  const DMY_DATE_RE = /^(\d{2})-{1,2}(\d{2})-{1,2}(\d{4})$/;
  const MOBILE_QUERY = '(max-width: 920px)';

  const toDisplayDate = (value) => {
    const text = String(value || '').trim();
    const iso = text.match(ISO_DATE_RE);
    if (iso) {
      return `${iso[3]}-${iso[2]}-${iso[1]}`;
    }
    const dmy = text.match(DMY_DATE_RE);
    if (dmy) {
      return `${dmy[1]}-${dmy[2]}-${dmy[3]}`;
    }
    return '';
  };

  const toIsoDate = (value) => {
    const text = String(value || '').trim();
    const iso = text.match(ISO_DATE_RE);
    if (iso) {
      return `${iso[1]}-${iso[2]}-${iso[3]}`;
    }
    const dmy = text.match(DMY_DATE_RE);
    if (dmy) {
      return `${dmy[3]}-${dmy[2]}-${dmy[1]}`;
    }
    return '';
  };

  const fields = document.querySelectorAll('[data-date-field]');
  fields.forEach((field) => {
    const displayInput = field.querySelector('[data-date-display]');
    const nativeInput = field.querySelector('[data-date-native]');
    const openBtn = field.querySelector('[data-date-open]');

    if (!displayInput || !nativeInput || !openBtn) {
      return;
    }

    const enableMobileNativeMode = () => {
      field.classList.add('mobile-native-date');
      nativeInput.removeAttribute('aria-hidden');
      nativeInput.tabIndex = 0;
    };

    if (window.matchMedia(MOBILE_QUERY).matches || 'ontouchstart' in window) {
      enableMobileNativeMode();
    }

    const syncNativeFromDisplay = () => {
      const iso = toIsoDate(displayInput.value);
      nativeInput.value = iso;
    };

    const syncDisplayFromNative = () => {
      displayInput.value = toDisplayDate(nativeInput.value);
    };

    syncNativeFromDisplay();

    openBtn.addEventListener('click', () => {
      syncNativeFromDisplay();
      if (typeof nativeInput.showPicker === 'function') {
        nativeInput.showPicker();
      } else {
        if (field.classList.contains('mobile-native-date')) {
          nativeInput.focus();
          return;
        }
        nativeInput.focus();
        nativeInput.click();
      }
    });

    nativeInput.addEventListener('change', syncDisplayFromNative);
    nativeInput.addEventListener('input', syncDisplayFromNative);

    displayInput.addEventListener('blur', () => {
      const normalized = toDisplayDate(displayInput.value);
      displayInput.value = normalized;
      syncNativeFromDisplay();
    });
  });
})();

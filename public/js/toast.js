(() => {
  const TYPE_META = {
    success: { title: 'Success', icon: '✓' },
    error: { title: 'Error', icon: '!' },
    info: { title: 'Notice', icon: 'i' },
    warning: { title: 'Warning', icon: '!' },
  };

  const DEFAULT_DURATION = 4600;
  const seenKeys = new Map();

  const createStack = () => {
    const stack = document.createElement('div');
    stack.className = 'toast-stack';
    stack.setAttribute('aria-live', 'polite');
    stack.setAttribute('aria-atomic', 'true');
    document.body.appendChild(stack);
    return stack;
  };

  const stack = createStack();

  const closeToast = (toast) => {
    if (!toast || toast.dataset.closing === '1') {
      return;
    }
    toast.dataset.closing = '1';
    toast.classList.remove('show');
    window.setTimeout(() => {
      toast.remove();
    }, 220);
  };

  const notify = (options = {}) => {
    const type = String(options.type || 'info').toLowerCase();
    const message = String(options.message || '').trim();

    if (!message) {
      return;
    }

    const dedupeKey = `${type}:${message}`;
    const now = Date.now();
    const lastShownAt = seenKeys.get(dedupeKey) || 0;
    if (now - lastShownAt < 1200) {
      return;
    }
    seenKeys.set(dedupeKey, now);

    const meta = TYPE_META[type] || TYPE_META.info;
    const title = String(options.title || meta.title);
    const duration = Number(options.duration) > 0 ? Number(options.duration) : DEFAULT_DURATION;

    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.setAttribute('role', 'status');

    const icon = document.createElement('span');
    icon.className = 'toast-icon';
    icon.textContent = meta.icon;

    const content = document.createElement('div');
    content.className = 'toast-content';

    const heading = document.createElement('strong');
    heading.className = 'toast-title';
    heading.textContent = title;

    const body = document.createElement('p');
    body.className = 'toast-message';
    body.textContent = message;

    content.appendChild(heading);
    content.appendChild(body);

    const close = document.createElement('button');
    close.type = 'button';
    close.className = 'toast-close';
    close.setAttribute('aria-label', 'Close notification');
    close.textContent = '×';
    close.addEventListener('click', () => closeToast(toast));

    const progress = document.createElement('span');
    progress.className = 'toast-progress';

    const progressBar = document.createElement('span');
    progressBar.className = 'toast-progress-bar';
    progressBar.style.animationDuration = `${duration}ms`;
    progress.appendChild(progressBar);

    toast.appendChild(icon);
    toast.appendChild(content);
    toast.appendChild(close);
    toast.appendChild(progress);

    stack.appendChild(toast);
    requestAnimationFrame(() => {
      toast.classList.add('show');
    });

    window.setTimeout(() => closeToast(toast), duration);
  };

  window.AppUI = window.AppUI || {};
  window.AppUI.notify = notify;

  const toErrorMessage = (reason) => {
    if (!reason) {
      return 'Unexpected client error.';
    }

    if (typeof reason === 'string') {
      return reason;
    }

    if (reason?.message) {
      return String(reason.message);
    }

    return 'Unexpected client error.';
  };

  window.addEventListener('error', (event) => {
    notify({
      type: 'error',
      title: 'Client Error',
      message: toErrorMessage(event.error || event.message),
      duration: 5600,
    });
  });

  window.addEventListener('unhandledrejection', (event) => {
    notify({
      type: 'error',
      title: 'Request Error',
      message: toErrorMessage(event.reason),
      duration: 5600,
    });
  });

  const flashNode = document.getElementById('flashToastData');
  if (flashNode) {
    notify({
      type: flashNode.dataset.flashType || 'info',
      message: flashNode.dataset.flashMessage || '',
    });
  }
})();

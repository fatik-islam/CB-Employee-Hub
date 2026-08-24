(() => {
  const modal = document.getElementById('globalConfirmModal');
  const titleEl = document.getElementById('globalConfirmTitle');
  const bodyEl = document.getElementById('globalConfirmBody');
  const cancelBtn = document.getElementById('globalConfirmCancelBtn');
  const proceedBtn = document.getElementById('globalConfirmProceedBtn');

  if (!modal || !titleEl || !bodyEl || !cancelBtn || !proceedBtn) {
    return;
  }

  let pendingResolver = null;
  let isOpen = false;

  const openModal = ({ title, message, proceedLabel, cancelLabel }) => {
    titleEl.textContent = title || 'Confirm Action';
    bodyEl.textContent = message || 'Are you sure you want to continue?';
    proceedBtn.textContent = proceedLabel || 'Confirm';
    cancelBtn.textContent = cancelLabel || 'Cancel';
    modal.classList.remove('hidden');
    isOpen = true;
  };

  const closeModal = () => {
    modal.classList.add('hidden');
    isOpen = false;
  };

  const resolvePending = (value) => {
    if (typeof pendingResolver === 'function') {
      pendingResolver(value);
    }
    pendingResolver = null;
  };

  const confirm = (options = {}) =>
    new Promise((resolve) => {
      pendingResolver = resolve;
      openModal(options);
    });

  window.AppUI = window.AppUI || {};
  window.AppUI.confirm = confirm;

  const handleCancel = () => {
    closeModal();
    resolvePending(false);
  };

  document.addEventListener('submit', (event) => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement)) {
      return;
    }

    if (!form.matches('form[data-confirm-form]')) {
      return;
    }

    if (form.dataset.confirmed === '1') {
      delete form.dataset.confirmed;
      return;
    }

    event.preventDefault();
    confirm({
      title: form.dataset.confirmTitle,
      message: form.dataset.confirmMessage,
      proceedLabel: form.dataset.confirmProceed,
      cancelLabel: form.dataset.confirmCancel,
    }).then((accepted) => {
      if (!accepted) {
        return;
      }

      form.dataset.confirmed = '1';
      form.submit();
    }).catch((error) => {
      if (window.AppUI?.notify) {
        window.AppUI.notify({
          type: 'error',
          message: error?.message || 'Confirmation dialog failed. Please retry.',
        });
      }
    });
  });

  cancelBtn.addEventListener('click', handleCancel);

  proceedBtn.addEventListener('click', () => {
    if (!isOpen) {
      closeModal();
      return;
    }

    closeModal();
    resolvePending(true);
  });

  modal.addEventListener('click', (event) => {
    if (event.target === modal) {
      handleCancel();
    }
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && isOpen) {
      handleCancel();
    }
  });
})();

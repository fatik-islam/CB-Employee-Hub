(() => {
  const modal = document.getElementById('employeeDetailsModal');
  const closeBtn = document.getElementById('employeeDetailsCloseBtn');
  const triggers = document.querySelectorAll('[data-employee-view]');

  if (!modal || !closeBtn || !triggers.length) {
    return;
  }

  const fields = {
    code: document.getElementById('employeeDetailsCode'),
    name: document.getElementById('employeeDetailsName'),
    phone: document.getElementById('employeeDetailsPhone'),
    position: document.getElementById('employeeDetailsPosition'),
    role: document.getElementById('employeeDetailsRole'),
    status: document.getElementById('employeeDetailsStatus'),
    cnic: document.getElementById('employeeDetailsCnic'),
    joiningDate: document.getElementById('employeeDetailsJoiningDate'),
    salaryDate: document.getElementById('employeeDetailsSalaryDate'),
    address: document.getElementById('employeeDetailsAddress'),
  };

  let lastTrigger = null;
  let open = false;

  const safeValue = (value) => {
    const text = String(value ?? '').trim();
    return text || '-';
  };

  const close = () => {
    if (!open) {
      return;
    }
    modal.classList.add('hidden');
    open = false;
    if (lastTrigger) {
      lastTrigger.focus();
    }
  };

  const showDetails = (trigger) => {
    const data = trigger.dataset;
    fields.code.textContent = safeValue(data.employeeCode);
    fields.name.textContent = safeValue(data.employeeName);
    fields.phone.textContent = safeValue(data.employeePhone);
    fields.position.textContent = safeValue(data.employeePosition);
    fields.role.textContent = safeValue(data.employeeRole);
    fields.status.textContent = safeValue(data.employeeStatus);
    fields.cnic.textContent = safeValue(data.employeeCnic);
    fields.joiningDate.textContent = safeValue(data.employeeJoiningDate);
    fields.salaryDate.textContent = safeValue(data.employeeSalaryDate);
    fields.address.textContent = safeValue(data.employeeAddress);

    modal.classList.remove('hidden');
    open = true;
    closeBtn.focus();
  };

  triggers.forEach((trigger) => {
    trigger.addEventListener('click', () => {
      lastTrigger = trigger;
      showDetails(trigger);
    });
  });

  closeBtn.addEventListener('click', close);

  modal.addEventListener('click', (event) => {
    if (event.target === modal) {
      close();
    }
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      close();
    }
  });
})();

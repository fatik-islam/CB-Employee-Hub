(() => {
  const ISO_DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
  const SQL_DATETIME_RE = /^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::\d{2})?)?$/;
  const DMY_DATE_RE = /^(\d{2})-{1,2}(\d{2})-{1,2}(\d{4})$/;
  const REQUEST_TIMEOUT_MS = 15000;

  const faceVideo = document.getElementById('faceVideo');
  const faceCanvas = document.getElementById('faceCanvas');
  const faceStatus = document.getElementById('faceStatus');
  const faceEmployeeId = document.getElementById('faceEmployeeId');
  const dateInput = document.getElementById('biometricDate');
  const startCameraBtn = document.getElementById('startCameraBtn');
  const enrollFaceBtn = document.getElementById('enrollFaceBtn');
  const verifyFaceBtn = document.getElementById('verifyFaceBtn');
  const removeFaceBtn = document.getElementById('removeFaceBtn');

  const indicatorFaceStatus = document.getElementById('indicatorFaceStatus');
  const indicatorUpdatedAt = document.getElementById('indicatorUpdatedAt');

  if (!faceVideo) {
    return;
  }

  const summaries = window.__employeeSummaries || {};
  const toastState = {
    message: '',
    tone: '',
    time: 0,
  };

  const formatDate = (value) => {
    const text = String(value || '').trim();
    const iso = text.match(ISO_DATE_RE);
    if (iso) {
      return `${iso[3]}-${iso[2]}-${iso[1]}`;
    }
    const dmy = text.match(DMY_DATE_RE);
    if (dmy) {
      return `${dmy[1]}-${dmy[2]}-${dmy[3]}`;
    }
    return text || '-';
  };

  const formatDateTime = (value) => {
    const text = String(value || '').trim();
    const stamp = text.match(SQL_DATETIME_RE);
    if (stamp) {
      const [, year, month, day, hour = '00', minute = '00'] = stamp;
      return `${day}-${month}-${year} ${hour}:${minute}`;
    }
    return formatDate(text);
  };

  const setStatus = (el, message, tone = 'info') => {
    if (!el) {
      return;
    }

    el.textContent = message;

    if (tone === 'error') {
      el.style.color = '#9d1717';
      const now = Date.now();
      if (
        window.AppUI?.notify &&
        (toastState.message !== message || toastState.tone !== tone || now - toastState.time > 1800)
      ) {
        window.AppUI.notify({ type: 'error', message });
        toastState.message = message;
        toastState.tone = tone;
        toastState.time = now;
      }
      return;
    }

    if (tone === 'success') {
      el.style.color = '#0b7742';
      const now = Date.now();
      if (
        window.AppUI?.notify &&
        (toastState.message !== message || toastState.tone !== tone || now - toastState.time > 1800)
      ) {
        window.AppUI.notify({ type: 'success', message });
        toastState.message = message;
        toastState.tone = tone;
        toastState.time = now;
      }
      return;
    }

    el.style.color = '#17348f';
  };

  const fetchJson = async (url, payload) => {
    const controller = new AbortController();
    const timeoutId = window.setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

    try {
      const response = await fetch(url, {
        method: payload ? 'POST' : 'GET',
        headers: payload
          ? {
              'Content-Type': 'application/json',
            }
          : undefined,
        body: payload ? JSON.stringify(payload) : undefined,
        signal: controller.signal,
      });

      const data = await response.json().catch(() => ({}));

      if (!response.ok) {
        throw new Error(data.error || `Request failed (${response.status})`);
      }

      return data;
    } catch (error) {
      if (error?.name === 'AbortError') {
        throw new Error('Request timed out. Please retry.');
      }

      if (error instanceof TypeError) {
        throw new Error('Network error. Check connection and retry.');
      }

      throw error;
    } finally {
      window.clearTimeout(timeoutId);
    }
  };

  const requireEmployeeSelection = () => {
    const employeeId = faceEmployeeId?.value || '';

    if (!employeeId) {
      throw new Error('Please select an employee first.');
    }

    return employeeId;
  };

  const renderSummary = (summary) => {
    if (!summary) {
      indicatorFaceStatus && (indicatorFaceStatus.textContent = 'Select employee');
      indicatorUpdatedAt && (indicatorUpdatedAt.textContent = '-');
      return;
    }

    const hasFace = Number(summary.has_face_profile || 0) === 1;
    const faceText = hasFace ? 'Enrolled' : 'Not enrolled';
    const faceUpdated = summary.face_updated_at ? formatDateTime(summary.face_updated_at) : '-';

    indicatorFaceStatus && (indicatorFaceStatus.textContent = `${faceText}`);
    indicatorUpdatedAt && (indicatorUpdatedAt.textContent = faceUpdated);
  };

  const loadEmployeeSummary = async (employeeId) => {
    if (!employeeId) {
      renderSummary(null);
      return;
    }

    if (summaries[employeeId]) {
      renderSummary(summaries[employeeId]);
      return;
    }

    try {
      const data = await fetchJson(`/api/biometric/employee-summary/${employeeId}`);
      summaries[employeeId] = data.summary;
      renderSummary(data.summary);
    } catch (error) {
      setStatus(faceStatus, error.message, 'error');
    }
  };

  faceEmployeeId?.addEventListener('change', () => {
    loadEmployeeSummary(faceEmployeeId.value);
  });

  if (faceEmployeeId?.value) {
    loadEmployeeSummary(faceEmployeeId.value);
  }

  dateInput?.addEventListener('blur', () => {
    if (dateInput.type === 'date') {
      return;
    }
    const normalized = formatDate(dateInput.value);
    if (DMY_DATE_RE.test(normalized)) {
      dateInput.value = normalized;
    }
  });

  let modelsLoaded = false;

  const loadFaceModels = async () => {
    if (modelsLoaded || typeof faceapi === 'undefined') {
      return;
    }

    const modelBase = 'https://cdn.jsdelivr.net/npm/@vladmandic/face-api/model';

    await Promise.all([
      faceapi.nets.tinyFaceDetector.loadFromUri(modelBase),
      faceapi.nets.faceLandmark68Net.loadFromUri(modelBase),
      faceapi.nets.faceRecognitionNet.loadFromUri(modelBase),
    ]);

    modelsLoaded = true;
  };

  const startCamera = async () => {
    if (!faceVideo) {
      return;
    }

    if (faceVideo.srcObject) {
      return;
    }

    const stream = await navigator.mediaDevices.getUserMedia({
      video: {
        width: { ideal: 1280 },
        height: { ideal: 720 },
        facingMode: 'user',
      },
      audio: false,
    });

    faceVideo.srcObject = stream;
    await faceVideo.play();
  };

  const captureDescriptor = async () => {
    if (!faceVideo) {
      throw new Error('Camera UI is not available.');
    }

    await loadFaceModels();
    await startCamera();

    const detection = await faceapi
      .detectSingleFace(faceVideo, new faceapi.TinyFaceDetectorOptions({ inputSize: 256, scoreThreshold: 0.5 }))
      .withFaceLandmarks()
      .withFaceDescriptor();

    if (!detection) {
      throw new Error('No face detected. Keep face centered and retry.');
    }

    if (faceCanvas) {
      const ctx = faceCanvas.getContext('2d');
      faceCanvas.width = faceVideo.videoWidth;
      faceCanvas.height = faceVideo.videoHeight;
      ctx.drawImage(faceVideo, 0, 0, faceCanvas.width, faceCanvas.height);
    }

    return Array.from(detection.descriptor || []);
  };

  const runFaceFlow = async (mode) => {
    try {
      const employeeId = requireEmployeeSelection();
      setStatus(faceStatus, 'Processing face scan...');
      const descriptor = await captureDescriptor();
      const enteredDate = String(dateInput?.value || '').trim();
      const date = enteredDate || new Date().toISOString().slice(0, 10);

      const endpoint = mode === 'enroll' ? '/api/biometric/face/enroll' : '/api/biometric/face/verify';
      const payload = { employeeId, descriptor, date };
      const result = await fetchJson(endpoint, payload);
      const details = result.distance != null ? ` (distance ${Number(result.distance).toFixed(4)})` : '';
      setStatus(faceStatus, `${result.message || 'Face operation completed.'}${details}`, 'success');

      await loadEmployeeSummary(employeeId);
    } catch (error) {
      setStatus(faceStatus, error.message, 'error');
    }
  };

  const removeFaceProfile = async () => {
    try {
      const employeeId = requireEmployeeSelection();
      const runRemoval = async () => {
        setStatus(faceStatus, 'Removing face profile...');
        const result = await fetchJson('/api/biometric/face/delete', { employeeId });
        setStatus(faceStatus, result.message || 'Face profile removed.', 'success');

        summaries[employeeId] = null;
        await loadEmployeeSummary(employeeId);
      };

      if (window.AppUI?.confirm) {
        const confirmed = await window.AppUI.confirm({
          title: 'Remove Face Profile',
          message: 'Remove this employee face profile? This action cannot be undone.',
          proceedLabel: 'Remove Profile',
          cancelLabel: 'Cancel',
        });
        if (!confirmed) {
          return;
        }
      }

      await runRemoval();
    } catch (error) {
      setStatus(faceStatus, error.message, 'error');
    }
  };

  startCameraBtn?.addEventListener('click', async () => {
    try {
      await startCamera();
      setStatus(faceStatus, 'Camera started. Ready for enrollment and verification.', 'success');
    } catch (error) {
      setStatus(faceStatus, `Camera error: ${error.message}`, 'error');
    }
  });

  enrollFaceBtn?.addEventListener('click', () => runFaceFlow('enroll'));
  verifyFaceBtn?.addEventListener('click', () => runFaceFlow('verify'));
  removeFaceBtn?.addEventListener('click', removeFaceProfile);
})();

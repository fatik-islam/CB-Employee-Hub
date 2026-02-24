(() => {
  const ISO_DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
  const SQL_DATETIME_RE = /^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::\d{2})?)?$/;
  const REQUEST_TIMEOUT_MS = 15000;

  const shell = document.querySelector('.kiosk-shell');
  const video = document.getElementById('kioskVideo');
  const overlay = document.getElementById('kioskOverlay');
  const capture = document.getElementById('kioskCapture');

  const statusEl = document.getElementById('kioskStatus');
  const faceChip = document.getElementById('feedbackFace');
  const lightingChip = document.getElementById('feedbackLighting');
  const multiFaceChip = document.getElementById('feedbackMultiFace');
  const livenessChip = document.getElementById('feedbackLiveness');
  const confidenceChip = document.getElementById('feedbackConfidence');

  const startBtn = document.getElementById('startKioskCameraBtn');
  const verifyBtn = document.getElementById('verifyIdentityBtn');
  const confirmBtn = document.getElementById('confirmAttendanceBtn');
  const resetBtn = document.getElementById('resetKioskBtn');
  const fullscreenBtn = document.getElementById('fullscreenBtn');

  const candidateWrap = document.getElementById('kioskCandidate');
  const candidateName = document.getElementById('candidateName');
  const candidateMeta = document.getElementById('candidateMeta');

  const logList = document.getElementById('todayLogList');

  if (!video || !overlay || !statusEl) {
    return;
  }

  const lockedDate = shell?.getAttribute('data-locked-date') || new Date().toISOString().slice(0, 10);

  const formatDate = (value) => {
    const text = String(value || '').trim();
    const match = text.match(ISO_DATE_RE);
    if (!match) {
      return text || '--';
    }
    return `${match[3]}-${match[2]}-${match[1]}`;
  };

  const formatDateTime = (value) => {
    const text = String(value || '').trim();
    const match = text.match(SQL_DATETIME_RE);
    if (!match) {
      return formatDate(text);
    }
    const [, year, month, day, hour = '00', minute = '00'] = match;
    return `${day}-${month}-${year} ${hour}:${minute}`;
  };

  const state = {
    modelsLoaded: false,
    analyzing: false,
    latestDescriptor: null,
    facesDetected: 0,
    lightingOk: false,
    livenessPassed: false,
    readyToVerify: false,
    confidence: null,
    matchedEmployee: null,
    livenessSamples: [],
    resetTimer: null,
  };

  const toastState = {
    message: '',
    tone: '',
    time: 0,
  };

  const setStatus = (message, tone = 'info') => {
    statusEl.textContent = message;
    statusEl.className = `kiosk-status ${tone}`;

    if (tone !== 'success' && tone !== 'error') {
      return;
    }

    const now = Date.now();
    if (
      !window.AppUI?.notify ||
      (toastState.message === message && toastState.tone === tone && now - toastState.time <= 1800)
    ) {
      return;
    }

    window.AppUI.notify({ type: tone, message });
    toastState.message = message;
    toastState.tone = tone;
    toastState.time = now;
  };

  const setChip = (element, text, tone = 'neutral') => {
    if (!element) {
      return;
    }

    element.textContent = text;
    element.className = `feedback-chip ${tone}`;
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

  const loadModels = async () => {
    if (state.modelsLoaded || typeof faceapi === 'undefined') {
      return;
    }

    const modelBase = 'https://cdn.jsdelivr.net/npm/@vladmandic/face-api/model';

    await Promise.all([
      faceapi.nets.tinyFaceDetector.loadFromUri(modelBase),
      faceapi.nets.faceLandmark68Net.loadFromUri(modelBase),
      faceapi.nets.faceRecognitionNet.loadFromUri(modelBase),
    ]);

    state.modelsLoaded = true;
  };

  const startCamera = async () => {
    if (video.srcObject) {
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

    video.srcObject = stream;
    await video.play();

    setStatus('Camera started. Stand in front and wait for readiness.', 'info');
  };

  const averageBrightness = () => {
    const ctx = capture.getContext('2d', { willReadFrequently: true });
    const sampleWidth = 96;
    const sampleHeight = 72;

    capture.width = sampleWidth;
    capture.height = sampleHeight;
    ctx.drawImage(video, 0, 0, sampleWidth, sampleHeight);

    const data = ctx.getImageData(0, 0, sampleWidth, sampleHeight).data;
    let sum = 0;
    for (let i = 0; i < data.length; i += 4) {
      const r = data[i];
      const g = data[i + 1];
      const b = data[i + 2];
      sum += 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }

    return sum / (sampleWidth * sampleHeight);
  };

  const eyeAspectRatio = (eye) => {
    const distance = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);

    const vertical = distance(eye[1], eye[5]) + distance(eye[2], eye[4]);
    const horizontal = distance(eye[0], eye[3]);

    return horizontal ? vertical / (2.0 * horizontal) : 0;
  };

  const updateLiveness = (landmarks, boxWidth) => {
    const leftEye = landmarks.getLeftEye();
    const rightEye = landmarks.getRightEye();
    const nose = landmarks.getNose();

    if (!leftEye?.length || !rightEye?.length || !nose?.length) {
      return false;
    }

    const ear = (eyeAspectRatio(leftEye) + eyeAspectRatio(rightEye)) / 2;
    const nosePoint = nose[Math.floor(nose.length / 2)];

    state.livenessSamples.push({
      ear,
      nx: nosePoint.x,
      ny: nosePoint.y,
    });

    if (state.livenessSamples.length > 14) {
      state.livenessSamples.shift();
    }

    if (state.livenessSamples.length < 6) {
      return false;
    }

    const ears = state.livenessSamples.map((item) => item.ear);
    const xs = state.livenessSamples.map((item) => item.nx);
    const ys = state.livenessSamples.map((item) => item.ny);

    const earRange = Math.max(...ears) - Math.min(...ears);
    const movement = Math.hypot(Math.max(...xs) - Math.min(...xs), Math.max(...ys) - Math.min(...ys));
    const normalizedMovement = boxWidth ? movement / boxWidth : 0;

    return earRange > 0.035 || normalizedMovement > 0.045;
  };

  const drawOverlay = (detections) => {
    const ctx = overlay.getContext('2d');
    overlay.width = video.videoWidth;
    overlay.height = video.videoHeight;

    ctx.clearRect(0, 0, overlay.width, overlay.height);

    detections.forEach((detection) => {
      const box = detection.detection.box;
      ctx.strokeStyle = '#f4a31b';
      ctx.lineWidth = 3;
      ctx.strokeRect(box.x, box.y, box.width, box.height);
    });
  };

  const renderReadiness = () => {
    setChip(faceChip, state.facesDetected > 0 ? 'Face detected' : 'No face detected', state.facesDetected > 0 ? 'good' : 'bad');
    setChip(lightingChip, state.lightingOk ? 'Lighting good' : 'Low lighting', state.lightingOk ? 'good' : 'bad');
    setChip(
      multiFaceChip,
      state.facesDetected > 1 ? 'Multiple faces detected' : state.facesDetected === 1 ? 'Single face in frame' : 'Single face required',
      state.facesDetected > 1 ? 'bad' : state.facesDetected === 1 ? 'good' : 'warn'
    );
    setChip(
      livenessChip,
      state.livenessPassed ? 'Liveness passed' : 'Liveness pending',
      state.livenessPassed ? 'good' : 'warn'
    );
    setChip(
      confidenceChip,
      state.confidence == null ? 'Confidence: --' : `Confidence: ${(state.confidence * 100).toFixed(1)}%`,
      state.confidence == null ? 'neutral' : state.confidence >= 0.75 ? 'good' : 'warn'
    );

    verifyBtn.disabled = !state.readyToVerify;
    confirmBtn.disabled = !state.matchedEmployee;
  };

  const analyzeFrame = async () => {
    if (!state.modelsLoaded || state.analyzing || video.readyState < 2) {
      return;
    }

    state.analyzing = true;

    try {
      const brightness = averageBrightness();
      state.lightingOk = brightness >= 58;

      const detections = await faceapi
        .detectAllFaces(video, new faceapi.TinyFaceDetectorOptions({ inputSize: 256, scoreThreshold: 0.45 }))
        .withFaceLandmarks()
        .withFaceDescriptors();

      state.facesDetected = detections.length;
      drawOverlay(detections);

      if (detections.length === 1) {
        const single = detections[0];
        state.latestDescriptor = Array.from(single.descriptor || []);
        state.livenessPassed = updateLiveness(single.landmarks, single.detection.box.width);
      } else {
        state.latestDescriptor = null;
        state.livenessPassed = false;
        state.livenessSamples = [];
      }

      state.readyToVerify =
        state.facesDetected === 1 &&
        state.lightingOk &&
        state.livenessPassed &&
        Array.isArray(state.latestDescriptor) &&
        state.latestDescriptor.length > 0;

      renderReadiness();
    } catch {
      setStatus('Frame analysis error. Please retry.', 'error');
    } finally {
      state.analyzing = false;
    }
  };

  const resetWorkflow = () => {
    state.confidence = null;
    state.matchedEmployee = null;
    candidateWrap.classList.add('hidden');
    candidateName.textContent = '-';
    candidateMeta.textContent = '-';
    renderReadiness();
    setStatus('Ready for next attendance check.', 'success');
  };

  const verifyIdentity = async () => {
    try {
      if (!state.readyToVerify || !state.latestDescriptor) {
        throw new Error('System is not ready. Ensure single face, good lighting, and liveness pass.');
      }

      setStatus('Verifying identity...', 'info');

      const result = await fetchJson('/api/attendance/face/identify', {
        descriptor: state.latestDescriptor,
        facesDetected: state.facesDetected,
        lightingOk: state.lightingOk,
        livenessPassed: state.livenessPassed,
      });

      state.confidence = result.confidence;
      state.matchedEmployee = result.employee;
      candidateWrap.classList.remove('hidden');
      candidateName.textContent = result.employee.fullName;
      candidateMeta.textContent = `${result.employee.employeeCode} • ${result.employee.position || 'Employee'}`;

      renderReadiness();
      setStatus('Identity verified. Confirm attendance to finalize.', 'success');
    } catch (error) {
      state.confidence = null;
      state.matchedEmployee = null;
      renderReadiness();
      setStatus(error.message, 'error');
    }
  };

  const confirmAttendance = async () => {
    try {
      if (!state.matchedEmployee) {
        throw new Error('No verified employee to confirm.');
      }

      setStatus('Confirming attendance...', 'info');

      const result = await fetchJson('/api/attendance/confirm', {
        employeeId: state.matchedEmployee.id,
        confidence: state.confidence,
      });

      setStatus(result.message, 'success');
      await refreshTodayLog();

      if (state.resetTimer) {
        clearTimeout(state.resetTimer);
      }

      state.resetTimer = setTimeout(() => {
        resetWorkflow();
      }, 3500);
    } catch (error) {
      setStatus(error.message, 'error');
    }
  };

  const renderLogEntries = (entries) => {
    if (!logList) {
      return;
    }

    if (!entries.length) {
      logList.innerHTML = '<div class="today-log-empty">No attendance entries yet for today.</div>';
      return;
    }

    const html = entries
      .map((entry) => {
        const timeStamp = entry.updated_at_display || formatDateTime(entry.updated_at);
        const statusTone = entry.status === 'present' ? 'good' : entry.status === 'leave' ? 'warn' : 'bad';

        return `
          <article class="today-log-item">
            <div>
              <strong>${entry.full_name}</strong>
              <p>${entry.employee_code} • ${entry.position || 'Employee'}</p>
            </div>
            <div class="today-log-meta">
              <span class="status-pill ${statusTone}">${entry.status}</span>
              <span>${entry.mark_source || '-'}</span>
              <span>${timeStamp}</span>
            </div>
          </article>
        `;
      })
      .join('');

    logList.innerHTML = html;
  };

  const refreshTodayLog = async () => {
    try {
      const data = await fetchJson('/api/attendance/today-log');
      renderLogEntries(data.entries || []);
    } catch {
      if (logList) {
        logList.innerHTML = '<div class="today-log-empty">Unable to load attendance log.</div>';
      }
    }
  };

  const toggleFullScreen = async () => {
    if (!document.fullscreenElement) {
      await document.documentElement.requestFullscreen();
      return;
    }

    await document.exitFullscreen();
  };

  startBtn?.addEventListener('click', async () => {
    try {
      await loadModels();
      await startCamera();
    } catch (error) {
      setStatus(error.message, 'error');
    }
  });

  verifyBtn?.addEventListener('click', verifyIdentity);
  confirmBtn?.addEventListener('click', confirmAttendance);
  resetBtn?.addEventListener('click', resetWorkflow);
  fullscreenBtn?.addEventListener('click', toggleFullScreen);

  loadModels()
    .then(startCamera)
    .catch((error) => setStatus(`Camera/model error: ${error.message}`, 'error'));

  setInterval(analyzeFrame, 350);
  refreshTodayLog();
  setInterval(refreshTodayLog, 8000);

  setStatus(`System date: ${formatDate(lockedDate)}`, 'info');
})();

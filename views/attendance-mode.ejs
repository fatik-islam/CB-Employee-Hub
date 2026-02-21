<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title><%= pageTitle %> | Chicky Bites Attendance</title>
    <link rel="icon" type="image/png" href="/assets/logo.png" />
    <link rel="shortcut icon" type="image/png" href="/assets/logo.png" />
    <link rel="apple-touch-icon" href="/assets/logo.png" />
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      href="https://fonts.googleapis.com/css2?family=Sora:wght@400;500;600;700;800&family=Manrope:wght@400;500;600;700&display=swap"
      rel="stylesheet"
    />
    <link rel="stylesheet" href="/public/css/styles.css" />
  </head>
  <body class="kiosk-body" data-kiosk="<%= kioskMode ? '1' : '0' %>">
    <main class="kiosk-shell" data-locked-date="<%= lockedDate %>">
      <header class="kiosk-topbar">
        <div class="kiosk-title">
          <img src="/assets/logo.png" alt="Chicky Bites logo" class="kiosk-title-logo" />
          <h1>Attendance Mode</h1>
        </div>

        <div class="kiosk-topbar-actions">
          <span class="kiosk-date-pill">System Date: <%= lockedDate %></span>
          <button id="fullscreenBtn" class="btn neutral" type="button">Full Screen</button>

          <% if (kioskMode) { %>
            <form action="/kiosk-logout" method="post">
              <button class="btn neutral" type="submit">Exit Kiosk</button>
            </form>
          <% } else { %>
            <a class="btn neutral" href="/dashboard">Back to Admin</a>
          <% } %>
        </div>
      </header>

      <section class="kiosk-main-grid">
        <article class="kiosk-camera-panel">
          <div class="kiosk-camera-wrap">
            <video id="kioskVideo" autoplay muted playsinline></video>
            <canvas id="kioskOverlay"></canvas>
            <canvas id="kioskCapture" hidden></canvas>
          </div>

          <div class="kiosk-feedback-grid">
            <div class="feedback-chip" id="feedbackFace">No face detected</div>
            <div class="feedback-chip" id="feedbackLighting">Lighting check pending</div>
            <div class="feedback-chip" id="feedbackMultiFace">Single face required</div>
            <div class="feedback-chip" id="feedbackLiveness">Liveness check pending</div>
            <div class="feedback-chip" id="feedbackConfidence">Confidence: --</div>
          </div>

          <div class="kiosk-actions">
            <button id="startKioskCameraBtn" class="btn neutral" type="button">Start Camera</button>
            <button id="verifyIdentityBtn" class="btn success" type="button" disabled>Verify Identity</button>
            <button id="confirmAttendanceBtn" class="btn primary" type="button" disabled>
              Confirm Attendance
            </button>
            <button id="resetKioskBtn" class="btn neutral" type="button">Reset</button>
          </div>

          <div id="kioskStatus" class="kiosk-status info">System ready. Start camera to begin.</div>

          <div id="kioskCandidate" class="kiosk-candidate hidden">
            <h3>Matched Employee</h3>
            <p id="candidateName">-</p>
            <p id="candidateMeta">-</p>
          </div>
        </article>

        <aside class="kiosk-log-panel">
          <div class="panel-head compact">
            <h3>Today’s Attendance Log</h3>
          </div>
          <div id="todayLogList" class="today-log-list"></div>
        </aside>
      </section>
    </main>

    <script src="https://cdn.jsdelivr.net/npm/face-api.js@0.22.2/dist/face-api.min.js"></script>
    <script src="/public/js/attendance-mode.js"></script>
  </body>
</html>

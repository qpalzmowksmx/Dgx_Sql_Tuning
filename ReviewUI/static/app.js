"use strict";

const state = {
  runs: [],
  run: null,
  selectedRun: null,
  selectedQuery: null,
  detail: null,
  activeTab: "overview",
  search: "",
  refreshing: false,
};

const tabs = [
  ["overview", "한눈에 보기"],
  ["sql", "SQL 비교"],
  ["writer", "Writer 근거"],
  ["critics", "Critic 검토"],
  ["oracle", "Oracle 검증"],
  ["benchmark", "성능 비교"],
  ["context", "DB 정보"],
  ["raw", "원본 JSON"],
];

const $ = (selector) => document.querySelector(selector);

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function displayValue(value, fallback = "—") {
  if (value === null || value === undefined || value === "") return fallback;
  if (typeof value === "boolean") return value ? "통과" : "실패";
  return String(value);
}

function statusTone(status) {
  const normalized = String(status || "UNKNOWN").toUpperCase();
  if (["SUCCESS", "PASSED", "APPROVED", "TRUE"].includes(normalized)) return "success";
  if (["FAILED", "REJECTED", "FALSE", "HIGH"].includes(normalized)) return "danger";
  if (["PARTIAL", "RETRY", "WAIT_USER", "MEDIUM"].includes(normalized)) return "warning";
  if (["RUNNING", "ANALYZING", "TUNING", "VERIFYING"].includes(normalized)) return "info";
  return "neutral";
}

function badge(label, tone) {
  return `<span class="badge ${escapeHtml(tone || statusTone(label))}">${escapeHtml(label)}</span>`;
}

function iconResult(value) {
  if (value === true) return '<span class="gate pass">✓ 통과</span>';
  if (value === false) return '<span class="gate fail">× 실패</span>';
  return '<span class="gate pending">· 미확인</span>';
}

function formatDate(value) {
  if (!value) return "기록 없음";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return new Intl.DateTimeFormat("ko-KR", {
    dateStyle: "medium",
    timeStyle: "medium",
  }).format(date);
}

function formatNumber(value, digits = 2) {
  const number = Number(value);
  if (!Number.isFinite(number)) return displayValue(value);
  return new Intl.NumberFormat("ko-KR", { maximumFractionDigits: digits }).format(number);
}

async function fetchJson(url) {
  const response = await fetch(url, { cache: "no-store" });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || `요청 실패 (${response.status})`);
  return data;
}

function showError(message) {
  const element = $("#global-error");
  element.textContent = message;
  element.classList.toggle("hidden", !message);
}

function showToast(message) {
  const toast = $("#toast");
  toast.textContent = message;
  toast.classList.remove("hidden");
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => toast.classList.add("hidden"), 1800);
}

async function loadRuns({ preserve = true } = {}) {
  const payload = await fetchJson("/api/runs");
  state.runs = payload.runs || [];
  if (!preserve || !state.runs.some((run) => run.id === state.selectedRun)) {
    state.selectedRun = state.runs[0]?.id || null;
    state.selectedQuery = null;
    state.detail = null;
  }
  renderRuns();
  if (state.selectedRun) {
    await loadRun(state.selectedRun, { preserveQuery: preserve });
  } else {
    renderEmpty();
  }
}

async function loadRun(runId, { preserveQuery = false } = {}) {
  state.selectedRun = runId;
  const run = await fetchJson(`/api/run?run=${encodeURIComponent(runId)}`);
  if (state.selectedRun !== runId) return;
  state.run = run;
  const jobs = run.jobs || [];
  if (!preserveQuery || !jobs.some((job) => job.name === state.selectedQuery)) {
    state.selectedQuery = jobs[0]?.name || null;
    state.detail = null;
  }
  renderRuns();
  renderRun();
  if (state.selectedQuery) await loadQuery(state.selectedQuery);
}

async function loadQuery(name) {
  state.selectedQuery = name;
  const runId = state.selectedRun;
  const detail = await fetchJson(
    `/api/query?run=${encodeURIComponent(runId)}&name=${encodeURIComponent(name)}`,
  );
  if (state.selectedRun !== runId || state.selectedQuery !== name) return;
  state.detail = detail;
  renderQueryList();
  renderDetail();
}

function renderRuns() {
  const target = $("#run-list");
  if (!state.runs.length) {
    target.innerHTML = '<p class="muted compact">표시할 기록이 없습니다.</p>';
    return;
  }
  target.innerHTML = state.runs
    .map(
      (run) => `
        <button class="run-item ${run.id === state.selectedRun ? "active" : ""}" data-run="${escapeHtml(run.id)}" type="button">
          <span class="run-row"><strong>${escapeHtml(run.label)}</strong>${badge(run.result)}</span>
          <span class="run-meta">${escapeHtml(formatDate(run.updated_at))}</span>
          <span class="run-meta">${formatNumber(run.job_count, 0)}개 쿼리 · ${escapeHtml(run.mode || "진행 중")}</span>
        </button>`,
    )
    .join("");
  target.querySelectorAll("[data-run]").forEach((button) => {
    button.addEventListener("click", () => {
      loadRun(button.dataset.run).catch((error) => showError(error.message));
    });
  });
}

function renderEmpty() {
  $("#run-title").textContent = "검토 결과";
  $("#run-meta").textContent = "실행 결과가 생성되면 자동으로 표시됩니다.";
  $("#summary-cards").innerHTML = "";
  $("#query-list").innerHTML = "";
  $("#detail-section").classList.add("hidden");
  $("#empty-state").classList.remove("hidden");
}

function renderRun() {
  const run = state.run;
  if (!run) return renderEmpty();
  $("#empty-state").classList.add("hidden");
  $("#run-title").textContent = run.label;
  const summary = run.summary || {};
  $("#run-meta").textContent = `${formatDate(run.updated_at)} · ${summary.mode || "진행 중"} · ${summary.tuner || "writer 미확인"}`;
  showError((run.errors || []).join(" · "));

  const jobs = run.jobs || [];
  const successes = jobs.filter((job) => job.status === "SUCCESS").length;
  const reviews = jobs.filter((job) => job.status === "FAILED" || job.improved === false).length;
  const oraclePassed = jobs.filter((job) => job.oracle_validation_passed === true).length;
  const criticPassed = jobs.filter((job) => job.critic_approved === true).length;
  $("#summary-cards").innerHTML = [
    summaryCard("전체 결과", badge(run.result), `${jobs.length}개 쿼리`),
    summaryCard("최종 통과", `<strong class="metric success-text">${successes}</strong>`, `수동 검토 ${reviews}`),
    summaryCard("Critic 승인", `<strong class="metric">${criticPassed}</strong>`, `전체 ${jobs.length}`),
    summaryCard("Oracle 검증", `<strong class="metric">${oraclePassed}</strong>`, `전체 ${jobs.length}`),
  ].join("");
  renderQueryList();
}

function summaryCard(label, value, sub) {
  return `<article class="summary-card"><span>${escapeHtml(label)}</span><div>${value}</div><small>${escapeHtml(sub)}</small></article>`;
}

function renderQueryList() {
  const target = $("#query-list");
  const term = state.search.trim().toLowerCase();
  const jobs = (state.run?.jobs || []).filter((job) => {
    const haystack = [job.name, job.sql_id, ...(job.tables || [])].join(" ").toLowerCase();
    return !term || haystack.includes(term);
  });
  if (!jobs.length) {
    target.innerHTML = '<p class="no-result">검색 조건에 맞는 쿼리가 없습니다.</p>';
    return;
  }
  target.innerHTML = jobs
    .map((job) => {
      const gates = [
        `Critic ${iconResult(job.critic_approved)}`,
        `Oracle ${iconResult(job.oracle_validation_passed)}`,
        `개선 ${iconResult(job.improved)}`,
      ].join("");
      return `
        <button class="query-row ${job.name === state.selectedQuery ? "active" : ""}" data-query="${escapeHtml(job.name)}" type="button">
          <span class="query-identity">
            <span class="query-title"><strong>${escapeHtml(job.sql_id || job.name)}</strong>${badge(job.status)}</span>
            <small>${escapeHtml(job.name)}${job.plan_hash_value ? ` · Plan ${escapeHtml(job.plan_hash_value)}` : ""}</small>
            <span class="table-tags">${(job.tables || []).slice(0, 4).map((table) => `<i>${escapeHtml(table)}</i>`).join("")}</span>
          </span>
          <span class="gate-list">${gates}</span>
          <span class="query-message">${escapeHtml(job.message || (job.risk ? `Critic risk: ${job.risk}` : "검토 상세 보기"))}</span>
        </button>`;
    })
    .join("");
  target.querySelectorAll("[data-query]").forEach((button) => {
    button.addEventListener("click", () => loadQuery(button.dataset.query).catch((error) => showError(error.message)));
  });
}

function renderDetail() {
  const detail = state.detail;
  const section = $("#detail-section");
  if (!detail) {
    section.classList.add("hidden");
    return;
  }
  section.classList.remove("hidden");
  const job = detail.job || {};
  $("#detail-header").innerHTML = `
    <div>
      <p class="eyebrow">QUERY REVIEW</p>
      <h2>${escapeHtml(job.sql_id || detail.name)}</h2>
      <p class="muted">${escapeHtml(detail.name)} · 재시도 ${formatNumber(job.retry_count || 0, 0)}회</p>
    </div>
    <div class="detail-gates">
      ${badge(job.status || "UNKNOWN")}
      ${job.benchmark?.critic_approved === undefined ? "" : iconResult(job.benchmark.critic_approved)}
      ${job.benchmark?.oracle_validation_passed === undefined ? "" : iconResult(job.benchmark.oracle_validation_passed)}
    </div>`;
  $("#detail-tabs").innerHTML = tabs
    .map(([id, label]) => `<button type="button" data-tab="${id}" class="${id === state.activeTab ? "active" : ""}">${label}</button>`)
    .join("");
  $("#detail-tabs").querySelectorAll("[data-tab]").forEach((button) => {
    button.addEventListener("click", () => {
      state.activeTab = button.dataset.tab;
      renderDetail();
    });
  });

  const renderers = {
    overview: renderOverview,
    sql: renderSql,
    writer: renderWriter,
    critics: renderCritics,
    oracle: () => renderObjectReport("Oracle 검증 결과", detail.validation, oracleHighlights(detail.validation)),
    benchmark: () => renderObjectReport("성능 비교 결과", detail.benchmark, benchmarkHighlights(detail.benchmark)),
    context: renderContext,
    raw: renderRaw,
  };
  $("#detail-content").innerHTML = renderers[state.activeTab]();
  bindCopyButtons();
}

function renderOverview() {
  const detail = state.detail;
  const writer = detail.writer || {};
  const critics = Object.entries(detail.critics || {});
  const blocking = critics.flatMap(([, report]) => report.block || []);
  const semantic = critics.flatMap(([, report]) => report.sem || []);
  const errors = detail.errors || [];
  return `
    ${errors.length ? `<div class="notice warning"><strong>일부 자료를 읽지 못했습니다.</strong><ul>${errors.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul></div>` : ""}
    <div class="overview-grid">
      <article class="panel verdict-panel">
        <span class="panel-label">최종 판정</span>
        <div class="verdict">${badge(detail.job.status || "UNKNOWN")}</div>
        <div class="gate-summary">
          <div><span>Writer 결과</span>${writer.sql ? iconResult(true) : iconResult(null)}</div>
          <div><span>Critic 승인</span>${iconResult(detail.benchmark?.critic_approved)}</div>
          <div><span>Oracle 검증</span>${iconResult(detail.benchmark?.oracle_validation_passed ?? detail.validation?.passed)}</div>
          <div><span>성능 개선</span>${iconResult(detail.benchmark?.improved)}</div>
        </div>
      </article>
      <article class="panel">
        <span class="panel-label">Writer가 바꾼 이유</span>
        ${renderList(writer.why, "기록된 변경 이유가 없습니다.")}
      </article>
      <article class="panel ${blocking.length ? "panel-danger" : ""}">
        <span class="panel-label">차단 사유</span>
        ${renderList(blocking, "Critic이 보고한 차단 사유가 없습니다.")}
      </article>
      <article class="panel ${semantic.length ? "panel-warning" : ""}">
        <span class="panel-label">의미 동일성 위험</span>
        ${renderList(semantic, "보고된 의미 변경 위험이 없습니다.")}
      </article>
    </div>
    <article class="panel message-panel">
      <span class="panel-label">검토 메모</span>
      <p>${escapeHtml(detail.benchmark?.message || critics.map(([, report]) => report.sum).filter(Boolean).join(" · ") || "추가 메모가 없습니다.")}</p>
    </article>`;
}

function renderList(items, emptyMessage) {
  if (!Array.isArray(items) || !items.length) return `<p class="muted">${escapeHtml(emptyMessage)}</p>`;
  return `<ul class="plain-list">${items.map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>`;
}

function diffLines(original, tuned) {
  const left = String(original || "").split("\n");
  const right = String(tuned || "").split("\n");
  if (left.length > 350 || right.length > 350) {
    const length = Math.max(left.length, right.length);
    return Array.from({ length }, (_, index) => [left[index] ?? null, right[index] ?? null, left[index] === right[index] ? "same" : "changed"]);
  }
  const matrix = Array.from({ length: left.length + 1 }, () => new Uint16Array(right.length + 1));
  for (let i = left.length - 1; i >= 0; i -= 1) {
    for (let j = right.length - 1; j >= 0; j -= 1) {
      matrix[i][j] = left[i] === right[j] ? matrix[i + 1][j + 1] + 1 : Math.max(matrix[i + 1][j], matrix[i][j + 1]);
    }
  }
  const rows = [];
  let i = 0;
  let j = 0;
  while (i < left.length || j < right.length) {
    if (i < left.length && j < right.length && left[i] === right[j]) {
      rows.push([left[i], right[j], "same"]); i += 1; j += 1;
    } else if (j < right.length && (i === left.length || matrix[i][j + 1] >= matrix[i + 1][j])) {
      rows.push([null, right[j], "added"]); j += 1;
    } else {
      rows.push([left[i], null, "removed"]); i += 1;
    }
  }
  return rows;
}

function renderSql() {
  const detail = state.detail;
  const originalMissing = !String(detail.original_sql || "").trim();
  const tunedMissing = !String(detail.tuned_sql || "").trim();
  const rows = diffLines(detail.original_sql, detail.tuned_sql);
  let leftNumber = 0;
  let rightNumber = 0;
  const paired = rows.map(([left, right, kind]) => {
    if (left !== null) leftNumber += 1;
    if (right !== null) rightNumber += 1;
    return { left, right, kind, leftNumber: left === null ? "" : leftNumber, rightNumber: right === null ? "" : rightNumber };
  });
  return `
    ${originalMissing ? '<div class="notice error"><strong>원본 SQL을 읽지 못했습니다.</strong> 현재 실행의 tmp 디렉터리와 원본 파일 권한을 확인하세요.</div>' : ""}
    ${tunedMissing ? '<div class="notice warning"><strong>튜닝 SQL이 아직 없습니다.</strong> Writer 단계가 끝난 뒤 자동으로 표시됩니다.</div>' : ""}
    <div class="sql-toolbar">
      <div><strong>줄 단위 비교</strong><span class="muted">초록색은 추가, 붉은색은 제거된 줄입니다.</span></div>
      <div><button class="button secondary copy-button" data-copy="tuned" type="button">튜닝 SQL 복사</button></div>
    </div>
    <div class="sql-diff">
      <section class="code-panel"><header><strong>원본 SQL</strong><span>${String(detail.original_sql || "").split("\n").length} lines</span></header><div class="code-lines">${paired.map((row) => codeLine(row.leftNumber, row.left, row.kind === "removed" ? "removed" : row.kind === "added" ? "blank" : "")).join("")}</div></section>
      <section class="code-panel"><header><strong>튜닝 SQL</strong><span>${String(detail.tuned_sql || "").split("\n").length} lines</span></header><div class="code-lines">${paired.map((row) => codeLine(row.rightNumber, row.right, row.kind === "added" ? "added" : row.kind === "removed" ? "blank" : "")).join("")}</div></section>
    </div>`;
}

function codeLine(number, text, tone) {
  return `<div class="code-line ${tone}"><span>${number}</span><code>${text === null ? "&nbsp;" : escapeHtml(text) || "&nbsp;"}</code></div>`;
}

function renderWriter() {
  const writer = state.detail.writer || {};
  return `<div class="three-column">
    <article class="panel"><span class="panel-label">변경 이유 · why</span>${renderList(writer.why, "없음")}</article>
    <article class="panel panel-warning"><span class="panel-label">예상 위험 · risk</span>${renderList(writer.risk, "Writer가 보고한 위험이 없습니다.")}</article>
    <article class="panel"><span class="panel-label">확인 항목 · check</span>${renderList(writer.check, "없음")}</article>
  </div>
  <article class="panel json-meta"><span class="panel-label">생성 정보</span>${renderKeyValues(state.detail.tuning_meta || {})}</article>`;
}

function renderCritics() {
  const critics = Object.entries(state.detail.critics || {});
  if (!critics.length) return '<div class="empty-inline">Critic 검토 결과가 아직 없습니다.</div>';
  return `<div class="critic-grid">${critics.map(([name, report]) => `
    <article class="panel critic-card ${report.ok === false ? "panel-danger" : ""}">
      <header><div><span class="panel-label">${escapeHtml(name)}</span><h3>${escapeHtml(report.sum || "요약 없음")}</h3></div><div>${iconResult(report.ok)} ${report.risk ? badge(`${report.risk} risk`) : ""}</div></header>
      <div class="critic-sections">
        <section><strong>차단 사유</strong>${renderList(report.block, "없음")}</section>
        <section><strong>수정 제안</strong>${renderList(report.fix, "없음")}</section>
        <section><strong>의미 위험</strong>${renderList(report.sem, "없음")}</section>
        <section><strong>벤치마크 의견</strong><p>${escapeHtml(report.bench || "없음")}</p></section>
      </div>
    </article>`).join("")}</div>`;
}

function oracleHighlights(report = {}) {
  const sample = report.sample_compare || {};
  const original = sample.original || {};
  const tuned = sample.tuned || {};
  const checks = sample.checks || {};
  return [
    ["전체 판정", report.passed],
    ["실패 단계", report.failed_stage],
    ["검증 시각", report.checked_at],
    ["원본 Parse", report.steps?.original?.parse?.ok],
    ["원본 Explain", report.steps?.original?.explain?.ok],
    ["튜닝 Parse", report.steps?.tuned?.parse?.ok],
    ["튜닝 Explain", report.steps?.tuned?.explain?.ok],
    ["동일 스냅샷", report.snapshot?.same_snapshot],
    ["실행 결과 동일", sample.passed],
    ["컬럼 동일", checks.columns_match],
    ["행 수 동일", checks.limited_row_count_match],
    ["결과 해시 동일", checks.unordered_hash_match],
    ["원본 행 수", original.row_count],
    ["튜닝 행 수", tuned.row_count],
    ["원본 실행 시간", original.elapsed_ms === undefined ? null : `${formatNumber(original.elapsed_ms, 4)} ms`],
    ["튜닝 실행 시간", tuned.elapsed_ms === undefined ? null : `${formatNumber(tuned.elapsed_ms, 4)} ms`],
    ["전체 결과 비교", checks.complete_results],
    ["표본 행 제한", report.row_limit],
    ["메시지", report.message],
  ];
}

function benchmarkHighlights(report = {}) {
  return [
    ["성능 개선", report.improved],
    ["개선율", report.improvement_pct !== undefined ? `${formatNumber(report.improvement_pct)}%` : null],
    ["원본 시간", nestedMetric(report.original) || firstMetric(report, ["original_ms", "original_elapsed_ms", "baseline_ms"])],
    ["튜닝 시간", nestedMetric(report.tuned) || firstMetric(report, ["tuned_ms", "tuned_elapsed_ms", "candidate_ms"])],
    ["검토 필요", report.needs_review],
    ["메시지", report.message],
  ];
}

function nestedMetric(metrics) {
  if (!metrics || typeof metrics !== "object") return null;
  const value = metrics.elapsed_ms ?? metrics.avg_elapsed_ms;
  return value === undefined || value === null ? null : `${formatNumber(value)} ms`;
}

function firstMetric(report, keys) {
  for (const key of keys) if (report[key] !== undefined && report[key] !== null) return `${formatNumber(report[key])} ms`;
  return null;
}

function renderObjectReport(title, report, highlights) {
  const hasReport = report && typeof report === "object" && Object.keys(report).length;
  if (!hasReport) return `<div class="empty-inline">${escapeHtml(title)}가 아직 없습니다.</div>`;
  return `<div class="report-layout">
    <article class="panel"><span class="panel-label">${escapeHtml(title)}</span><div class="highlight-list">${highlights.filter(([, value]) => value !== undefined && value !== null && value !== "").map(([key, value]) => `<div><span>${escapeHtml(key)}</span>${typeof value === "boolean" ? iconResult(value) : `<strong>${escapeHtml(displayValue(value))}</strong>`}</div>`).join("")}</div></article>
    <article class="panel"><span class="panel-label">상세 데이터</span><pre class="json-view">${escapeHtml(JSON.stringify(report, null, 2))}</pre></article>
  </div>`;
}

function renderContext() {
  const context = state.detail.db_context || {};
  const objects = Array.isArray(context.objects) ? context.objects : [];
  const unresolved = context.unresolved_objects || context.unresolved || [];
  const captured = context.catalog?.captured_at || context.query_context?.captured_at || context.captured_at || context.capture_time || context.as_of;
  return `<div class="context-summary">
    ${summaryCard("선별 객체", `<strong class="metric">${objects.length}</strong>`, "writer/critic 공통 입력")}
    ${summaryCard("미해결 객체", `<strong class="metric ${unresolved.length ? "danger-text" : ""}">${unresolved.length}</strong>`, "확인 필요")}
    ${summaryCard("수집 시각", `<strong class="small-metric">${escapeHtml(captured ? formatDate(captured) : "미기록")}</strong>`, "동적 DB 정보")}
  </div>
  ${objects.length ? `<div class="object-grid">${objects.map(renderDbObject).join("")}</div>` : '<div class="empty-inline">이 쿼리에 주입된 DB 객체 정보가 없습니다.</div>'}
  ${unresolved.length ? `<article class="panel panel-warning"><span class="panel-label">미해결 객체</span>${renderList(unresolved, "없음")}</article>` : ""}
  <details class="raw-details"><summary>DB 컨텍스트 JSON 보기</summary><pre class="json-view">${escapeHtml(JSON.stringify(context, null, 2))}</pre></details>`;
}

function renderDbObject(item) {
  const name = [item.owner, item.name].filter(Boolean).join(".") || "이름 없음";
  const stats = item.statistics || item.stats || {};
  return `<article class="panel object-card">
    <header><div><span class="panel-label">${escapeHtml(item.object_type || item.type || "OBJECT")}</span><h3>${escapeHtml(name)}</h3></div></header>
    <div class="object-facts">
      <span>행 수 <strong>${escapeHtml(displayValue(stats.num_rows ?? item.num_rows))}</strong></span>
      <span>통계 시각 <strong>${escapeHtml(displayValue(stats.last_analyzed ?? item.last_analyzed))}</strong></span>
      <span>의존 객체 <strong>${Array.isArray(item.dependencies) ? item.dependencies.length : 0}</strong></span>
    </div>
    ${(item.dependencies || []).length ? `<p class="dependencies">${item.dependencies.map((value) => `<i>${escapeHtml(value)}</i>`).join("")}</p>` : ""}
  </article>`;
}

function renderRaw() {
  const raw = state.detail.raw || {};
  return `<div class="raw-toolbar"><p class="muted">기계 간 계약의 원본입니다. 화면 표시에 누락이 의심될 때 확인하세요.</p><button class="button secondary copy-button" data-copy="json" type="button">전체 JSON 복사</button></div>
    ${Object.entries(raw).map(([name, payload]) => `<details class="raw-details"><summary>${escapeHtml(name)}</summary><pre class="json-view">${escapeHtml(JSON.stringify(payload, null, 2))}</pre></details>`).join("")}`;
}

function renderKeyValues(object) {
  const entries = Object.entries(object || {});
  if (!entries.length) return '<p class="muted">기록 없음</p>';
  return `<dl class="key-values">${entries.map(([key, value]) => `<div><dt>${escapeHtml(key)}</dt><dd>${escapeHtml(typeof value === "object" ? JSON.stringify(value) : displayValue(value))}</dd></div>`).join("")}</dl>`;
}

async function copyText(content) {
  const text = String(content || "");
  if (!text) throw new Error("복사할 내용이 없습니다.");
  if (navigator.clipboard && window.isSecureContext) {
    try {
      await navigator.clipboard.writeText(text);
      return;
    } catch {
      // Some browsers expose the API but deny it without an explicit permission.
    }
  }

  // `execCommand("copy")` can return true without transferring textarea
  // contents on some Firefox/Linux builds. Supplying the copy event payload
  // explicitly keeps the fallback reliable in those browsers.
  let eventCopied = false;
  const handleCopy = (event) => {
    if (!event.clipboardData) return;
    event.clipboardData.setData("text/plain", text);
    event.preventDefault();
    eventCopied = true;
  };
  document.addEventListener("copy", handleCopy, { once: true });
  const eventCommandCopied = document.execCommand("copy");
  document.removeEventListener("copy", handleCopy);
  if (eventCommandCopied && eventCopied) return;

  const textarea = document.createElement("textarea");
  textarea.value = text;
  textarea.setAttribute("aria-hidden", "true");
  textarea.style.position = "fixed";
  textarea.style.opacity = "0";
  textarea.style.pointerEvents = "none";
  textarea.style.top = "0";
  document.body.appendChild(textarea);
  textarea.focus();
  textarea.select();
  textarea.setSelectionRange(0, textarea.value.length);
  const copied = document.execCommand("copy");
  textarea.remove();
  if (!copied) throw new Error("브라우저가 복사를 허용하지 않았습니다.");
}

function bindCopyButtons() {
  $("#detail-content").querySelectorAll("[data-copy]").forEach((button) => {
    button.addEventListener("click", async () => {
      const content = button.dataset.copy === "tuned" ? state.detail.tuned_sql : JSON.stringify(state.detail.raw, null, 2);
      try {
        await copyText(content);
        showToast("클립보드에 복사했습니다.");
      } catch (error) {
        showToast(error.message || "복사하지 못했습니다.");
      }
    });
  });
}

function captureScrollState() {
  return {
    pageX: window.scrollX,
    pageY: window.scrollY,
    sidebar: $(".sidebar")?.scrollTop || 0,
    codePanels: Array.from(document.querySelectorAll(".code-lines, .json-view"))
      .map((element) => ({ left: element.scrollLeft, top: element.scrollTop })),
  };
}

function restoreScrollState(snapshot) {
  const root = document.documentElement;
  const previousBehavior = root.style.scrollBehavior;
  root.style.scrollBehavior = "auto";
  window.scrollTo(snapshot.pageX, snapshot.pageY);
  const sidebar = $(".sidebar");
  if (sidebar) sidebar.scrollTop = snapshot.sidebar;
  document.querySelectorAll(".code-lines, .json-view").forEach((element, index) => {
    const saved = snapshot.codePanels[index];
    if (saved) {
      element.scrollLeft = saved.left;
      element.scrollTop = saved.top;
    }
  });
  root.style.scrollBehavior = previousBehavior;
}

async function refresh({ quiet = false } = {}) {
  if (state.refreshing) return;
  state.refreshing = true;
  const scrollState = quiet ? captureScrollState() : null;
  try {
    showError("");
    await loadRuns({ preserve: true });
    if (!quiet) showToast("최신 결과를 불러왔습니다.");
  } catch (error) {
    showError(`결과를 불러오지 못했습니다: ${error.message}`);
  } finally {
    if (scrollState) {
      requestAnimationFrame(() => restoreScrollState(scrollState));
    }
    state.refreshing = false;
  }
}

$("#refresh-button").addEventListener("click", () => refresh());
$("#query-search").addEventListener("input", (event) => {
  state.search = event.target.value;
  renderQueryList();
});

refresh({ quiet: true });
setInterval(() => refresh({ quiet: true }), 5000);

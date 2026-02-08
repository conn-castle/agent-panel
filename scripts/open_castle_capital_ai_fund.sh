#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="Castle Capital AI Fund"
PROJECT_ID="castle-capital-ai-fund"
WORKSPACE_NAME="ap-${PROJECT_ID}"
WINDOW_TOKEN="AP:${PROJECT_ID}"
CONFIG_PATH="${HOME}/.config/agent-panel/config.toml"
VSCODE_WORKSPACE_DIR="${HOME}/.local/state/agent-panel/vscode"
VSCODE_WORKSPACE_PATH="${VSCODE_WORKSPACE_DIR}/${PROJECT_ID}.code-workspace"

AEROSPACE_WINDOW_FORMAT="%{window-id}||%{app-bundle-id}||%{workspace}||%{window-title}"
AEROSPACE_WORKSPACE_FORMAT="%{workspace}"

POLL_TIMEOUT_SECONDS=10
POLL_INTERVAL_SECONDS=0.1

VSCODE_BUNDLE_ID="com.microsoft.VSCode"
CHROME_BUNDLE_ID="com.google.Chrome"

FOCUS_TRACE_SAMPLE_COUNT=40
FOCUS_TRACE_INTERVAL_SECONDS=0.05
FOCUS_TRACE_RESULT=""

log() {
  printf "[open-project] %s\n" "$*"
}

fatal() {
  printf "[open-project] error: %s\n" "$*" >&2
  exit 1
}

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    fatal "Missing required command: ${command_name}"
  fi
}

extract_project_path() {
  if [[ ! -f "${CONFIG_PATH}" ]]; then
    fatal "Config file not found at ${CONFIG_PATH}"
  fi

  awk -v target_name="${PROJECT_NAME}" '
    /^\[\[project\]\]/ {
      in_project = 1
      matched_name = 0
      next
    }

    in_project && /^[[:space:]]*name[[:space:]]*=/ {
      line = $0
      sub(/^[[:space:]]*name[[:space:]]*=[[:space:]]*"/, "", line)
      sub(/"[[:space:]]*$/, "", line)
      matched_name = (line == target_name)
      next
    }

    in_project && matched_name && /^[[:space:]]*path[[:space:]]*=/ {
      line = $0
      sub(/^[[:space:]]*path[[:space:]]*=[[:space:]]*"/, "", line)
      sub(/"[[:space:]]*$/, "", line)
      print line
      exit
    }
  ' "${CONFIG_PATH}"
}

list_windows_for_app() {
  local app_bundle_id="$1"

  # Prefer searching across all monitors/spaces. If that fails (older AeroSpace builds),
  # fall back to the focused monitor.
  aerospace list-windows \
    --app-bundle-id "${app_bundle_id}" \
    --format "${AEROSPACE_WINDOW_FORMAT}" 2>/dev/null \
    || aerospace list-windows \
      --monitor focused \
      --app-bundle-id "${app_bundle_id}" \
      --format "${AEROSPACE_WINDOW_FORMAT}"
}

find_window_by_token() {
  local app_bundle_id="$1"
  list_windows_for_app "${app_bundle_id}" \
    | awk -F '\\|\\|' -v token="${WINDOW_TOKEN}" '$4 ~ token { print $0; exit }'
}

extract_field() {
  local raw_line="$1"
  local field_index="$2"
  awk -F '\\|\\|' -v idx="${field_index}" '{ print $idx }' <<<"${raw_line}"
}

normalize_trace_value() {
  local value="$1"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  value="${value//$'\t'/ }"
  printf "%s" "${value}"
}

poll_for_window_by_token() {
  local app_bundle_id="$1"
  local started_at
  started_at="$(date +%s)"

  while true; do
    local found_window
    found_window="$(find_window_by_token "${app_bundle_id}" || true)"
    if [[ -n "${found_window}" ]]; then
      printf "%s\n" "${found_window}"
      return 0
    fi

    local now
    now="$(date +%s)"
    if (( now - started_at >= POLL_TIMEOUT_SECONDS )); then
      return 1
    fi

    sleep "${POLL_INTERVAL_SECONDS}"
  done
}

launch_chrome_window() {
  osascript <<OSA
tell application "Google Chrome"
  set newWindow to make new window
  set URL of active tab of newWindow to "https://example.com"
  set given name of newWindow to "${WINDOW_TOKEN}"
end tell
OSA
}

write_vscode_workspace_file() {
  local project_path="$1"
  mkdir -p "${VSCODE_WORKSPACE_DIR}"
  cat >"${VSCODE_WORKSPACE_PATH}" <<EOF
{
  "folders": [
    {
      "path": "${project_path}"
    }
  ],
  "settings": {
    "window.title": "${WINDOW_TOKEN} - \${dirty}\${activeEditorShort}\${separator}\${rootName}\${separator}\${appName}"
  }
}
EOF
}

launch_vscode_window() {
  local project_path="$1"
  write_vscode_workspace_file "${project_path}"
  code --new-window "${VSCODE_WORKSPACE_PATH}"
}

is_window_in_workspace() {
  local window_id="$1"
  local workspace_windows="$2"
  awk -F '\\|\\|' -v expected_window_id="${window_id}" '
    $1 == expected_window_id { found = 1 }
    END { exit(found ? 0 : 1) }
  ' <<<"${workspace_windows}"
}

poll_for_workspace_windows() {
  local chrome_window_id="$1"
  local ide_window_id="$2"
  local started_at
  started_at="$(date +%s)"

  while true; do
    local windows
    windows="$(aerospace list-windows --workspace "${WORKSPACE_NAME}" --format "${AEROSPACE_WINDOW_FORMAT}" 2>/dev/null || true)"

    if is_window_in_workspace "${chrome_window_id}" "${windows}" \
      && is_window_in_workspace "${ide_window_id}" "${windows}"; then
      return 0
    fi

    local now
    now="$(date +%s)"
    if (( now - started_at >= POLL_TIMEOUT_SECONDS )); then
      return 1
    fi

    sleep "${POLL_INTERVAL_SECONDS}"
  done
}

focused_workspace_name_or_placeholder() {
  local ws
  ws="$(aerospace list-workspaces --focused --format "${AEROSPACE_WORKSPACE_FORMAT}" 2>/dev/null || true)"
  if [[ -z "${ws}" ]]; then
    printf "unknown"
    return
  fi
  printf "%s" "${ws}"
}

ensure_workspace_focused() {
  local target_workspace="$1"
  local started_at
  started_at="$(date +%s)"

  while true; do
    local current_ws
    current_ws="$(focused_workspace_name_or_placeholder)"
    if [[ "${current_ws}" == "${target_workspace}" ]]; then
      return 0
    fi

    # Prefer summon-workspace for multi-monitor setups; fall back to workspace if needed.
    aerospace summon-workspace "${target_workspace}" >/dev/null 2>&1 \
      || aerospace workspace "${target_workspace}" >/dev/null 2>&1 \
      || true

    local now
    now="$(date +%s)"
    if (( now - started_at >= POLL_TIMEOUT_SECONDS )); then
      return 1
    fi

    sleep "${POLL_INTERVAL_SECONDS}"
  done
}

focused_window_line_or_placeholder() {
  local focused_window
  focused_window="$(aerospace list-windows --focused --format "${AEROSPACE_WINDOW_FORMAT}" 2>&1)" || {
    printf "[focus-trace] focused_query_error=%s\n" "$(normalize_trace_value "${focused_window}")"
    printf "unknown||unknown||unknown||unknown"
    return
  }
  if [[ -z "${focused_window}" ]]; then
    printf "[focus-trace] focused_query_error=empty_output\n"
    printf "unknown||unknown||unknown||unknown"
    return
  fi
  printf "%s" "${focused_window}"
}

frontmost_bundle_id_or_unknown() {
  local bundle_id
  bundle_id="$(
    osascript -e 'tell application "System Events" to get bundle identifier of first application process whose frontmost is true' \
      2>/dev/null \
      || true
  )"
  if [[ -z "${bundle_id}" ]]; then
    printf "unknown"
    return
  fi
  printf "%s" "${bundle_id}"
}

trace_focus_handoff() {
  local target_window_id="$1"
  local seen_target=0
  local seen_non_target_after_target=0

  log "Tracing focus handoff (${FOCUS_TRACE_SAMPLE_COUNT} samples, interval ${FOCUS_TRACE_INTERVAL_SECONDS}s)..."
  for ((sample = 1; sample <= FOCUS_TRACE_SAMPLE_COUNT; sample++)); do
    local focused_window_line
    focused_window_line="$(focused_window_line_or_placeholder)"

    local focused_window_id
    local focused_bundle_id
    local focused_title
    focused_window_id="$(extract_field "${focused_window_line}" 1)"
    focused_bundle_id="$(extract_field "${focused_window_line}" 2)"
    focused_title="$(extract_field "${focused_window_line}" 4)"

    local frontmost_bundle_id
    frontmost_bundle_id="$(frontmost_bundle_id_or_unknown)"

    printf "[focus-trace] sample=%02d focused_window_id=%s focused_bundle_id=%s frontmost_bundle_id=%s focused_title=%s\n" \
      "${sample}" \
      "$(normalize_trace_value "${focused_window_id}")" \
      "$(normalize_trace_value "${focused_bundle_id}")" \
      "$(normalize_trace_value "${frontmost_bundle_id}")" \
      "$(normalize_trace_value "${focused_title}")"

    if [[ "${focused_window_id}" == "${target_window_id}" ]]; then
      seen_target=1
    elif [[ "${seen_target}" -eq 1 ]]; then
      seen_non_target_after_target=1
    fi

    sleep "${FOCUS_TRACE_INTERVAL_SECONDS}"
  done

  if [[ "${seen_target}" -eq 0 ]]; then
    FOCUS_TRACE_RESULT="never-focused"
    log "Focus trace summary: target window never became focused."
    return
  fi

  if [[ "${seen_non_target_after_target}" -eq 1 ]]; then
    FOCUS_TRACE_RESULT="focus-lost"
    log "Focus trace summary: target window became focused and then lost focus."
    return
  fi

  FOCUS_TRACE_RESULT="stable"
  log "Focus trace summary: target window became focused and remained focused during trace."
}

move_window_to_workspace() {
  local window_id="$1"
  local target_workspace="$2"
  local focus_follows="${3:-0}"

  if [[ "${focus_follows}" -eq 1 ]]; then
    aerospace move-node-to-workspace --focus-follows-window --window-id "${window_id}" "${target_workspace}" >/dev/null 2>&1 \
      || aerospace move-node-to-workspace --window-id "${window_id}" "${target_workspace}"
    return
  fi

  aerospace move-node-to-workspace --window-id "${window_id}" "${target_workspace}"
}

poll_until_window_is_focused() {
  local target_window_id="$1"
  local started_at
  started_at="$(date +%s)"

  while true; do
    local focused_line
    focused_line="$(aerospace list-windows --focused --format "${AEROSPACE_WINDOW_FORMAT}" 2>/dev/null || true)"

    local focused_id=""
    if [[ -n "${focused_line}" ]]; then
      focused_id="$(extract_field "${focused_line}" 1)"
    fi

    if [[ "${focused_id}" == "${target_window_id}" ]]; then
      return 0
    fi

    # Re-assert focus (macOS can steal it briefly during Space/app switches).
    aerospace focus --window-id "${target_window_id}" >/dev/null 2>&1 || true

    local now
    now="$(date +%s)"
    if (( now - started_at >= POLL_TIMEOUT_SECONDS )); then
      return 1
    fi

    sleep "${POLL_INTERVAL_SECONDS}"
  done
}

main() {
  require_command aerospace
  require_command code
  require_command osascript
  require_command awk

  local project_path
  project_path="$(extract_project_path)"
  if [[ -z "${project_path}" ]]; then
    fatal "Project '${PROJECT_NAME}' not found in ${CONFIG_PATH}"
  fi
  if [[ ! -d "${project_path}" ]]; then
    fatal "Project path does not exist: ${project_path}"
  fi

  log "Project: ${PROJECT_NAME}"
  log "Project ID: ${PROJECT_ID}"
  log "Workspace: ${WORKSPACE_NAME}"
  log "Project path: ${project_path}"

  local chrome_window
  chrome_window="$(find_window_by_token "${CHROME_BUNDLE_ID}" || true)"
  if [[ -z "${chrome_window}" ]]; then
    log "Launching tagged Chrome window..."
    launch_chrome_window
    chrome_window="$(poll_for_window_by_token "${CHROME_BUNDLE_ID}")" \
      || fatal "Chrome window did not appear within timeout"
  else
    log "Using existing tagged Chrome window."
  fi

  local ide_window
  ide_window="$(find_window_by_token "${VSCODE_BUNDLE_ID}" || true)"
  if [[ -z "${ide_window}" ]]; then
    log "Launching tagged VS Code window..."
    launch_vscode_window "${project_path}"
    ide_window="$(poll_for_window_by_token "${VSCODE_BUNDLE_ID}")" \
      || fatal "VS Code window did not appear within timeout"
  else
    log "Using existing tagged VS Code window."
  fi

  local chrome_window_id chrome_workspace
  chrome_window_id="$(extract_field "${chrome_window}" 1)"
  chrome_workspace="$(extract_field "${chrome_window}" 3)"

  local ide_window_id ide_workspace
  ide_window_id="$(extract_field "${ide_window}" 1)"
  ide_workspace="$(extract_field "${ide_window}" 3)"

  # Move Chrome first (no focus follow), then move VS Code with focus follow so the final
  # focus lands in the target workspace on the IDE window.
  if [[ "${chrome_workspace}" != "${WORKSPACE_NAME}" ]]; then
    log "Moving Chrome window ${chrome_window_id} to workspace ${WORKSPACE_NAME}..."
    move_window_to_workspace "${chrome_window_id}" "${WORKSPACE_NAME}" 0
  fi

  if [[ "${ide_workspace}" != "${WORKSPACE_NAME}" ]]; then
    log "Moving VS Code window ${ide_window_id} to workspace ${WORKSPACE_NAME} (focus follows)..."
    move_window_to_workspace "${ide_window_id}" "${WORKSPACE_NAME}" 1
  fi

  log "Verifying both windows are in workspace ${WORKSPACE_NAME}..."
  poll_for_workspace_windows "${chrome_window_id}" "${ide_window_id}" \
    || fatal "Windows did not arrive in workspace ${WORKSPACE_NAME} within timeout"

  log "Ensuring workspace ${WORKSPACE_NAME} is focused on the current monitor..."
  ensure_workspace_focused "${WORKSPACE_NAME}" \
    || fatal "Workspace ${WORKSPACE_NAME} could not be focused within timeout (current=$(focused_workspace_name_or_placeholder))"

  log "Focusing VS Code window ${ide_window_id}..."
  aerospace focus --window-id "${ide_window_id}" >/dev/null 2>&1 || true

  if ! poll_until_window_is_focused "${ide_window_id}"; then
    trace_focus_handoff "${ide_window_id}"
    local current_ws
    current_ws="$(focused_workspace_name_or_placeholder)"
    local frontmost
    frontmost="$(frontmost_bundle_id_or_unknown)"
    fatal "Focus verification failed (${FOCUS_TRACE_RESULT}). Expected VS Code window ${ide_window_id} to remain focused. current_workspace=${current_ws} frontmost_bundle_id=${frontmost}"
  fi

  log "Done. VS Code window ${ide_window_id} is focused in workspace ${WORKSPACE_NAME}."
}

main "$@"

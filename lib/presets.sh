#!/usr/bin/env bash
# lib/presets.sh — first-class preset inspection and configuration workflows.
# Source after lib/common.sh. Not meant to be executed directly.
# shellcheck shell=bash
# shellcheck disable=SC2016  # jq programs use $variables that Bash must not expand

COL_PRESET_OUTPUT="table"

col_preset_fail() {
  local exit_code="$1" error_code="$2" message="$3"
  if [ "$COL_PRESET_OUTPUT" = "json" ]; then
    jq -n --arg code "$error_code" --arg message "$message" \
      '{error: {code: $code, message: $message}}' >&2
  else
    printf 'claude-openrouter: %s\n' "$message" >&2
  fi
  exit "$exit_code"
}

col_preset_group_usage() {
  cat <<'EOF'
Manage OpenRouter presets and their local launcher profiles.

Usage:
  claude-openrouter preset <command> [flags]

Commands:
  list                 List account presets and their local profile links
  view                 Show one preset and its local synchronization status
  create               Interactively or declaratively create a managed preset
  update               Interactively or declaratively update a managed preset
  apply                Synchronize local preset-backed profiles to OpenRouter

Examples:
  claude-openrouter preset list
  claude-openrouter preset view fusion
  claude-openrouter preset create team-glm
  claude-openrouter preset apply team-glm
EOF
}

col_preset_list_usage() {
  cat <<'EOF'
List OpenRouter account presets and their local profile links.

Usage:
  claude-openrouter preset list [--key-file FILE] [--config FILE] [-o table|json|name]

Flags:
      --key-file FILE   File containing OPENROUTER_API_KEY
      --config FILE     Use this configuration file
  -o, --output FORMAT   Output format: table, json, or name (default: table)
      --json            Shorthand for --output json

Examples:
  claude-openrouter preset list
  claude-openrouter preset list -o name
EOF
}

col_preset_view_usage() {
  cat <<'EOF'
Show a remote preset, its linked local profile, and synchronization status.

Usage:
  claude-openrouter preset view <profile-name> [flags]
  claude-openrouter preset view --slug <remote-slug> [flags]

Flags:
      --slug SLUG       Inspect a remote preset without requiring a linked profile
      --key-file FILE   File containing OPENROUTER_API_KEY
      --config FILE     Use this configuration file
  -o, --output FORMAT   Output format: table or json (default: table)
      --json            Shorthand for --output json

Examples:
  claude-openrouter preset view fusion
  claude-openrouter preset view --slug cc-orphan --json
EOF
}

col_preset_mutation_usage() {
  local action="$1" action_title automation_example
  case "$action" in
    create)
      action_title="Create"
      automation_example="claude-openrouter preset create team-glm --type preset --preset-slug cc-team-glm --model z-ai/glm-5.2 --provider fireworks --no-input --yes"
      ;;
    update)
      action_title="Update"
      automation_example="claude-openrouter preset update team-glm --provider fireworks --no-input --yes"
      ;;
  esac
  cat <<EOF
$action_title a managed OpenRouter preset and its local launcher profile.

Usage:
  claude-openrouter preset $action [<profile-name>] [flags]

Flags:
      --type TYPE           Profile type: preset or fusion
      --preset-slug SLUG    Remote OpenRouter preset slug
      --model SLUG          Model for a provider-pinned preset
      --provider TAG        Allowed provider tag; repeat for multiple providers
      --panel-model SLUG    Fusion panel model; repeat for multiple models
                          (replaces the whole panel — re-specify every model to keep)
      --add-panel-model SLUG
                          Add one fusion panel model, keeping the rest (update only; repeatable)
      --remove-panel-model SLUG
                          Remove one fusion panel model (update only; repeatable)
      --judge-model SLUG    Fusion judge model
      --max-tool-calls N    Fusion web-search steps per inner call, 1-16 (default 4)
      --temperature T       Fusion panel temperature, 0-2 (analyst always runs at 0)
      --max-completion-tokens N
                          Max output tokens per inner panel/analyst call
      --reasoning-effort E  Reasoning effort forwarded to panel and analyst calls
      --reasoning-max-tokens N
                          Reasoning token budget forwarded to panel and analyst calls
      --fallback SLUG       Backend used until the remote preset is verified
      --key-file FILE       File containing OPENROUTER_API_KEY
      --config FILE         Configuration file to modify
      --dry-run             Show local and remote changes without writing
  -y, --yes                 Confirm the displayed changes
      --no-input            Never prompt; fail when required input is missing
  -o, --output FORMAT       Output format: table or json (default: table)
      --json                Shorthand for --output json

Examples:
  claude-openrouter preset $action team-glm
  $automation_example
EOF
}

col_preset_apply_usage() {
  cat <<'EOF'
Synchronize local preset-backed profiles to OpenRouter.

Usage:
  claude-openrouter preset apply <profile-name> [flags]
  claude-openrouter preset apply --all [flags]

Flags:
      --all             Apply every preset-backed profile
      --key-file FILE   File containing OPENROUTER_API_KEY
      --config FILE     Use this configuration file
      --dry-run         Show which profiles would be synchronized
  -o, --output FORMAT   Output format: table or json (default: table)
      --json            Shorthand for --output json

Examples:
  claude-openrouter preset apply fusion
  claude-openrouter preset apply --all
EOF
}

col_preset_resolve_key() {
  local keyfile="${1:-}" key
  if [ -n "$keyfile" ]; then
    [ -f "$keyfile" ] || col_preset_fail 1 "key_file_not_found" "key file not found: $keyfile"
    key="$(sed -nE 's/^[[:space:]]*(export[[:space:]]+)?OPENROUTER_API_KEY=//p' "$keyfile" \
      | head -1 | tr -d '"' | tr -d "'" | tr -d '[:space:]')"
    [ -n "$key" ] || col_preset_fail 4 "auth_required" "OPENROUTER_API_KEY not found in $keyfile"
    printf '%s' "$key"
    return 0
  fi
  [ -n "${OPENROUTER_API_KEY:-}" ] \
    || col_preset_fail 4 "auth_required" "no OpenRouter key — use --key-file FILE or export OPENROUTER_API_KEY"
  printf '%s' "$OPENROUTER_API_KEY"
}

col_preset_require_valid_key() {
  local key="$1" code
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 \
    "$OR_API/key" -H "Authorization: Bearer $key" 2>/dev/null)" || true
  case "$code" in
    2*) return 0 ;;
    401|403) col_preset_fail 4 "auth_failed" "OpenRouter rejected the key" ;;
    ''|000|408|429|5*) col_preset_fail 1 "remote_unavailable" "could not reach OpenRouter to validate the key" ;;
    *) col_preset_fail 4 "auth_failed" "OpenRouter rejected the key (HTTP $code)" ;;
  esac
}

col_preset_validate_output() {
  case "$1" in
    table|json|name) ;;
    *) col_preset_fail 2 "usage" "unknown output format '$1' — use table, json, or name" ;;
  esac
}

col_preset_need_value() {
  [ "$2" -ge 2 ] || col_preset_fail 2 "usage" "$1 needs a value"
}

col_preset_load_config() {
  [ -f "$COL_CONFIG" ] || col_preset_fail 3 "not_found" "config not found: $COL_CONFIG"
  jq -e . "$COL_CONFIG" >/dev/null 2>&1 \
    || col_preset_fail 1 "invalid_config" "invalid JSON in $COL_CONFIG"
}

col_preset_profile_for_slug() {
  jq -r --arg slug "$1" '
    [.profiles | to_entries[]
      | select((.value.type == "fusion" or .value.type == "preset")
               and .value.preset_slug == $slug)
      | .key] | first // empty' "$COL_CONFIG"
}

col_preset_other_profile_for_slug() {
  jq -r --arg profile "$1" --arg slug "$2" '
    [.profiles | to_entries[]
      | select(.key != $profile and (.value.preset_slug // "") == $slug)
      | .key] | first // empty' "$COL_CONFIG"
}

col_preset_sync_status() {
  local profile="$1" remote_config="$2" type cfg_model cfg_provider
  [ -n "$profile" ] || { printf 'orphan'; return 0; }
  type="$(col_profile_type "$profile")"
  case "$type" in
    fusion)
      if jq -ne --argjson remote "$remote_config" \
        --argjson panel "$(jq -c --arg p "$profile" '.profiles[$p].panel_models' "$COL_CONFIG")" \
        --arg judge "$(col_cfg --arg p "$profile" '.profiles[$p].judge_model')" \
        --argjson knobs "$(jq -c --arg p "$profile" '.profiles[$p]
          | {max_tool_calls: .max_tool_calls, temperature: .temperature,
             max_completion_tokens: .max_completion_tokens, reasoning: .reasoning}
          | with_entries(select(.value != null))' "$COL_CONFIG")" '
          $remote.model == "openrouter/fusion"
          and $remote.tool_choice == "required"
          and ([ $remote.tools[]?
                 | select(.type == "openrouter:fusion")
                 | .parameters.analysis_models ][0] == $panel)
          and ([ $remote.tools[]?
                 | select(.type == "openrouter:fusion")
                 | .parameters.model ][0] == $judge)
          and (([$remote.tools[]?
                 | select(.type == "openrouter:fusion")
                 | .parameters][0] // {}) as $params
                | ([$knobs | to_entries[] | $params[.key] == .value] | all))' >/dev/null 2>&1; then
        printf 'in-sync'
      else
        printf 'drifted'
      fi
      ;;
    preset)
      cfg_model="$(col_cfg --arg p "$profile" '.profiles[$p].model')"
      cfg_provider="$(jq -c --arg p "$profile" '.profiles[$p].provider // {}' "$COL_CONFIG")"
      if [ "$(printf '%s' "$remote_config" | jq -r '.model // empty')" = "$cfg_model" ] \
        && col_provider_match "$(printf '%s' "$remote_config" | jq -c '.provider // {}')" "$cfg_provider"; then
        printf 'in-sync'
      else
        printf 'drifted'
      fi
      ;;
    *) printf 'unmanaged' ;;
  esac
}

col_preset_list_command() {
  local keyfile="" output="table" key
  while [ $# -gt 0 ]; do
    case "$1" in
      --key-file) col_preset_need_value "$1" "$#"; keyfile="$2"; shift 2 ;;
      --key-file=*) keyfile="${1#*=}"; shift ;;
      --config) col_preset_need_value "$1" "$#"; col_set_config "$2"; shift 2 ;;
      --config=*) col_set_config "${1#*=}"; shift ;;
      -o|--output) col_preset_need_value "$1" "$#"; output="$2"; COL_PRESET_OUTPUT="$2"; shift 2 ;;
      --output=*) output="${1#*=}"; COL_PRESET_OUTPUT="${1#*=}"; shift ;;
      --json) output="json"; COL_PRESET_OUTPUT="json"; shift ;;
      -h|--help) col_preset_list_usage; return 0 ;;
      *) COL_PRESET_OUTPUT="$output"; col_preset_fail 2 "usage" "unknown argument '$1' for 'preset list'" ;;
    esac
  done
  COL_PRESET_OUTPUT="$output"
  col_preset_validate_output "$output"
  col_require curl jq
  col_preset_load_config
  key="$(col_preset_resolve_key "$keyfile")"
  col_preset_require_valid_key "$key"
  # shellcheck disable=SC2034  # read by col_list_presets in lib/common.sh
  COL_PRESET_CONTEXT=1
  col_list_presets "$key" "$output"
}

col_preset_view_command() {
  local profile="" slug="" keyfile="" output="table" key response remote local_json status type
  while [ $# -gt 0 ]; do
    case "$1" in
      --slug) col_preset_need_value "$1" "$#"; slug="$2"; shift 2 ;;
      --slug=*) slug="${1#*=}"; shift ;;
      --key-file) col_preset_need_value "$1" "$#"; keyfile="$2"; shift 2 ;;
      --key-file=*) keyfile="${1#*=}"; shift ;;
      --config) col_preset_need_value "$1" "$#"; col_set_config "$2"; shift 2 ;;
      --config=*) col_set_config "${1#*=}"; shift ;;
      -o|--output) col_preset_need_value "$1" "$#"; output="$2"; COL_PRESET_OUTPUT="$2"; shift 2 ;;
      --output=*) output="${1#*=}"; COL_PRESET_OUTPUT="${1#*=}"; shift ;;
      --json) output="json"; COL_PRESET_OUTPUT="json"; shift ;;
      -h|--help) col_preset_view_usage; return 0 ;;
      -*) COL_PRESET_OUTPUT="$output"; col_preset_fail 2 "usage" "unknown argument '$1' for 'preset view'" ;;
      *) [ -z "$profile" ] || { COL_PRESET_OUTPUT="$output"; col_preset_fail 2 "usage" "preset view accepts one profile name"; }; profile="$1"; shift ;;
    esac
  done
  COL_PRESET_OUTPUT="$output"
  col_preset_validate_output "$output"
  [ "$output" != "name" ] || col_preset_fail 2 "usage" "preset view supports table or json output"
  [ -z "$profile" ] || [ -z "$slug" ] \
    || col_preset_fail 2 "usage" "use either a profile name or --slug, not both"
  [ -n "$profile" ] || [ -n "$slug" ] \
    || col_preset_fail 2 "usage" "preset view needs a profile name or --slug"
  col_require curl jq
  col_preset_load_config
  if [ -n "$profile" ]; then
    jq -e --arg p "$profile" '.profiles[$p] != null' "$COL_CONFIG" >/dev/null \
      || col_preset_fail 3 "not_found" "profile '$profile' not found"
    type="$(col_profile_type "$profile")"
    case "$type" in fusion|preset) ;; *) col_preset_fail 2 "usage" "profile '$profile' is type '$type' and has no OpenRouter preset" ;; esac
    slug="$(col_cfg --arg p "$profile" '.profiles[$p].preset_slug // empty')"
    [ -n "$slug" ] || col_preset_fail 1 "invalid_config" "profile '$profile' has no preset_slug"
  else
    profile="$(col_preset_profile_for_slug "$slug")"
  fi
  key="$(col_preset_resolve_key "$keyfile")"
  col_preset_require_valid_key "$key"
  if ! response="$(col_or_get "$key" "presets/$slug" 2>/dev/null)"; then
    local preset_check_rc=0
    col_preset_check "$key" "$slug" || preset_check_rc=$?
    case "$preset_check_rc" in
      1) col_preset_fail 3 "not_found" "preset '$slug' not found" ;;
      *) col_preset_fail 1 "remote_unavailable" "could not read preset '$slug' from OpenRouter" ;;
    esac
  fi
  printf '%s' "$response" | jq -e '.data.designated_version.config | type == "object"' >/dev/null 2>&1 \
    || col_preset_fail 1 "invalid_response" "OpenRouter returned an unreadable preset response for '$slug'"
  remote="$(printf '%s' "$response" | jq -c '.data.designated_version.config')"
  status="$(col_preset_sync_status "$profile" "$remote")"
  if [ -n "$profile" ]; then local_json="$(jq -c --arg p "$profile" '.profiles[$p]' "$COL_CONFIG")"; else local_json="null"; fi
  if [ "$output" = "json" ]; then
    printf '%s' "$response" | jq --arg slug "$slug" --arg profile "$profile" \
      --arg status "$status" --argjson local "$local_json" '
        {slug: $slug,
         profile: (if $profile == "" then null else $profile end),
         status: $status,
         local: $local,
         remote: .data}'
    return 0
  fi
  printf 'Preset:\n'
  printf '  slug: %s\n' "$slug"
  printf '  profile: %s\n' "${profile:-(none)}"
  printf '  status: %s\n' "$status"
  printf '  model: %s\n' "$(printf '%s' "$remote" | jq -r '.model // "(none)"')"
  if printf '%s' "$remote" | jq -e '[.tools[]? | select(.type == "openrouter:fusion")] | length > 0' >/dev/null; then
    printf '  panel: %s\n' "$(printf '%s' "$remote" | jq -r '[.tools[]? | select(.type == "openrouter:fusion").parameters.analysis_models[]?] | join(", ")')"
    printf '  judge: %s\n' "$(printf '%s' "$remote" | jq -r '[.tools[]? | select(.type == "openrouter:fusion").parameters.model][0] // "(none)"')"
    remote_knobs="$(printf '%s' "$remote" | jq -c '[.tools[]? | select(.type == "openrouter:fusion").parameters][0] | del(.analysis_models, .model)')"
    [ "$remote_knobs" = "{}" ] || printf '  knobs: %s\n' "$remote_knobs"
    printf '  tool_choice: %s\n' "$(printf '%s' "$remote" | jq -r '.tool_choice // "(none)"')"
  elif printf '%s' "$remote" | jq -e '.provider != null' >/dev/null; then
    printf '  provider: %s\n' "$(printf '%s' "$remote" | jq -c '.provider')"
  fi
  printf '  config:\n'
  printf '%s' "$remote" | jq . | sed 's/^/    /'
}

col_preset_prompt() {
  local label="$1" default="${2:-}" answer
  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$label" "$default" >&2
  else
    printf '%s: ' "$label" >&2
  fi
  IFS= read -r answer || return 130
  if [ -n "$answer" ]; then printf '%s' "$answer"; else printf '%s' "$default"; fi
}

col_preset_csv_json() {
  # Empty (or all-blank) input is a valid empty list: jq -R emits nothing when
  # it has no input lines, which would otherwise corrupt --argjson callers.
  [ -n "${1//[[:space:],]/}" ] || { printf '[]'; return 0; }
  printf '%s' "$1" | jq -Rc '
    split(",")
    | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
    | map(select(length > 0))'
}

# col_preset_apply_panel_edits <current_csv> <add_csv> <remove_csv> <profile> —
# merge additive panel edits onto the current panel and print the result CSV.
# Removals apply first, then additions (already-present additions are a no-op,
# so automation is idempotent). Fails when a removal names a model that is not
# on the panel, leaving the caller's config untouched.
col_preset_apply_panel_edits() {
  local current="$1" add="$2" remove="$3" profile="$4"
  local base_json add_json remove_json merged missing
  base_json="$(col_preset_csv_json "$current")"
  add_json="$(col_preset_csv_json "$add")"
  remove_json="$(col_preset_csv_json "$remove")"
  missing="$(jq -nc --argjson base "$base_json" --argjson remove "$remove_json" \
    '[$remove[] | select(. as $r | ($base | index($r)) == null)]')"
  [ "$(printf '%s' "$missing" | jq -r 'length')" -eq 0 ] \
    || col_preset_fail 1 "not_found" "panel of profile '$profile' has no model $(printf '%s' "$missing" | jq -r '.[0]') — nothing changed"
  merged="$(jq -nc --argjson base "$base_json" --argjson add "$add_json" --argjson remove "$remove_json" \
    '($base - $remove) as $kept | $kept + [$add[] | select(. as $a | ($kept | index($a)) == null)]')"
  printf '%s' "$merged" | jq -r 'join(",")'
}

col_preset_write_profile() {
  local profile="$1" profile_json="$2" source="$COL_CONFIG" target lock tmp
  if [ "$COL_CONFIG_SOURCE" = "example" ]; then
    target="$COL_ROOT/config/modes.json"
  else
    target="$COL_CONFIG"
  fi
  mkdir -p "$(dirname "$target")"
  lock="$target.lock"
  if ! mkdir "$lock" 2>/dev/null; then
    col_preset_fail 5 "config_locked" "configuration is locked by another process: $lock"
  fi
  tmp="$(mktemp "$target.tmp.XXXXXX")" || {
    rmdir "$lock" 2>/dev/null || true
    col_preset_fail 1 "config_write_failed" "could not create a temporary file beside $target"
  }
  trap 'rm -f "$tmp"; rmdir "$lock" 2>/dev/null || true; exit 130' INT
  trap 'rm -f "$tmp"; rmdir "$lock" 2>/dev/null || true; exit 143' TERM
  if ! jq --arg profile "$profile" --argjson value "$profile_json" \
      '.profiles[$profile] = $value' "$source" > "$tmp"; then
    rm -f "$tmp"
    rmdir "$lock" 2>/dev/null || true
    col_preset_fail 1 "config_write_failed" "could not update profile '$profile' in $source"
  fi
  if [ -f "$target" ] && ! cp -p "$target" "$target.bak"; then
    rm -f "$tmp"
    rmdir "$lock" 2>/dev/null || true
    col_preset_fail 1 "config_write_failed" "could not back up $target"
  fi
  if ! mv -f "$tmp" "$target"; then
    rm -f "$tmp"
    rmdir "$lock" 2>/dev/null || true
    col_preset_fail 1 "config_write_failed" "could not replace $target"
  fi
  trap - INT TERM
  rmdir "$lock" 2>/dev/null || true
  COL_CONFIG="$target"
  COL_CONFIG_SOURCE="explicit"
  COL_CONFIG_WRITE_RESULT="$target"
}

col_preset_print_plan() {
  local action="$1" profile="$2" profile_json="$3" target
  if [ "$COL_CONFIG_SOURCE" = "example" ]; then target="$COL_ROOT/config/modes.json"; else target="$COL_CONFIG"; fi
  if [ "$COL_PRESET_OUTPUT" = "json" ]; then
    jq -n --arg action "$action" --arg profile "$profile" --arg config "$target" \
      --argjson value "$profile_json" '
        {dry_run: true, action: $action, profile: $profile, config: $config,
         remote_preset: $value.preset_slug, value: $value}'
    return 0
  fi
  printf 'Plan:\n'
  printf '  action: %s profile %s\n' "$action" "$profile"
  printf '  config: %s\n' "$target"
  printf '  remote preset: %s\n' "$(printf '%s' "$profile_json" | jq -r '.preset_slug')"
  printf '  type: %s\n' "$(printf '%s' "$profile_json" | jq -r '.type')"
  if [ "$(printf '%s' "$profile_json" | jq -r '.type')" = "preset" ]; then
    printf '  model: %s\n' "$(printf '%s' "$profile_json" | jq -r '.model')"
    printf '  provider.only: %s\n' "$(printf '%s' "$profile_json" | jq -r '.provider.only | join(", ")')"
  else
    printf '  panel: %s\n' "$(printf '%s' "$profile_json" | jq -r '.panel_models | join(", ")')"
    printf '  judge: %s\n' "$(printf '%s' "$profile_json" | jq -r '.judge_model')"
    if [ "$(printf '%s' "$profile_json" | jq -c '{max_tool_calls, temperature, max_completion_tokens, reasoning} | with_entries(select(.value != null))')" != "{}" ]; then
      printf '  knobs: %s\n' "$(printf '%s' "$profile_json" | jq -c '{max_tool_calls, temperature, max_completion_tokens, reasoning} | with_entries(select(.value != null))')"
    fi
  fi
  printf '  fallback: %s\n' "$(printf '%s' "$profile_json" | jq -r '.fallback')"
}

col_preset_apply_profile() {
  local profile="$1" key="$2" slug output_file rc=0
  slug="$(col_cfg --arg p "$profile" '.profiles[$p].preset_slug // empty')"
  output_file="$(mktemp "${TMPDIR:-/tmp}/claude-openrouter-apply.XXXXXX")"
  CLAUDE_OPENROUTER_CONFIG="$COL_CONFIG" OPENROUTER_API_KEY="$key" \
    "$COL_ROOT/setup.sh" --profile "$profile" > "$output_file" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ "$COL_PRESET_OUTPUT" = "table" ]; then cat "$output_file" >&2; fi
    rm -f "$output_file"
    col_preset_fail 1 "apply_failed" "local configuration was saved, but preset synchronization failed; retry with 'claude-openrouter preset apply $profile'"
  fi
  if [ "$COL_PRESET_OUTPUT" = "table" ]; then cat "$output_file"; fi
  rm -f "$output_file"
  COL_PRESET_APPLIED_SLUG="$slug"
}

col_preset_mutation_command() {
  local action="$1"; shift
  local profile="" type="" preset_slug="" model="" provider_csv="" panel_csv=""
  local add_csv="" remove_csv=""
  local judge_model="" fallback="" keyfile="" output="table" _add_type=""
  local max_tool_calls="" temperature="" max_completion_tokens=""
  local reasoning_effort="" reasoning_max_tokens=""
  local type_set=0 slug_set=0 model_set=0 provider_set=0 panel_set=0 judge_set=0 fallback_set=0
  local add_set=0 remove_set=0
  local mtc_set=0 temp_set=0 mct_set=0 reff_set=0 rmt_set=0
  local dry_run=0 assume_yes=0 no_input=0 exists=0 interactive=0 current="{}" profile_json
  local current_type="" current_slug="" conflicting_profile providers_json panel_json
  local key answer applied_slug preset_check_rc
  while [ $# -gt 0 ]; do
    case "$1" in
      --type) col_preset_need_value "$1" "$#"; type="$2"; type_set=1; shift 2 ;;
      --type=*) type="${1#*=}"; type_set=1; shift ;;
      --preset-slug) col_preset_need_value "$1" "$#"; preset_slug="$2"; slug_set=1; shift 2 ;;
      --preset-slug=*) preset_slug="${1#*=}"; slug_set=1; shift ;;
      --model) col_preset_need_value "$1" "$#"; model="$2"; model_set=1; shift 2 ;;
      --model=*) model="${1#*=}"; model_set=1; shift ;;
      --provider) col_preset_need_value "$1" "$#"; if [ -n "$provider_csv" ]; then provider_csv="$provider_csv,$2"; else provider_csv="$2"; fi; provider_set=1; shift 2 ;;
      --provider=*) if [ -n "$provider_csv" ]; then provider_csv="$provider_csv,${1#*=}"; else provider_csv="${1#*=}"; fi; provider_set=1; shift ;;
      --panel-model) col_preset_need_value "$1" "$#"; if [ -n "$panel_csv" ]; then panel_csv="$panel_csv,$2"; else panel_csv="$2"; fi; panel_set=1; shift 2 ;;
      --panel-model=*) if [ -n "$panel_csv" ]; then panel_csv="$panel_csv,${1#*=}"; else panel_csv="${1#*=}"; fi; panel_set=1; shift ;;
      --add-panel-model) col_preset_need_value "$1" "$#"; if [ -n "$add_csv" ]; then add_csv="$add_csv,$2"; else add_csv="$2"; fi; add_set=1; shift 2 ;;
      --add-panel-model=*) if [ -n "$add_csv" ]; then add_csv="$add_csv,${1#*=}"; else add_csv="${1#*=}"; fi; add_set=1; shift ;;
      --remove-panel-model) col_preset_need_value "$1" "$#"; if [ -n "$remove_csv" ]; then remove_csv="$remove_csv,$2"; else remove_csv="$2"; fi; remove_set=1; shift 2 ;;
      --remove-panel-model=*) if [ -n "$remove_csv" ]; then remove_csv="$remove_csv,${1#*=}"; else remove_csv="${1#*=}"; fi; remove_set=1; shift ;;
      --judge-model) col_preset_need_value "$1" "$#"; judge_model="$2"; judge_set=1; shift 2 ;;
      --judge-model=*) judge_model="${1#*=}"; judge_set=1; shift ;;
      --max-tool-calls) col_preset_need_value "$1" "$#"; max_tool_calls="$2"; mtc_set=1; shift 2 ;;
      --max-tool-calls=*) max_tool_calls="${1#*=}"; mtc_set=1; shift ;;
      --temperature) col_preset_need_value "$1" "$#"; temperature="$2"; temp_set=1; shift 2 ;;
      --temperature=*) temperature="${1#*=}"; temp_set=1; shift ;;
      --max-completion-tokens) col_preset_need_value "$1" "$#"; max_completion_tokens="$2"; mct_set=1; shift 2 ;;
      --max-completion-tokens=*) max_completion_tokens="${1#*=}"; mct_set=1; shift ;;
      --reasoning-effort) col_preset_need_value "$1" "$#"; reasoning_effort="$2"; reff_set=1; shift 2 ;;
      --reasoning-effort=*) reasoning_effort="${1#*=}"; reff_set=1; shift ;;
      --reasoning-max-tokens) col_preset_need_value "$1" "$#"; reasoning_max_tokens="$2"; rmt_set=1; shift 2 ;;
      --reasoning-max-tokens=*) reasoning_max_tokens="${1#*=}"; rmt_set=1; shift ;;
      --fallback) col_preset_need_value "$1" "$#"; fallback="$2"; fallback_set=1; shift 2 ;;
      --fallback=*) fallback="${1#*=}"; fallback_set=1; shift ;;
      --key-file) col_preset_need_value "$1" "$#"; keyfile="$2"; shift 2 ;;
      --key-file=*) keyfile="${1#*=}"; shift ;;
      --config) col_preset_need_value "$1" "$#"; col_set_config "$2"; shift 2 ;;
      --config=*) col_set_config "${1#*=}"; shift ;;
      --dry-run) dry_run=1; shift ;;
      -y|--yes) assume_yes=1; shift ;;
      --no-input) no_input=1; shift ;;
      -o|--output) col_preset_need_value "$1" "$#"; output="$2"; COL_PRESET_OUTPUT="$2"; shift 2 ;;
      --output=*) output="${1#*=}"; COL_PRESET_OUTPUT="${1#*=}"; shift ;;
      --json) output="json"; COL_PRESET_OUTPUT="json"; shift ;;
      -h|--help) col_preset_mutation_usage "$action"; return 0 ;;
      -*) COL_PRESET_OUTPUT="$output"; col_preset_fail 2 "usage" "unknown argument '$1' for 'preset $action'" ;;
      *) [ -z "$profile" ] || { COL_PRESET_OUTPUT="$output"; col_preset_fail 2 "usage" "preset $action accepts one profile name"; }; profile="$1"; shift ;;
    esac
  done
  COL_PRESET_OUTPUT="$output"
  col_preset_validate_output "$output"
  [ "$output" != "name" ] || col_preset_fail 2 "usage" "preset $action supports table or json output"
  col_require jq
  col_preset_load_config
  if [ "$no_input" -eq 0 ] && [ -t 0 ]; then interactive=1; fi
  if [ -z "$profile" ]; then
    [ "$interactive" -eq 1 ] || col_preset_fail 2 "usage" "preset $action needs a profile name when input is not interactive"
    profile="$(col_preset_prompt "Profile name")" || col_preset_fail 130 "interrupted" "preset $action interrupted"
  fi
  case "$profile" in
    ''|*[!a-z0-9._-]*|-*|.*|_*) col_preset_fail 2 "usage" "invalid profile name '$profile' — use lowercase letters, digits, dots, underscores, or hyphens" ;;
  esac
  if jq -e --arg p "$profile" '.profiles[$p] != null' "$COL_CONFIG" >/dev/null; then exists=1; fi
  if [ "$action" = "create" ] && [ "$exists" -eq 1 ]; then
    col_preset_fail 5 "conflict" "profile '$profile' already exists — use 'preset update $profile'"
  elif [ "$action" = "update" ] && [ "$exists" -eq 0 ]; then
    col_preset_fail 3 "not_found" "profile '$profile' not found — use 'preset create $profile'"
  fi
  if [ "$exists" -eq 1 ]; then
    current="$(jq -c --arg p "$profile" '.profiles[$p]' "$COL_CONFIG")"
    current_type="$(printf '%s' "$current" | jq -r '.type // empty')"
    current_slug="$(printf '%s' "$current" | jq -r '.preset_slug // empty')"
    [ "$type_set" -eq 1 ] || type="$(printf '%s' "$current" | jq -r '.type // empty')"
    [ "$slug_set" -eq 1 ] || preset_slug="$(printf '%s' "$current" | jq -r '.preset_slug // empty')"
    [ "$model_set" -eq 1 ] || model="$(printf '%s' "$current" | jq -r '.model // empty')"
    [ "$provider_set" -eq 1 ] || provider_csv="$(printf '%s' "$current" | jq -r '.provider.only // [] | join(",")')"
    [ "$panel_set" -eq 1 ] || panel_csv="$(printf '%s' "$current" | jq -r '.panel_models // [] | join(",")')"
    [ "$judge_set" -eq 1 ] || judge_model="$(printf '%s' "$current" | jq -r '.judge_model // empty')"
    [ "$fallback_set" -eq 1 ] || fallback="$(printf '%s' "$current" | jq -r '.fallback // empty')"
    [ "$mtc_set" -eq 1 ] || max_tool_calls="$(printf '%s' "$current" | jq -r '.max_tool_calls // empty')"
    [ "$temp_set" -eq 1 ] || temperature="$(printf '%s' "$current" | jq -r '.temperature // empty')"
    [ "$mct_set" -eq 1 ] || max_completion_tokens="$(printf '%s' "$current" | jq -r '.max_completion_tokens // empty')"
    [ "$reff_set" -eq 1 ] || reasoning_effort="$(printf '%s' "$current" | jq -r '.reasoning.effort // empty')"
    [ "$rmt_set" -eq 1 ] || reasoning_max_tokens="$(printf '%s' "$current" | jq -r '.reasoning.max_tokens // empty')"
  fi
  # Additive panel edits merge onto the resolved panel before any prompting, so
  # an interactive confirmation shows the merged panel as its default.
  if [ "$add_set" -eq 1 ] || [ "$remove_set" -eq 1 ]; then
    [ "$action" = "update" ] \
      || col_preset_fail 2 "usage" "--add-panel-model and --remove-panel-model need 'preset update' (create takes the full panel via --panel-model)"
    [ "$panel_set" -eq 0 ] \
      || col_preset_fail 2 "usage" "--panel-model replaces the whole panel — use it alone, or use --add-panel-model / --remove-panel-model to change single entries"
    _add_type="$type"
    [ -n "$_add_type" ] || _add_type="$current_type"
    [ "$_add_type" = "fusion" ] \
      || col_preset_fail 2 "usage" "--add-panel-model and --remove-panel-model need a fusion profile (type '${_add_type:-unknown}' has no panel)"
    panel_csv="$(col_preset_apply_panel_edits "$panel_csv" "$add_csv" "$remove_csv" "$profile")"
  fi
  if [ "$interactive" -eq 1 ]; then
    type="$(col_preset_prompt "Profile type (preset or fusion)" "${type:-preset}")" || col_preset_fail 130 "interrupted" "preset $action interrupted"
    preset_slug="$(col_preset_prompt "Preset slug" "${preset_slug:-cc-$profile}")" || col_preset_fail 130 "interrupted" "preset $action interrupted"
    if [ "$type" = "preset" ]; then
      model="$(col_preset_prompt "Model" "$model")" || col_preset_fail 130 "interrupted" "preset $action interrupted"
      provider_csv="$(col_preset_prompt "Provider tags (comma-separated)" "$provider_csv")" || col_preset_fail 130 "interrupted" "preset $action interrupted"
      fallback="$(col_preset_prompt "Fallback" "${fallback:-$model}")" || col_preset_fail 130 "interrupted" "preset $action interrupted"
    elif [ "$type" = "fusion" ]; then
      panel_csv="$(col_preset_prompt "Panel models (comma-separated)" "$panel_csv")" || col_preset_fail 130 "interrupted" "preset $action interrupted"
      judge_model="$(col_preset_prompt "Judge model" "$judge_model")" || col_preset_fail 130 "interrupted" "preset $action interrupted"
      max_tool_calls="$(col_preset_prompt "Max tool calls 1-16 (blank for default)" "$max_tool_calls")" || col_preset_fail 130 "interrupted" "preset $action interrupted"
      temperature="$(col_preset_prompt "Panel temperature 0-2 (blank for default)" "$temperature")" || col_preset_fail 130 "interrupted" "preset $action interrupted"
      max_completion_tokens="$(col_preset_prompt "Max completion tokens (blank for default)" "$max_completion_tokens")" || col_preset_fail 130 "interrupted" "preset $action interrupted"
      reasoning_effort="$(col_preset_prompt "Reasoning effort (blank for default)" "$reasoning_effort")" || col_preset_fail 130 "interrupted" "preset $action interrupted"
      reasoning_max_tokens="$(col_preset_prompt "Reasoning max tokens (blank for default)" "$reasoning_max_tokens")" || col_preset_fail 130 "interrupted" "preset $action interrupted"
      fallback="$(col_preset_prompt "Fallback" "${fallback:-openrouter/fusion}")" || col_preset_fail 130 "interrupted" "preset $action interrupted"
    fi
  fi
  case "$type" in preset|fusion) ;; *) col_preset_fail 2 "usage" "profile type must be 'preset' or 'fusion'" ;; esac
  [ -n "$preset_slug" ] || col_preset_fail 2 "usage" "--preset-slug is required"
  case "$preset_slug" in *[!a-zA-Z0-9._-]*) col_preset_fail 2 "usage" "invalid preset slug '$preset_slug'" ;; esac
  if [ "$type" = "preset" ] && { [ "$mtc_set" -eq 1 ] || [ "$temp_set" -eq 1 ] || [ "$mct_set" -eq 1 ] || [ "$reff_set" -eq 1 ] || [ "$rmt_set" -eq 1 ]; }; then
    col_preset_fail 2 "usage" "tuning knobs (--max-tool-calls, --temperature, --max-completion-tokens, --reasoning-*) need a fusion profile"
  fi
  if [ "$type" = "preset" ]; then
    [ -n "$model" ] || col_preset_fail 2 "usage" "--model is required for type 'preset'"
    [ -n "$provider_csv" ] || col_preset_fail 2 "usage" "at least one --provider is required for type 'preset'"
    [ -n "$fallback" ] || fallback="$model"
    providers_json="$(col_preset_csv_json "$provider_csv")"
    [ "$(printf '%s' "$providers_json" | jq -r 'length')" -gt 0 ] \
      || col_preset_fail 2 "usage" "at least one non-empty --provider is required for type 'preset'"
    profile_json="$(jq -n --arg slug "$preset_slug" --arg model "$model" \
      --argjson providers "$providers_json" --arg fallback "$fallback" \
      '{type:"preset", preset_slug:$slug, model:$model, provider:{only:$providers}, fallback:$fallback}')"
  else
    [ -n "$panel_csv" ] || col_preset_fail 2 "usage" "type 'fusion' needs a non-empty panel — pass --panel-model, or --add-panel-model on update"
    [ -n "$judge_model" ] || col_preset_fail 2 "usage" "--judge-model is required for type 'fusion'"
    [ -n "$fallback" ] || fallback="openrouter/fusion"
    if [ -n "$max_tool_calls" ]; then
      printf '%s' "$max_tool_calls" | jq -e 'tonumber | . == floor and . >= 1 and . <= 16' >/dev/null 2>&1 \
        || col_preset_fail 2 "usage" "--max-tool-calls must be an integer from 1 to 16"
    fi
    if [ -n "$temperature" ]; then
      printf '%s' "$temperature" | jq -e 'tonumber | . >= 0 and . <= 2' >/dev/null 2>&1 \
        || col_preset_fail 2 "usage" "--temperature must be a number from 0 to 2"
    fi
    if [ -n "$max_completion_tokens" ]; then
      printf '%s' "$max_completion_tokens" | jq -e 'tonumber | . == floor and . > 0' >/dev/null 2>&1 \
        || col_preset_fail 2 "usage" "--max-completion-tokens must be a positive integer"
    fi
    if [ -n "$reasoning_max_tokens" ]; then
      printf '%s' "$reasoning_max_tokens" | jq -e 'tonumber | . == floor and . > 0' >/dev/null 2>&1 \
        || col_preset_fail 2 "usage" "--reasoning-max-tokens must be a positive integer"
    fi
    panel_json="$(col_preset_csv_json "$panel_csv")"
    [ "$(printf '%s' "$panel_json" | jq -r 'length')" -gt 0 ] \
      || col_preset_fail 2 "usage" "type 'fusion' needs at least one non-empty panel model"
    # Optional knobs; only set values join the profile (absent stays default).
    knobs_json="$(jq -nc --arg mtc "$max_tool_calls" --arg temp "$temperature" \
      --arg mct "$max_completion_tokens" --arg reff "$reasoning_effort" --arg rmt "$reasoning_max_tokens" '
      {} | if $mtc != "" then .max_tool_calls = ($mtc | tonumber) else . end
         | if $temp != "" then .temperature = ($temp | tonumber) else . end
         | if $mct != "" then .max_completion_tokens = ($mct | tonumber) else . end
         | if $reff != "" or $rmt != "" then .reasoning = (
             {} | if $reff != "" then .effort = $reff else . end
                | if $rmt != "" then .max_tokens = ($rmt | tonumber) else . end) else . end')"
    profile_json="$(jq -n --arg slug "$preset_slug" --argjson panel "$panel_json" \
      --arg judge "$judge_model" --arg fallback "$fallback" --argjson knobs "$knobs_json" \
      '{type:"fusion", preset_slug:$slug, panel_models:$panel, judge_model:$judge, fallback:$fallback} + $knobs')"
  fi
  if [ "$action" = "update" ]; then
    if [ "$current_type" = "$type" ]; then
      profile_json="$(jq -n --argjson current "$current" --argjson next "$profile_json" '$current * $next')"
    else
      profile_json="$(jq -n --argjson current "$current" --argjson next "$profile_json" '
        ($current | del(.type, .preset_slug, .model, .provider, .panel_models, .judge_model,
                        .fallback, .max_tool_calls, .temperature, .max_completion_tokens, .reasoning)) * $next')"
    fi
  fi
  conflicting_profile="$(col_preset_other_profile_for_slug "$profile" "$preset_slug")"
  [ -z "$conflicting_profile" ] \
    || col_preset_fail 5 "conflict" "preset slug '$preset_slug' is already linked to profile '$conflicting_profile'"
  if [ "$COL_PRESET_OUTPUT" = "table" ] || [ "$dry_run" -eq 1 ]; then
    col_preset_print_plan "$action" "$profile" "$profile_json"
  fi
  [ "$dry_run" -eq 0 ] || return 0
  if [ "$assume_yes" -eq 0 ]; then
    [ "$interactive" -eq 1 ] || col_preset_fail 2 "confirmation_required" "confirmation required — pass --yes, or run interactively"
    answer="$(col_preset_prompt "Apply these changes? (y/N)" "N")" || col_preset_fail 130 "interrupted" "preset $action interrupted"
    case "$answer" in
      y|Y|yes|YES|Yes) ;;
      *)
        if [ "$COL_PRESET_OUTPUT" = "json" ]; then
          jq -n --arg action "$action" --arg profile "$profile" \
            '{ok:false, action:$action, profile:$profile, confirmed:false}'
        else
          printf 'No changes made.\n'
        fi
        return 0
        ;;
    esac
  fi
  col_require curl
  key="$(col_preset_resolve_key "$keyfile")"
  col_preset_require_valid_key "$key"
  if [ "$action" = "create" ] || { [ "$action" = "update" ] && [ "$current_slug" != "$preset_slug" ]; }; then
    preset_check_rc=0
    col_preset_check "$key" "$preset_slug" || preset_check_rc=$?
    case "$preset_check_rc" in
      0) col_preset_fail 5 "conflict" "preset '$preset_slug' already exists — link it in config or choose a different slug" ;;
      1) ;;
      2) col_preset_fail 1 "remote_unavailable" "could not verify whether preset '$preset_slug' already exists" ;;
    esac
  fi
  col_preset_write_profile "$profile" "$profile_json"
  if [ "$COL_PRESET_OUTPUT" = "table" ]; then printf 'config saved: %s\n' "$COL_CONFIG_WRITE_RESULT"; fi
  col_preset_apply_profile "$profile" "$key"
  applied_slug="$COL_PRESET_APPLIED_SLUG"
  if [ "$COL_PRESET_OUTPUT" = "json" ]; then
    jq -n --arg action "$action" --arg profile "$profile" --arg slug "$applied_slug" \
      --arg config "$COL_CONFIG_WRITE_RESULT" \
      '{ok:true, action:$action, profile:$profile, preset_slug:$slug, config:$config}'
  else
    printf "preset '%s' is ready for profile '%s'\n" "$applied_slug" "$profile"
  fi
}

col_preset_apply_command() {
  local profile="" all=0 keyfile="" output="table" dry_run=0 key profiles_json output_file rc=0 slug
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) all=1; shift ;;
      --key-file) col_preset_need_value "$1" "$#"; keyfile="$2"; shift 2 ;;
      --key-file=*) keyfile="${1#*=}"; shift ;;
      --config) col_preset_need_value "$1" "$#"; col_set_config "$2"; shift 2 ;;
      --config=*) col_set_config "${1#*=}"; shift ;;
      --dry-run) dry_run=1; shift ;;
      -o|--output) col_preset_need_value "$1" "$#"; output="$2"; COL_PRESET_OUTPUT="$2"; shift 2 ;;
      --output=*) output="${1#*=}"; COL_PRESET_OUTPUT="${1#*=}"; shift ;;
      --json) output="json"; COL_PRESET_OUTPUT="json"; shift ;;
      -h|--help) col_preset_apply_usage; return 0 ;;
      -*) COL_PRESET_OUTPUT="$output"; col_preset_fail 2 "usage" "unknown argument '$1' for 'preset apply'" ;;
      *) [ -z "$profile" ] || { COL_PRESET_OUTPUT="$output"; col_preset_fail 2 "usage" "preset apply accepts one profile name"; }; profile="$1"; shift ;;
    esac
  done
  COL_PRESET_OUTPUT="$output"
  col_preset_validate_output "$output"
  [ "$output" != "name" ] || col_preset_fail 2 "usage" "preset apply supports table or json output"
  [ "$all" -eq 0 ] || [ -z "$profile" ] || col_preset_fail 2 "usage" "use a profile name or --all, not both"
  [ "$all" -eq 1 ] || [ -n "$profile" ] || col_preset_fail 2 "usage" "preset apply needs a profile name or --all"
  col_require jq
  col_preset_load_config
  if [ "$all" -eq 0 ]; then
    jq -e --arg p "$profile" '.profiles[$p] != null' "$COL_CONFIG" >/dev/null \
      || col_preset_fail 3 "not_found" "profile '$profile' not found"
    case "$(col_profile_type "$profile")" in fusion|preset) ;; *) col_preset_fail 2 "usage" "profile '$profile' has no OpenRouter preset" ;; esac
    profiles_json="$(jq -n --arg p "$profile" '[$p]')"
  else
    profiles_json="$(jq -c '[.profiles | to_entries[] | select(.value.type == "fusion" or .value.type == "preset") | .key] | sort' "$COL_CONFIG")"
  fi
  if [ "$dry_run" -eq 1 ]; then
    if [ "$output" = "json" ]; then
      jq -n --argjson profiles "$profiles_json" --arg config "$COL_CONFIG" \
        '{dry_run:true, action:"apply", profiles:$profiles, config:$config}'
    else
      printf 'Plan:\n  apply profiles: %s\n  config: %s\n' \
        "$(printf '%s' "$profiles_json" | jq -r 'join(", ")')" "$COL_CONFIG"
    fi
    return 0
  fi
  col_require curl
  key="$(col_preset_resolve_key "$keyfile")"
  col_preset_require_valid_key "$key"
  output_file="$(mktemp "${TMPDIR:-/tmp}/claude-openrouter-apply.XXXXXX")"
  if [ "$all" -eq 1 ]; then
    CLAUDE_OPENROUTER_CONFIG="$COL_CONFIG" OPENROUTER_API_KEY="$key" \
      "$COL_ROOT/setup.sh" > "$output_file" 2>&1 || rc=$?
  else
    CLAUDE_OPENROUTER_CONFIG="$COL_CONFIG" OPENROUTER_API_KEY="$key" \
      "$COL_ROOT/setup.sh" --profile "$profile" > "$output_file" 2>&1 || rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    if [ "$COL_PRESET_OUTPUT" = "table" ]; then cat "$output_file" >&2; fi
    rm -f "$output_file"
    col_preset_fail 1 "apply_failed" "preset synchronization failed"
  fi
  if [ "$output" = "json" ]; then
    jq -n --argjson profiles "$profiles_json" --arg config "$COL_CONFIG" \
      '{ok:true, action:"apply", profiles:$profiles, config:$config}'
  else
    cat "$output_file"
    if [ "$all" -eq 0 ]; then
      slug="$(col_cfg --arg p "$profile" '.profiles[$p].preset_slug')"
      printf "preset '%s' is ready for profile '%s'\n" "$slug" "$profile"
    fi
  fi
  rm -f "$output_file"
}

col_preset_command() {
  local action="${1:-}"
  [ $# -gt 0 ] && shift
  case "$action" in
    list) col_preset_list_command "$@" ;;
    view) col_preset_view_command "$@" ;;
    create|update) col_preset_mutation_command "$action" "$@" ;;
    apply) col_preset_apply_command "$@" ;;
    -h|--help|help) col_preset_group_usage ;;
    '') col_preset_group_usage >&2; return 2 ;;
    *) col_preset_group_usage >&2; printf "\nclaude-openrouter: unknown preset command '%s'\n" "$action" >&2; return 2 ;;
  esac
}

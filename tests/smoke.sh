#!/usr/bin/env bash
# tests/smoke.sh — NO-COST checks (no OpenRouter/Claude API calls).
# shellcheck disable=SC2030,SC2031
set -uo pipefail

COL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$COL_ROOT" || exit 1
fail=0
note() { printf '%-42s %s\n' "$1" "$2"; }
ok()   { note "$1" "ok"; }
bad()  { note "$1" "FAIL: ${2:-}"; fail=1; }

# 1. shellcheck (if available)
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck bin/claude-openrouter setup.sh lib/common.sh lib/presets.sh lib/check-openrouter.sh tests/smoke.sh .githooks/pre-commit; then ok "shellcheck"; else bad "shellcheck"; fi
else
  note "shellcheck" "skipped (not installed)"
fi

# 2. example config is valid JSON
if jq -e . config/modes.json.example >/dev/null 2>&1; then ok "modes.json.example valid"; else bad "modes.json.example valid"; fi

# 3. launcher --help works with no config and no key
if bin/claude-openrouter --help >/dev/null 2>&1; then ok "launcher --help"; else bad "launcher --help"; fi

# Use the example as config and an isolated state dir for render/key tests.
export CLAUDE_OPENROUTER_CONFIG="$COL_ROOT/config/modes.json.example"
tmpstate="$(mktemp -d)"
export XDG_CONFIG_HOME="$tmpstate"
trap 'rm -rf "$tmpstate"' EXIT
# shellcheck source=lib/common.sh
. lib/common.sh

fakebin="$tmpstate/fakebin"; mkdir -p "$fakebin"
cat > "$fakebin/claude" <<'EOS'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "claude smoke"
  exit 0
fi
if [ -n "${CLAUDE_ARGV_OUT:-}" ]; then
  printf '%s\n' "$@" > "$CLAUDE_ARGV_OUT"
fi
EOS
chmod +x "$fakebin/claude"

# 4. each shipped mode renders to valid JSON (profile-aware signature)
for m in subagent main extreme; do
  out="$(col_render_settings "$m" fusion)"
  if jq -e . "$out" >/dev/null 2>&1; then
    ok "render mode: $m"
  else
    bad "render mode: $m"
  fi
done

# 4b. the settings path is unique per resolved backend (same mode, different profile
#     or a direct slug must NOT collide on one $mode.json), and the write is atomic.
p_fusion="$(col_render_settings extreme fusion)"
p_deep="$(col_render_settings extreme deepseek)"
p_direct="$(col_render_settings extreme "" "qwen/qwen3-coder-plus")"
if [ "$p_fusion" != "$p_deep" ] && [ "$p_deep" != "$p_direct" ] && [ "$p_fusion" != "$p_direct" ] \
  && jq -e . "$p_deep" >/dev/null 2>&1 && jq -e . "$p_direct" >/dev/null 2>&1; then
  ok "settings path unique per backend"
else
  bad "settings path unique per backend" "$(basename "$p_fusion") $(basename "$p_deep") $(basename "$p_direct")"
fi

# 5. fusion profile resolves to fallback when its preset is NOT set up
out5="$(col_render_settings main fusion)"
opus_main="$(jq -r '.env.ANTHROPIC_DEFAULT_OPUS_MODEL' "$out5")"
if [ "$opus_main" = "openrouter/fusion" ]; then ok "fusion->fallback (no preset)"; else bad "fusion->fallback (no preset)" "got $opus_main"; fi

# 6. fusion profile resolves to @preset/<slug> once the per-slug marker exists
mkdir -p "$XDG_CONFIG_HOME/claude-openrouter/presets"
printf '{"preset_slug":"cc-fusion","verified_at":"2000-01-01T00:00:00Z"}' > "$XDG_CONFIG_HOME/claude-openrouter/presets/cc-fusion.json"
out="$(col_render_settings main fusion)"
opus_main="$(jq -r '.env.ANTHROPIC_DEFAULT_OPUS_MODEL' "$out")"
if [ "$opus_main" = "@preset/cc-fusion" ]; then ok "fusion->@preset (preset ready)"; else bad "fusion->@preset (preset ready)" "got $opus_main"; fi

# 6b. a marker for a different slug must NOT route to @preset/<this-slug>
stalecfg="$(mktemp)"
jq '.profiles.fusion.preset_slug = "cc-fusion-new"' "$COL_CONFIG" > "$stalecfg"
old_cfg="$COL_CONFIG"; COL_CONFIG="$stalecfg"; stale_out="$(col_render_settings main fusion)"; COL_CONFIG="$old_cfg"
stale_opus="$(jq -r '.env.ANTHROPIC_DEFAULT_OPUS_MODEL' "$stale_out")"
if [ "$stale_opus" = "openrouter/fusion" ]; then ok "stale preset marker ignored"; else bad "stale preset marker ignored" "got $stale_opus"; fi
rm -f "$stalecfg"

# 6c. the top-level default model slot also resolves the "backend" keyword
defcfg="$(mktemp)"
jq '.modes.default_fusion = {"default":"backend","opus":"~anthropic/claude-opus-latest"}' "$COL_CONFIG" > "$defcfg"
old_cfg="$COL_CONFIG"; COL_CONFIG="$defcfg"; def_out="$(col_render_settings default_fusion fusion)"; COL_CONFIG="$old_cfg"
def_model="$(jq -r '.model' "$def_out")"
if [ "$def_model" = "@preset/cc-fusion" ]; then ok "default slot resolves backend"; else bad "default slot resolves backend" "got $def_model"; fi
rm -f "$defcfg"

# 6d. a type:"preset" profile resolves to its fallback (bare model) with no marker,
#     and to @preset/<slug> once the per-slug marker exists.
fw_ref="$(col_profile_backend_ref glm-fireworks)"
if [ "$fw_ref" = "z-ai/glm-5.2" ]; then ok "preset->fallback (no preset)"; else bad "preset->fallback (no preset)" "got $fw_ref"; fi
printf '{"preset_slug":"cc-glm-fireworks"}' > "$XDG_CONFIG_HOME/claude-openrouter/presets/cc-glm-fireworks.json"
fw_ref2="$(col_profile_backend_ref glm-fireworks)"
if [ "$fw_ref2" = "@preset/cc-glm-fireworks" ]; then ok "preset->@preset (marker present)"; else bad "preset->@preset (marker present)" "got $fw_ref2"; fi
rm -f "$XDG_CONFIG_HOME/claude-openrouter/presets/cc-glm-fireworks.json"

# 7. subagent mode keeps a plain Opus main but fusion subagent
sub_out="$(col_render_settings subagent fusion)"
sub="$(jq -r '.env.CLAUDE_CODE_SUBAGENT_MODEL' "$sub_out")"
mainslot="$(jq -r '.env.ANTHROPIC_DEFAULT_OPUS_MODEL' "$sub_out")"
if [ "$sub" = "@preset/cc-fusion" ] && [ "$mainslot" = "~anthropic/claude-opus-latest" ]; then
  ok "subagent slot mapping"
else
  bad "subagent slot mapping" "main=$mainslot sub=$sub"
fi

# 8. advisor disabled in every rendered profile
ext_out="$(col_render_settings extreme fusion)"
if jq -e '.env.CLAUDE_CODE_DISABLE_ADVISOR_TOOL == "1"' "$ext_out" >/dev/null; then ok "advisor disabled"; else bad "advisor disabled"; fi

# 8b. rendered env never contains null values (all strings)
if jq -e '[.env[]] | all(type == "string")' "$ext_out" >/dev/null; then ok "env values all strings"; else bad "env values all strings"; fi

# 8c. a partial custom mode OMITS undefined slots (must not write null env keys)
partcfg="$(mktemp)"
jq '.modes.partial = {"default":"opus","opus":"backend","subagent":"backend"}' "$COL_CONFIG" > "$partcfg"
old_cfg="$COL_CONFIG"; COL_CONFIG="$partcfg"; part_out="$(col_render_settings partial fusion)"; COL_CONFIG="$old_cfg"
nulls="$(jq -c '[.env[] | select(. == null)] | length' "$part_out")"
has_sonnet="$(jq -c '.env | has("ANTHROPIC_DEFAULT_SONNET_MODEL")' "$part_out")"
if [ "$nulls" = "0" ] && [ "$has_sonnet" = "false" ]; then ok "partial mode omits null slots"; else bad "partial mode omits null slots" "nulls=$nulls sonnetKey=$has_sonnet"; fi
rm -f "$partcfg"

# 9. key precedence: --key > --key-file > env
k="$(col_resolve_key "argkey" "")"
if [ "$k" = "argkey" ]; then ok "key: --key wins"; else bad "key: --key wins" "$k"; fi
kf="$(mktemp)"; printf 'export OPENROUTER_API_KEY=filekey\n' > "$kf"
k="$(OPENROUTER_API_KEY=envkey col_resolve_key "" "$kf")"
if [ "$k" = "filekey" ]; then ok "key: --key-file > env"; else bad "key: --key-file > env" "$k"; fi
k="$(OPENROUTER_API_KEY=envkey col_resolve_key "" "")"
if [ "$k" = "envkey" ]; then ok "key: env fallback"; else bad "key: env fallback" "$k"; fi
rm -f "$kf"

# 10. config resolution: with no override and no modes.json, defaults to the example.
# shellcheck disable=SC2016  # $COL_CONFIG must expand in the child bash, not here
cfg_resolved="$(cd "$COL_ROOT" && env -u CLAUDE_OPENROUTER_CONFIG -u COL_ROOT bash -c '. lib/common.sh; printf "%s" "$COL_CONFIG"')"
case "$cfg_resolved" in
  */config/modes.json.example) ok "config defaults to example (no setup needed)" ;;
  */config/modes.json)         ok "config uses local modes.json override" ;;
  *) bad "config resolution" "$cfg_resolved" ;;
esac

# 11. launcher runs from an unrelated cwd (run-location / symlink guard)
if ( cd /tmp && "$COL_ROOT/bin/claude-openrouter" --help >/dev/null 2>&1 ); then ok "runs from other cwd"; else bad "runs from other cwd"; fi

# 12. launcher runs via a symlink onto PATH
lns="$(mktemp -d)/cf-link"; ln -s "$COL_ROOT/bin/claude-openrouter" "$lns"
if ( cd /tmp && "$lns" --help >/dev/null 2>&1 ); then ok "runs via symlink"; else bad "runs via symlink"; fi
rm -f "$lns"

# 13. 'modes' subcommand lists shipped modes
# (capture first — `cmd | grep -q` under `set -o pipefail` can SIGPIPE the producer)
modes_out="$(bin/claude-openrouter modes 2>/dev/null || true)"
case "$modes_out" in *"subagent:"*) ok "modes subcommand" ;; *) bad "modes subcommand" ;; esac

# 13b. 'profiles' subcommand lists profiles + targets (fusion, model, and preset)
profiles_out="$(bin/claude-openrouter profiles 2>/dev/null || true)"
if [[ "$profiles_out" == *"fusion (fusion):"* && "$profiles_out" == *"glm-fireworks (preset):"* && "$profiles_out" == *"fireworks"* ]]; then
  ok "profiles subcommand"
else
  bad "profiles subcommand" "$profiles_out"
fi

# 14. --show-settings renders valid JSON and reports the active profile
ss_out="$(bin/claude-openrouter --show-settings --profile fusion --mode main 2>/dev/null || true)"
ss_json="$(printf '%s' "$ss_out" | sed -n '/^----$/,$p' | tail -n +2)"
if printf '%s' "$ss_json" | jq -e '.env.ANTHROPIC_DEFAULT_OPUS_MODEL' >/dev/null 2>&1 \
  && [[ "$ss_out" == *"profile:"* ]]; then ok "--show-settings renders JSON"; else bad "--show-settings renders JSON" "$ss_out"; fi

# 14b. unknown modes must fail instead of silently rendering defaults
if bin/claude-openrouter --show-settings --mode bogus >/dev/null 2>&1; then bad "unknown mode rejected"; else ok "unknown mode rejected"; fi

# 14c. --backend uses the raw slug in all slots under the default (extreme) mode
be_out="$(bin/claude-openrouter --show-settings --backend "qwen/qwen3-coder-plus" 2>/dev/null || true)"
be_json="$(printf '%s' "$be_out" | sed -n '/^----$/,$p' | tail -n +2)"
be_default="$(printf '%s' "$be_json" | jq -r '.model')"
be_sub="$(printf '%s' "$be_json" | jq -r '.env.CLAUDE_CODE_SUBAGENT_MODEL')"
if [ "$be_default" = "qwen/qwen3-coder-plus" ] && [ "$be_sub" = "qwen/qwen3-coder-plus" ]; then ok "--backend fills all slots (extreme default)"; else bad "--backend fills all slots" "default=$be_default sub=$be_sub"; fi

# 14d. --profile model alias resolves in all slots under default mode
ds_out="$(bin/claude-openrouter --show-settings --profile deepseek 2>/dev/null || true)"
ds_json="$(printf '%s' "$ds_out" | sed -n '/^----$/,$p' | tail -n +2)"
ds_default="$(printf '%s' "$ds_json" | jq -r '.model')"
if [ "$ds_default" = "deepseek/deepseek-v3.2" ]; then ok "--profile model alias resolves"; else bad "--profile model alias resolves" "$ds_default"; fi

# 14e. --profile and --backend together is an error
if bin/claude-openrouter --show-settings --profile fusion --backend foo >/dev/null 2>&1; then bad "profile+backend mutually exclusive"; else ok "profile+backend mutually exclusive"; fi

# 15. no args (non-TTY) prints help and exits 0
if out_help="$(bin/claude-openrouter </dev/null 2>&1)" && printf '%s' "$out_help" | grep -q 'claude-openrouter'; then ok "no-args help (exit 0)"; else bad "no-args help"; fi

# 16. -h prints help
h_out="$(bin/claude-openrouter -h 2>/dev/null || true)"
case "$h_out" in *"Quick start"*) ok "-h help" ;; *) bad "-h help" ;; esac

# 17. doctor runs and reports (no key -> skips account checks; deps may vary in CI)
doc_out="$(bin/claude-openrouter doctor </dev/null 2>&1 || true)"
if [[ "$doc_out" == *"claude-openrouter doctor"* && "$doc_out" == *"doctor:"* ]]; then ok "doctor reports"; else bad "doctor reports"; fi

# 18. pre-flight connectivity check: script present/executable, wired into launcher,
#     and the rendered settings carry NO (non-functional) hooks block.
if [ -x lib/check-openrouter.sh ]; then ok "pre-flight script executable"; else bad "pre-flight script executable"; fi
if grep -q 'lib/check-openrouter.sh' bin/claude-openrouter; then ok "launcher runs pre-flight"; else bad "launcher runs pre-flight"; fi
if jq -e 'has("hooks") | not' "$ext_out" >/dev/null 2>&1; then ok "no dead hooks block in settings"; else bad "no dead hooks block in settings"; fi

# 19. check-openrouter covers key/no-key URL choices and warns non-blockingly.
prebin="$tmpstate/prebin"; mkdir -p "$prebin"
cat > "$prebin/curl" <<'EOS'
#!/usr/bin/env bash
url=""
for arg in "$@"; do
  case "$arg" in https://*) url="$arg" ;; esac
done
printf '%s\n' "$url" >> "$CURL_URL_LOG"
if [ "${CURL_FAIL:-0}" = "1" ]; then exit 7; fi
exit 0
EOS
chmod +x "$prebin/curl"
curl_url_log="$tmpstate/precheck-urls.txt"
# check-openrouter.sh resolves ANTHROPIC_AUTH_TOKEN before OPENROUTER_API_KEY, and the
# clf/clfa launcher wrappers export the former — so both must go for these URL branches
# to be decided by the case under test rather than by the ambient shell.
env -u OPENROUTER_API_KEY -u ANTHROPIC_AUTH_TOKEN PATH="$prebin:$PATH" CURL_URL_LOG="$curl_url_log" lib/check-openrouter.sh >/dev/null 2>&1
env -u ANTHROPIC_AUTH_TOKEN PATH="$prebin:$PATH" CURL_URL_LOG="$curl_url_log" OPENROUTER_API_KEY=test lib/check-openrouter.sh >/dev/null 2>&1
pre_fail_out="$(env -u ANTHROPIC_AUTH_TOKEN PATH="$prebin:$PATH" CURL_URL_LOG="$curl_url_log" CURL_FAIL=1 OPENROUTER_API_KEY=test lib/check-openrouter.sh 2>&1)"
if grep -Fxq "https://openrouter.ai/api/v1/models" "$curl_url_log" \
  && grep -Fxq "https://openrouter.ai/api/v1/key" "$curl_url_log" \
  && [[ "$pre_fail_out" == *"can't reach"* ]]; then
  ok "pre-flight checks URL paths"
else
  bad "pre-flight checks URL paths" "$(tr '\n' ' ' < "$curl_url_log" 2>/dev/null || true)"
fi

# 20. Doctor account checks are covered with stubbed OpenRouter responses.
# Build an in-sync preset straight from the config so the diff has nothing to flag,
# and a drifted variant (one panel model swapped) that must warn but NOT fail.
synced_preset="$(jq -nc \
  --argjson panel "$(jq -c '.profiles.fusion.panel_models' "$COL_CONFIG")" \
  --arg judge "$(jq -r '.profiles.fusion.judge_model' "$COL_CONFIG")" \
  '{data:{designated_version:{config:{model:"openrouter/fusion",tool_choice:"required",
    tools:[{type:"openrouter:fusion",parameters:{model:$judge,analysis_models:$panel}}]}}}}')"
drift_preset="$(printf '%s' "$synced_preset" \
  | jq -c '.data.designated_version.config.tools[0].parameters.analysis_models[0]="zzz/drifted-model"')"

doctor_ok_out="$(
  PATH="$fakebin:$PATH"
  col_or_get() {
    if [ "$2" = "key" ]; then
      printf '{"data":{"label":"smoke"}}'
    elif [ "$2" = "credits" ]; then
      printf '{"data":{"total_credits":1,"total_usage":0.25}}'
    elif [ "$2" = "presets/cc-fusion" ]; then
      printf '%s' "$synced_preset"
    else
      return 22
    fi
  }
  col_doctor "test" "file:/tmp/key.env"
)"
drift_rc=0
doctor_drift_out="$(
  PATH="$fakebin:$PATH"
  col_or_get() {
    if [ "$2" = "key" ]; then
      printf '{"data":{"label":"smoke"}}'
    elif [ "$2" = "credits" ]; then
      printf '{"data":{"total_credits":10,"total_usage":1}}'
    elif [ "$2" = "presets/cc-fusion" ]; then
      printf '%s' "$drift_preset"
    else
      return 22
    fi
  }
  col_doctor "test" "env:OPENROUTER_API_KEY"
)" || drift_rc=$?
doctor_bad_out="$(
  PATH="$fakebin:$PATH"
  col_or_get() { return 22; }
  col_doctor "test"
)"
# shellcheck disable=SC2016  # the $OPENROUTER_API_KEY below is a literal in a glob, not an expansion
if [[ "$doctor_ok_out" == *"key resolved (…test)"* \
  && "$doctor_ok_out" == *"source: file /tmp/key.env"* \
  && "$doctor_ok_out" == *"key valid"* && "$doctor_ok_out" == *"low credits"* \
  && "$doctor_ok_out" == *"preset 'cc-fusion' configured"* \
  && "$doctor_ok_out" == *"qwen/qwen3-coder-plus"* \
  && "$doctor_ok_out" == *"tool_choice: required"* \
  && "$doctor_ok_out" == *"matches config"* \
  && "$doctor_ok_out" == *"fusion (fusion):"* \
  && "$doctor_drift_out" == *'source: env $OPENROUTER_API_KEY'* \
  && "$doctor_drift_out" == *"differs from config"* && "$doctor_drift_out" == *"zzz/drifted-model"* \
  && "$drift_rc" -eq 0 \
  && "$doctor_bad_out" == *"OpenRouter rejected the key"* ]]; then
  ok "doctor account branch covered"
else
  bad "doctor account branch covered" "drift_rc=$drift_rc"
fi

# 21. --cost reports a numeric usage delta with stubbed curl/claude.
costbin="$tmpstate/costbin"; mkdir -p "$costbin"
cost_count="$tmpstate/cost-count.txt"; printf '0' > "$cost_count"
cat > "$costbin/curl" <<'EOS'
#!/usr/bin/env bash
url=""
for arg in "$@"; do
  case "$arg" in https://*) url="$arg" ;; esac
done
case "$url" in
  */credits)
    n="$(cat "$COST_COUNT")"
    if [ "$n" = "0" ]; then
      printf '1' > "$COST_COUNT"
      printf '{"data":{"total_usage":1}}'
    else
      printf '{"data":{"total_usage":1.25}}'
    fi
    ;;
  *) printf '{"data":{}}' ;;
esac
EOS
cat > "$costbin/claude" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS
chmod +x "$costbin/curl" "$costbin/claude"
cost_out="$(PATH="$costbin:$PATH" COST_COUNT="$cost_count" COL_SKIP_PRECHECK=1 bin/claude-openrouter --cost --key test -p hi 2>&1)"
if [[ "$cost_out" == *"session cost ~\$0.25"* && "$cost_out" == *"OpenRouter usage \$1 -> \$1.25"* ]]; then ok "--cost reports usage delta"; else bad "--cost reports usage delta" "$cost_out"; fi

# 22. Setup reports non-JSON preset responses instead of aborting on jq parse errors.
setupbin="$tmpstate/setupbin"; mkdir -p "$setupbin"
cat > "$setupbin/curl" <<'EOS'
#!/usr/bin/env bash
url=""
for arg in "$@"; do
  case "$arg" in https://*) url="$arg" ;; esac
done
case "$url" in
  */key) printf '{"data":{"label":"smoke"}}' ;;
  */credits) printf '{"data":{"total_credits":10,"total_usage":1}}' ;;
  */presets/*/chat/completions) printf '<html>bad gateway</html>' ;;
  *) printf '{"error":{"message":"unexpected URL"}}' ;;
esac
EOS
chmod +x "$setupbin/curl"
setup_out="$(PATH="$setupbin:$PATH" XDG_CONFIG_HOME="$tmpstate/setup-state" ./setup.sh --key test 2>&1)"
setup_rc=$?
if [ "$setup_rc" -ne 0 ] && [[ "$setup_out" == *'<html>bad gateway</html>'* && "$setup_out" == *'preset creation failed'* && "$setup_out" != *'parse error'* ]]; then
  ok "setup handles non-JSON preset response"
else
  bad "setup handles non-JSON preset response" "$setup_out"
fi

# 22b. Setup creates a preset per fusion profile and writes a per-slug marker each.
# The stub echoes back the requested model so it works for fusion AND preset bodies.
okbin="$tmpstate/setup-okbin"; mkdir -p "$okbin"
cat > "$okbin/curl" <<'EOS'
#!/usr/bin/env bash
url=""; body=""; prev=""
for arg in "$@"; do
  case "$arg" in https://*) url="$arg" ;; esac
  [ "$prev" = "-d" ] && body="$arg"
  prev="$arg"
done
case "$url" in
  */key) printf '{"data":{"label":"smoke"}}' ;;
  */credits) printf '{"data":{"total_credits":10,"total_usage":1}}' ;;
  */presets/*/chat/completions)
    # Echo the posted config back verbatim (model, provider, tools, tool_choice) so
    # both the fusion field-verification and the preset provider check see a match.
    cfg="$(printf '%s' "$body" | jq -c '{model, provider:(.provider//{}), tools:(.tools//[]), tool_choice:(.tool_choice//null)}')"
    printf '{"data":{"designated_version":{"config":%s}}}' "$cfg" ;;
  *) printf '{"error":{"message":"unexpected URL"}}' ;;
esac
EOS
chmod +x "$okbin/curl"
two_cfg="$(mktemp)"
jq '.profiles["fusion2"] = {"type":"fusion","preset_slug":"cc-fusion-2","panel_models":["deepseek/deepseek-v3.2"],"judge_model":"deepseek/deepseek-v3.2","fallback":"openrouter/fusion"}' "$COL_CONFIG" > "$two_cfg"
ok_state="$tmpstate/setup-ok-state"
ok_out="$(PATH="$okbin:$PATH" XDG_CONFIG_HOME="$ok_state" CLAUDE_OPENROUTER_CONFIG="$two_cfg" ./setup.sh --key test 2>&1)"
if [ -f "$ok_state/claude-openrouter/presets/cc-fusion.json" ] && [ -f "$ok_state/claude-openrouter/presets/cc-fusion-2.json" ]; then
  ok "setup creates a marker per fusion profile"
else
  bad "setup creates a marker per fusion profile" "$ok_out"
fi

# 22c. setup --profile <model-profile> creates nothing and exits 0.
skip_out="$(PATH="$okbin:$PATH" XDG_CONFIG_HOME="$tmpstate/setup-skip-state" CLAUDE_OPENROUTER_CONFIG="$two_cfg" ./setup.sh --profile deepseek --key test 2>&1)"
skip_rc=$?
if [ "$skip_rc" -eq 0 ] && [[ "$skip_out" == *"nothing to set up"* ]] && [ ! -d "$tmpstate/setup-skip-state/claude-openrouter/presets" ]; then
  ok "setup --profile model skips"
else
  bad "setup --profile model skips" "rc=$skip_rc $skip_out"
fi
rm -f "$two_cfg"

# 22d. setup --profile <preset-profile> creates a provider-pinned preset: writes the
#      marker AND the POSTed body carries the provider pin (provider.only).
presetbin="$tmpstate/setup-presetbin"; mkdir -p "$presetbin"
preset_body_log="$tmpstate/preset-body.txt"
cat > "$presetbin/curl" <<'EOS'
#!/usr/bin/env bash
url=""; body=""; prev=""
for arg in "$@"; do
  case "$arg" in https://*) url="$arg" ;; esac
  [ "$prev" = "-d" ] && body="$arg"
  prev="$arg"
done
case "$url" in
  */key) printf '{"data":{"label":"smoke"}}' ;;
  */credits) printf '{"data":{"total_credits":10,"total_usage":1}}' ;;
  */presets/*/chat/completions)
    printf '%s\n' "$body" >> "$PRESET_BODY_LOG"
    m="$(printf '%s' "$body" | jq -r '.model // "openrouter/fusion"')"
    prov="$(printf '%s' "$body" | jq -c '.provider // {}')"
    printf '{"data":{"designated_version":{"config":{"model":"%s","provider":%s}}}}' "$m" "$prov" ;;
  *) printf '{"error":{"message":"unexpected URL"}}' ;;
esac
EOS
chmod +x "$presetbin/curl"
preset_state="$tmpstate/setup-preset-state"
PATH="$presetbin:$PATH" PRESET_BODY_LOG="$preset_body_log" XDG_CONFIG_HOME="$preset_state" \
  ./setup.sh --profile glm-fireworks --key test >/dev/null 2>&1
preset_rc=$?
if [ "$preset_rc" -eq 0 ] \
  && [ -f "$preset_state/claude-openrouter/presets/cc-glm-fireworks.json" ] \
  && jq -rc 'select(.model=="z-ai/glm-5.2") | .provider.only' "$preset_body_log" 2>/dev/null | grep -q fireworks; then
  ok "setup creates provider-pinned preset"
else
  bad "setup creates provider-pinned preset" "rc=$preset_rc"
fi

# 22e. A preset-backed profile missing preset_slug is skipped with a warning and a
#      non-zero exit, and writes no marker (no POST to /presets//chat/completions).
badcfg="$(mktemp)"
jq '.profiles["broken"] = {"type":"fusion","panel_models":["deepseek/deepseek-v3.2"],"judge_model":"deepseek/deepseek-v3.2"}' "$COL_CONFIG" > "$badcfg"
badslug_out="$(PATH="$presetbin:$PATH" XDG_CONFIG_HOME="$tmpstate/setup-badslug" CLAUDE_OPENROUTER_CONFIG="$badcfg" ./setup.sh --profile broken --key test 2>&1)"
badslug_rc=$?
if [ "$badslug_rc" -ne 0 ] && [[ "$badslug_out" == *"missing preset_slug"* ]] && [ ! -e "$tmpstate/setup-badslug/claude-openrouter/presets/null.json" ]; then
  ok "setup rejects missing preset_slug"
else
  bad "setup rejects missing preset_slug" "rc=$badslug_rc $badslug_out"
fi
rm -f "$badcfg"

# 23. gitleaks hook falls back to the older protect --staged syntax.
gitleaksbin="$tmpstate/gitleaksbin"; mkdir -p "$gitleaksbin"
gitleaks_log="$tmpstate/gitleaks.log"
cat > "$gitleaksbin/gitleaks" <<'EOS'
#!/usr/bin/env bash
case "$1" in
  git) echo "unknown command git" >&2; exit 2 ;;
  protect) printf '%s\n' "$*" >> "$GITLEAKS_LOG"; exit 0 ;;
  *) exit 2 ;;
esac
EOS
chmod +x "$gitleaksbin/gitleaks"
if PATH="$gitleaksbin:$PATH" GITLEAKS_LOG="$gitleaks_log" .githooks/pre-commit >/dev/null 2>&1 \
  && grep -Fxq "protect --staged --no-banner --redact" "$gitleaks_log"; then
  ok "gitleaks hook supports protect syntax"
else
  bad "gitleaks hook supports protect syntax"
fi

# 24. CI and local recipe entrypoints stay aligned.
ci_file=".github/workflows/ci.yml"
if grep -q 'setup-just' "$ci_file" && grep -q 'make check' "$ci_file" && grep -q 'just all' "$ci_file" && grep -q '^all: lint test' justfile; then
  ok "ci runs declared recipes"
else
  bad "ci runs declared recipes"
fi
if grep -q 'lib/check-openrouter.sh' justfile && grep -q '.githooks/pre-commit' justfile \
  && grep -q 'lib/check-openrouter.sh' Makefile && grep -q '.githooks/pre-commit' Makefile; then
  ok "lint recipes cover shell files"
else
  bad "lint recipes cover shell files"
fi

# 25. Just/Make recipes preserve documented defaults and setup args.
argv_out="$tmpstate/claude-argv.txt"
if PATH="$fakebin:$PATH" CLAUDE_ARGV_OUT="$argv_out" COL_SKIP_PRECHECK=1 just --quiet run main --key test -p "hello world" >/dev/null 2>&1 \
  && grep -Fxq -- "hello world" "$argv_out"; then
  ok "just run preserves spaced args"
else
  bad "just run preserves spaced args" "$(tr '\n' ' ' < "$argv_out" 2>/dev/null || true)"
fi

default_argv_out="$tmpstate/default-claude-argv.txt"
if PATH="$fakebin:$PATH" CLAUDE_ARGV_OUT="$default_argv_out" COL_SKIP_PRECHECK=1 OPENROUTER_API_KEY=test just --quiet run >/dev/null 2>&1 \
  && grep -Eq '/fusion-extreme\.json$' "$default_argv_out"; then
  ok "just run defaults to extreme"
else
  bad "just run defaults to extreme" "$(tr '\n' ' ' < "$default_argv_out" 2>/dev/null || true)"
fi

setup_dry="$(just --dry-run setup --key-file "space path" 2>&1 || true)"
doctor_dry="$(just --dry-run doctor --key-file "space path" 2>&1 || true)"
if [[ "$setup_dry" == *'./setup.sh "$@"'* && "$doctor_dry" == *'bin/claude-openrouter doctor "$@"'* ]]; then
  ok "just setup/doctor forward args safely"
else
  bad "just setup/doctor forward args safely"
fi

make_setup_dry="$(make -n setup ARGS='--key-file /tmp/key' 2>&1 || true)"
if [[ "$make_setup_dry" == *'./setup.sh --key-file /tmp/key'* ]]; then ok "make setup forwards ARGS"; else bad "make setup forwards ARGS" "$make_setup_dry"; fi

install_home="$tmpstate/install-home"
mkdir -p "$install_home"
rm -rf "$COL_ROOT/~"
just_bin="$(type -a -p just | grep -v '/mise/shims/' | head -1)"
[ -n "$just_bin" ] || just_bin="$(command -v just)"
if HOME="$install_home" "$just_bin" --quiet install >/dev/null 2>&1 \
  && [ -L "$install_home/.local/bin/claude-openrouter" ] \
  && [ ! -e "$COL_ROOT/~/.local/bin/claude-openrouter" ]; then
  ok "just install defaults to HOME"
else
  bad "just install defaults to HOME"
fi
rm -rf "$COL_ROOT/~"

# 26. Doctor covers type:"preset" profiles (provider-pinned) — in-sync + drift, non-fatal.
glm_synced="$(jq -nc '{data:{designated_version:{config:{model:"z-ai/glm-5.2",provider:{only:["fireworks"]}}}}}')"
glm_drift="$(jq -nc '{data:{designated_version:{config:{model:"z-ai/glm-5.2",provider:{only:["together"]}}}}}')"
dp_ok_file="$tmpstate/doctor-preset-ok.txt"
(
  PATH="$fakebin:$PATH"
  col_or_get() {
    case "$2" in
      key) printf '{"data":{"label":"smoke"}}' ;;
      credits) printf '{"data":{"total_credits":10,"total_usage":1}}' ;;
      presets/cc-glm-fireworks) printf '%s' "$glm_synced" ;;
      *) return 22 ;;
    esac
  }
  col_doctor "test" "flag"
) > "$dp_ok_file"
dp_ok_out="$(cat "$dp_ok_file")"
dp_drift_rc=0
dp_drift_file="$tmpstate/doctor-preset-drift.txt"
(
  PATH="$fakebin:$PATH"
  col_or_get() {
    case "$2" in
      key) printf '{"data":{"label":"smoke"}}' ;;
      credits) printf '{"data":{"total_credits":10,"total_usage":1}}' ;;
      presets/cc-glm-fireworks) printf '%s' "$glm_drift" ;;
      *) return 22 ;;
    esac
  }
  col_doctor "test" "flag"
) > "$dp_drift_file" || dp_drift_rc=$?
dp_drift_out="$(cat "$dp_drift_file")"
if [[ "$dp_ok_out" == *"preset 'cc-glm-fireworks' configured (profile 'glm-fireworks', model z-ai/glm-5.2)"* \
  && "$dp_ok_out" == *"model + provider in sync"* \
  && "$dp_drift_out" == *"differs from config"* && "$dp_drift_out" == *'"only":["together"]'* \
  && "$dp_drift_rc" -eq 0 ]]; then
  ok "doctor covers preset profiles"
else
  bad "doctor covers preset profiles" "drift_rc=$dp_drift_rc"
fi

# 27. Launcher pre-flight ABORTS when a preset-backed profile resolves to @preset
#     but the preset GET returns an HTTP error (404 -> missing on the account).
#     col_preset_check reads the http_code, so the stub prints the code for /presets.
chkbin="$tmpstate/preset-chkbin"; mkdir -p "$chkbin"
cat > "$chkbin/curl" <<'EOS'
#!/usr/bin/env bash
url=""
for arg in "$@"; do case "$arg" in https://*) url="$arg" ;; esac; done
case "$url" in
  */api/v1/key) exit 0 ;;          # pre-flight connectivity/key check passes
  */presets/*) printf '404' ;;     # preset GET -> HTTP 404 -> "not available"
  *) exit 0 ;;
esac
EOS
chmod +x "$chkbin/curl"
chk_state="$tmpstate/preset-chk-state"; mkdir -p "$chk_state/claude-openrouter/presets"
printf '{"preset_slug":"cc-glm-fireworks"}' > "$chk_state/claude-openrouter/presets/cc-glm-fireworks.json"
chk_out="$(PATH="$chkbin:$fakebin:$PATH" XDG_CONFIG_HOME="$chk_state" bin/claude-openrouter --profile glm-fireworks --key test -p hi 2>&1)"
chk_rc=$?
if [ "$chk_rc" -ne 0 ] && [[ "$chk_out" == *"not available on your OpenRouter account"* && "$chk_out" == *"claude-openrouter preset apply glm-fireworks"* ]]; then
  ok "preflight aborts on missing preset"
else
  bad "preflight aborts on missing preset" "rc=$chk_rc $chk_out"
fi

# 27b. Launcher pre-flight PROCEEDS when the preset exists (HTTP 200).
cat > "$chkbin/curl" <<'EOS'
#!/usr/bin/env bash
url=""
for arg in "$@"; do case "$arg" in https://*) url="$arg" ;; esac; done
case "$url" in
  */api/v1/key) exit 0 ;;
  */presets/*) printf '200' ;;
  *) exit 0 ;;
esac
EOS
chmod +x "$chkbin/curl"
chk2_out="$(PATH="$chkbin:$fakebin:$PATH" XDG_CONFIG_HOME="$chk_state" bin/claude-openrouter --profile glm-fireworks --key test -p hi 2>&1)"
chk2_rc=$?
if [ "$chk2_rc" -eq 0 ] && [[ "$chk2_out" != *"not available"* ]]; then
  ok "preflight proceeds when preset exists"
else
  bad "preflight proceeds when preset exists" "rc=$chk2_rc $chk2_out"
fi

# 27c. On a transport/network error (no HTTP response) the pre-flight WARNS but does
#      NOT abort — a blip must not be reported as 'preset not on your account'.
cat > "$chkbin/curl" <<'EOS'
#!/usr/bin/env bash
url=""
for arg in "$@"; do case "$arg" in https://*) url="$arg" ;; esac; done
case "$url" in
  */api/v1/key) exit 0 ;;
  */presets/*) exit 7 ;;           # curl transport failure (no http_code) -> unknown
  *) exit 0 ;;
esac
EOS
chmod +x "$chkbin/curl"
chk3_out="$(PATH="$chkbin:$fakebin:$PATH" XDG_CONFIG_HOME="$chk_state" bin/claude-openrouter --profile glm-fireworks --key test -p hi 2>&1)"
chk3_rc=$?
if [ "$chk3_rc" -eq 0 ] && [[ "$chk3_out" == *"couldn't verify preset"* && "$chk3_out" != *"not available on your OpenRouter account"* ]]; then
  ok "preflight warns (not abort) on network error"
else
  bad "preflight warns (not abort) on network error" "rc=$chk3_rc $chk3_out"
fi

# 27d. A retryable HTTP status (503) is treated as transient (warn + proceed), NOT as
#      a missing preset — so an OpenRouter-side blip doesn't tell users to re-run setup.
cat > "$chkbin/curl" <<'EOS'
#!/usr/bin/env bash
url=""
for arg in "$@"; do case "$arg" in https://*) url="$arg" ;; esac; done
case "$url" in
  */api/v1/key) exit 0 ;;
  */presets/*) printf '503' ;;     # transient server error -> unknown, not "missing"
  *) exit 0 ;;
esac
EOS
chmod +x "$chkbin/curl"
chk4_out="$(PATH="$chkbin:$fakebin:$PATH" XDG_CONFIG_HOME="$chk_state" bin/claude-openrouter --profile glm-fireworks --key test -p hi 2>&1)"
chk4_rc=$?
if [ "$chk4_rc" -eq 0 ] && [[ "$chk4_out" == *"couldn't verify preset"* && "$chk4_out" != *"not available on your OpenRouter account"* ]]; then
  ok "preflight treats 5xx as transient"
else
  bad "preflight treats 5xx as transient" "rc=$chk4_rc $chk4_out"
fi

# 28. 'models' — discovery over the public /models endpoint (no key needed).
#     Stub curl with a fixed catalog: a 1M-context paid model, a free model, a small one.
modbin="$tmpstate/modbin"; mkdir -p "$modbin"
cat > "$modbin/curl" <<'EOS'
#!/usr/bin/env bash
url=""
for arg in "$@"; do case "$arg" in https://*) url="$arg" ;; esac; done
case "$url" in
  */v1/models)
    cat <<'JSON'
{"data":[
 {"id":"z-ai/glm-5.2","name":"Z.ai: GLM 5.2","context_length":1048576,"pricing":{"prompt":"0.00000095","completion":"0.000003"}},
 {"id":"vendor/gratis","name":"Vendor: Free Model","context_length":131072,"pricing":{"prompt":"0","completion":"0"}},
 {"id":"acme/tiny","name":"Acme: Tiny","context_length":8000,"pricing":{"prompt":"0.0000006","completion":"0.0000022"}}
]}
JSON
    ;;
  *) printf '{"error":{"message":"unexpected URL"}}' ;;
esac
EOS
chmod +x "$modbin/curl"
run_models() { env -u OPENROUTER_API_KEY PATH="$modbin:$PATH" bin/claude-openrouter models "$@" 2>&1; }

# match on id, formatting ($/1M + M-context), and both hint lines — with NO key set
m_out="$(run_models glm)"
# shellcheck disable=SC2016  # $0.95/$3.00 is a literal price string, not an expansion
if [[ "$m_out" == *"z-ai/glm-5.2"* && "$m_out" == *"1.0M ctx"* && "$m_out" == *'$0.95/$3.00 per 1M'* \
   && "$m_out" == *"1 of 3 matching"* && "$m_out" == *"--backend"* && "$m_out" == *"see 'claude-openrouter modes'"* \
   && "$m_out" != *"vendor/gratis"* ]]; then
  ok "models: filter by id + format + hints"
else
  bad "models: filter by id + format + hints" "$m_out"
fi

# match on NAME, case-insensitively; a fully-free model reads 'free' (not 'free/free per 1M')
m_free="$(run_models FREE)"
if [[ "$m_free" == *"vendor/gratis"* && "$m_free" == *"131K ctx  free"* \
   && "$m_free" != *"free/free"* && "$m_free" != *"z-ai/glm-5.2"* ]]; then
  ok "models: name match (case-insensitive) + free pricing"
else
  bad "models: name match (case-insensitive) + free pricing" "$m_free"
fi

# 28c. A 200 carrying a non-JSON body must fail cleanly (col_die), never as a raw jq
#      parse error — same guarantee setup.sh already makes for preset responses.
junkbin="$tmpstate/junkbin"; mkdir -p "$junkbin"
cat > "$junkbin/curl" <<'EOS'
#!/usr/bin/env bash
printf '<html>502 bad gateway</html>'
EOS
chmod +x "$junkbin/curl"
j_out="$(env -u OPENROUTER_API_KEY PATH="$junkbin:$PATH" bin/claude-openrouter models glm 2>&1)"
j_rc=$?
jp_out="$(PATH="$junkbin:$PATH" bin/claude-openrouter presets --key test 2>&1)"
jp_rc=$?
if [ "$j_rc" -ne 0 ] && [[ "$j_out" == *"unreadable /models response"* && "$j_out" != *"parse error"* ]] \
  && [ "$jp_rc" -ne 0 ] && [[ "$jp_out" == *"unreadable /presets response"* && "$jp_out" != *"parse error"* ]]; then
  ok "models/presets: non-JSON 200 fails cleanly"
else
  bad "models/presets: non-JSON 200 fails cleanly" "models(rc=$j_rc)=$j_out presets(rc=$jp_rc)=$jp_out"
fi

# no query lists all; K-context formatting present
m_all="$(run_models)"
if [[ "$m_all" == *"3 total"* && "$m_all" == *"z-ai/glm-5.2"* && "$m_all" == *"vendor/gratis"* \
   && "$m_all" == *"acme/tiny"* && "$m_all" == *"131K ctx"* ]]; then
  ok "models: no query lists all"
else
  bad "models: no query lists all" "$m_all"
fi

# --json emits exactly the filtered set
m_json="$(env -u OPENROUTER_API_KEY PATH="$modbin:$PATH" bin/claude-openrouter models glm --json 2>/dev/null)"
if [ "$(printf '%s' "$m_json" | jq -r 'length')" = "1" ] \
  && [ "$(printf '%s' "$m_json" | jq -r '.[0].id')" = "z-ai/glm-5.2" ]; then
  ok "models: --json filtered array"
else
  bad "models: --json filtered array" "$m_json"
fi

# 28b. no match is grep-style: stderr message + exit 1 (and [] + exit 1 for --json)
nm_err="$(env -u OPENROUTER_API_KEY PATH="$modbin:$PATH" bin/claude-openrouter models zzz 2>&1 >/dev/null)"
nm_rc=$?
nmj="$(env -u OPENROUTER_API_KEY PATH="$modbin:$PATH" bin/claude-openrouter models zzz --json 2>/dev/null)"
nmj_rc=$?
if [ "$nm_rc" -eq 1 ] && [[ "$nm_err" == *"no models match 'zzz'"* ]] \
  && [ "$nmj_rc" -eq 1 ] && [ "$(printf '%s' "$nmj" | tr -d '[:space:]')" = "[]" ]; then
  ok "models: no match -> stderr + exit 1"
else
  bad "models: no match -> stderr + exit 1" "rc=$nm_rc jsonrc=$nmj_rc err=$nm_err json=$nmj"
fi

# 28d. 'providers' — who serves a model, at what ctx/price/uptime. Stub the endpoints
#      payload with a deliberate spread so each sort is distinguishable.
#      NOTE: OpenRouter returns throughput/latency as null on this endpoint (verified
#      live across several models), so there is no speed column — uptime is the signal.
provbin="$tmpstate/provbin"; mkdir -p "$provbin"
cat > "$provbin/curl" <<'EOS'
#!/usr/bin/env bash
url=""
for arg in "$@"; do case "$arg" in https://*) url="$arg" ;; esac; done
case "$url" in
  */models/zed/nope/endpoints) exit 22 ;;
  */endpoints)
    cat <<'JSON'
{"data":{"endpoints":[
 {"tag":"zeta/fp8","context_length":131072,"pricing":{"prompt":"0.000003","completion":"0.00001"},"uptime_last_30m":91.2,"throughput_last_30m":null},
 {"tag":"alpha/fp4","context_length":1048576,"pricing":{"prompt":"0.0000009","completion":"0.000003"},"uptime_last_30m":99.94,"throughput_last_30m":null},
 {"tag":"mid","context_length":262144,"pricing":{"prompt":"0.000002","completion":"0.000005"},"uptime_last_30m":97.0,"throughput_last_30m":null}
]}}
JSON
    ;;
  *) printf '{"error":{"message":"unexpected URL"}}' ;;
esac
EOS
chmod +x "$provbin/curl"
run_prov() { env -u OPENROUTER_API_KEY PATH="$provbin:$PATH" bin/claude-openrouter providers "$@" 2>&1; }
first_tag() { run_prov "$@" | sed -n '2p' | awk '{print $1}'; }

v_out="$(run_prov acme/model)"
# default alpha; renders ctx + per-1M price + uptime; no dead speed column; pin hint
# shellcheck disable=SC2016  # $0.90/$3.00 is a literal price string, not an expansion
if [[ "$(first_tag acme/model)" = "alpha/fp4" && "$v_out" == *"3 serving"* && "$v_out" == *"1.0M ctx"* \
   && "$v_out" == *'$0.90/$3.00 per 1M'* && "$v_out" == *"99.9% up"* \
   && "$v_out" != *"tok/s"* && "$v_out" == *"provider"*"only"* ]]; then
  ok "providers: default alpha + ctx/price/uptime + pin hint"
else
  bad "providers: default alpha + ctx/price/uptime + pin hint" "$v_out"
fi

# each sort orders by its own key (and they differ from one another)
if [ "$(first_tag acme/model --sort cheapest)" = "alpha/fp4" ] \
  && [ "$(first_tag acme/model --sort expensive)" = "zeta/fp8" ] \
  && [ "$(first_tag acme/model --sort reliable)" = "alpha/fp4" ] \
  && [ "$(first_tag acme/model --sort alpha)" = "alpha/fp4" ]; then
  ok "providers: --sort cheapest/expensive/reliable"
else
  bad "providers: --sort" "cheap=$(first_tag acme/model --sort cheapest) exp=$(first_tag acme/model --sort expensive) rel=$(first_tag acme/model --sort reliable)"
fi

# --json passthrough, missing-slug and bad-sort rejection, unknown model
vj="$(env -u OPENROUTER_API_KEY PATH="$provbin:$PATH" bin/claude-openrouter providers acme/model --json 2>/dev/null)"
v_noslug="$(run_prov)"; v_noslug_rc=$?
v_badsort="$(run_prov acme/model --sort fastest)"; v_badsort_rc=$?
v_404="$(run_prov zed/nope)"; v_404_rc=$?
if [ "$(printf '%s' "$vj" | jq -r 'length')" = "3" ] \
  && [ "$v_noslug_rc" -ne 0 ] && [[ "$v_noslug" == *"needs a model slug"* ]] \
  && [ "$v_badsort_rc" -ne 0 ] && [[ "$v_badsort" == *"unknown --sort 'fastest'"* ]] \
  && [ "$v_404_rc" -ne 0 ] && [[ "$v_404" == *"no providers found"* ]]; then
  ok "providers: --json + arg/sort/404 errors"
else
  bad "providers: --json + arg/sort/404 errors" "json=$vj noslug=$v_noslug badsort=$v_badsort 404=$v_404"
fi

# 29. 'presets' — account listing cross-referenced against config profiles:
#     linked / orphan (on account, unreferenced) / missing (referenced, absent upstream).
prebin="$tmpstate/presets-bin"; mkdir -p "$prebin"
cat > "$prebin/curl" <<'EOS'
#!/usr/bin/env bash
url=""
for arg in "$@"; do case "$arg" in https://*) url="$arg" ;; esac; done
case "$url" in
  */v1/presets) printf '{"data":[{"slug":"cc-fusion"},{"slug":"cc-orphan"}]}' ;;
  *) printf '{"error":{"message":"unexpected URL"}}' ;;
esac
EOS
chmod +x "$prebin/curl"
p_out="$(PATH="$prebin:$PATH" bin/claude-openrouter presets --key test 2>&1)"
if [[ "$p_out" == *"2 total"* \
   && "$p_out" == *"cc-fusion"*"← profile: fusion"* \
   && "$p_out" == *"cc-orphan"*"orphan"* \
   && "$p_out" == *"cc-glm-fireworks"*"missing"*"glm-fireworks"* ]]; then
  ok "presets: linked / orphan / missing"
else
  bad "presets: linked / orphan / missing" "$p_out"
fi

p_json="$(PATH="$prebin:$PATH" bin/claude-openrouter presets --key test --json 2>/dev/null)"
if [ "$(printf '%s' "$p_json" | jq -r 'length')" = "2" ] \
  && [ "$(printf '%s' "$p_json" | jq -r '.[0].slug')" = "cc-fusion" ]; then
  ok "presets: --json account array"
else
  bad "presets: --json account array" "$p_json"
fi

# 29b. Canonical 'preset' group: deterministic list formats and targeted view.
manage_bin="$tmpstate/preset-manage-bin"; mkdir -p "$manage_bin"
manage_body_log="$tmpstate/preset-manage-bodies.jsonl"
cat > "$manage_bin/curl" <<'EOS'
#!/usr/bin/env bash
url="" body="" status_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    https://*) url="$1"; shift ;;
    -d) body="$2"; shift 2 ;;
    -w) status_only=1; shift 2 ;;
    -o) shift 2 ;;
    *) shift ;;
  esac
done
case "$url" in
  */v1/key) if [ "$status_only" -eq 1 ]; then printf '%s' "${PRESET_KEY_STATUS:-200}"; else printf '{"data":{"label":"smoke"}}'; fi ;;
  */v1/credits) printf '{"data":{"total_credits":10,"total_usage":1}}' ;;
  */v1/presets)
    printf '{"data":[{"slug":"cc-orphan"},{"slug":"cc-fusion"}]}'
    ;;
  */v1/presets/cc-fusion)
    if [ "$status_only" -eq 1 ]; then printf '200'; else
      printf '%s' '{"data":{"slug":"cc-fusion","designated_version":{"config":{"model":"openrouter/fusion","tools":[{"type":"openrouter:fusion","parameters":{"analysis_models":["~anthropic/claude-opus-latest","~openai/gpt-latest","~google/gemini-pro-latest","deepseek/deepseek-v3.2","qwen/qwen3-coder-plus"],"model":"~anthropic/claude-opus-latest"}}],"tool_choice":"required"}}}}'
    fi
    ;;
  */v1/presets/cc-orphan)
    if [ "$status_only" -eq 1 ]; then printf '200'; else
      printf '%s' '{"data":{"slug":"cc-orphan","designated_version":{"config":{"model":"acme/orphan","provider":{"only":["acme"]}}}}}'
    fi
    ;;
  */v1/presets/*/chat/completions)
    [ -n "${PRESET_BODY_LOG:-}" ] && printf '%s\n' "$body" >> "$PRESET_BODY_LOG"
    cfg="$(printf '%s' "$body" | jq -c '{model, provider:(.provider//{}), tools:(.tools//[]), tool_choice:(.tool_choice//null)}')"
    printf '{"data":{"designated_version":{"config":%s}}}' "$cfg"
    ;;
  */v1/presets/*) if [ "$status_only" -eq 1 ]; then printf '404'; else return 22; fi ;;
  *) return 22 ;;
esac
EOS
chmod +x "$manage_bin/curl"

manage_env=(env PATH="$manage_bin:$PATH" PRESET_BODY_LOG="$manage_body_log" OPENROUTER_API_KEY=test)
pl_names="$("${manage_env[@]}" bin/claude-openrouter preset list -o name 2>/dev/null)"
pl_json="$("${manage_env[@]}" bin/claude-openrouter preset list --json 2>/dev/null)"
pv_human="$("${manage_env[@]}" bin/claude-openrouter preset view fusion 2>/dev/null)"
pv_orphan="$("${manage_env[@]}" bin/claude-openrouter preset view --slug cc-orphan --json 2>/dev/null)"
if [ "$pl_names" = $'cc-fusion\ncc-orphan' ] \
  && [ "$(printf '%s' "$pl_json" | jq -r '.[0].slug')" = "cc-fusion" ] \
  && [[ "$pv_human" == *"profile: fusion"* && "$pv_human" == *"status: in-sync"* \
       && "$pv_human" == *"panel:"* && "$pv_human" == *"judge: ~anthropic/claude-opus-latest"* ]] \
  && [ "$(printf '%s' "$pv_orphan" | jq -r '.profile')" = "null" ] \
  && [ "$(printf '%s' "$pv_orphan" | jq -r '.status')" = "orphan" ] \
  && [ "$(printf '%s' "$pv_orphan" | jq -r '.remote.designated_version.config.model')" = "acme/orphan" ]; then
  ok "preset list/view: human + machine output"
else
  bad "preset list/view: human + machine output" "names=$pl_names view=$pv_human orphan=$pv_orphan"
fi

auth_error="$tmpstate/preset-auth-error.txt"
"${manage_env[@]}" PRESET_KEY_STATUS=401 bin/claude-openrouter preset list --json \
  2> "$auth_error" >/dev/null
auth_error_rc=$?
network_error="$tmpstate/preset-network-error.txt"
"${manage_env[@]}" PRESET_KEY_STATUS=000 bin/claude-openrouter preset list --json \
  2> "$network_error" >/dev/null
network_error_rc=$?
if [ "$auth_error_rc" -eq 4 ] && [ "$(jq -r '.error.code' "$auth_error")" = "auth_failed" ] \
  && [ "$network_error_rc" -eq 1 ] \
  && [ "$(jq -r '.error.code' "$network_error")" = "remote_unavailable" ]; then
  ok "preset list: auth and network failures separated"
else
  bad "preset list: auth and network failures separated" \
    "auth=$auth_error_rc network=$network_error_rc"
fi

"${manage_env[@]}" bin/claude-openrouter preset >/dev/null 2>&1; pg_rc=$?
"${manage_env[@]}" bin/claude-openrouter preset view missing >/dev/null 2>&1; pv_missing_rc=$?
"${manage_env[@]}" bin/claude-openrouter preset view --slug cc-missing >/dev/null 2>&1; ps_missing_rc=$?
"${manage_env[@]}" bin/claude-openrouter preset nope >/dev/null 2>&1; pu_rc=$?
if [ "$pg_rc" -eq 2 ] && [ "$pv_missing_rc" -eq 3 ] \
  && [ "$ps_missing_rc" -eq 3 ] && [ "$pu_rc" -eq 2 ]; then
  ok "preset group: usage/not-found exit codes"
else
  bad "preset group: usage/not-found exit codes" \
    "group=$pg_rc profile-missing=$pv_missing_rc preset-missing=$ps_missing_rc unknown=$pu_rc"
fi

preset_help_ok=1
for preset_action in list view create update apply; do
  help_out="$(bin/claude-openrouter preset "$preset_action" --help 2>&1)" || preset_help_ok=0
  [[ "$help_out" == *"Usage:"* ]] || preset_help_ok=0
done
bin/claude-openrouter --config >/dev/null 2>&1; global_config_rc=$?
bin/claude-openrouter doctor --unknown >/dev/null 2>&1; doctor_unknown_rc=$?
bin/claude-openrouter presets --unknown >/dev/null 2>&1; presets_unknown_rc=$?
bin/claude-openrouter preset list --key secret >/dev/null 2>&1; canonical_key_rc=$?
if [ "$preset_help_ok" -eq 1 ] && [ "$global_config_rc" -eq 2 ] \
  && [ "$doctor_unknown_rc" -eq 2 ] && [ "$presets_unknown_rc" -eq 2 ] \
  && [ "$canonical_key_rc" -eq 2 ]; then
  ok "preset group: help + strict argument parsing"
else
  bad "preset group: help + strict argument parsing" \
    "help=$preset_help_ok config=$global_config_rc doctor=$doctor_unknown_rc legacy=$presets_unknown_rc key=$canonical_key_rc"
fi

# 29c. Non-interactive create/update persist config atomically and apply remotely.
manage_cfg="$tmpstate/preset-manage.json"
cp "$COL_CONFIG" "$manage_cfg"
manage_state="$tmpstate/preset-manage-state"
create_out="$(XDG_CONFIG_HOME="$manage_state" "${manage_env[@]}" bin/claude-openrouter preset create team-glm \
  --config "$manage_cfg" --type preset --preset-slug cc-team-glm \
  --model z-ai/glm-5.2 --provider fireworks --fallback z-ai/glm-5.2 \
  --no-input --yes 2>&1)"
if jq -e '.profiles["team-glm"] == {type:"preset",preset_slug:"cc-team-glm",model:"z-ai/glm-5.2",provider:{only:["fireworks"]},fallback:"z-ai/glm-5.2"}' "$manage_cfg" >/dev/null \
  && [ -f "$manage_state/claude-openrouter/presets/cc-team-glm.json" ] \
  && jq -e 'select(.model=="z-ai/glm-5.2" and .provider.only==["fireworks"])' "$manage_body_log" >/dev/null \
  && [[ "$create_out" == *"config saved:"* && "$create_out" == *"preset 'cc-team-glm' is ready"* ]]; then
  ok "preset create: config + remote + marker"
else
  bad "preset create: config + remote + marker" "$create_out"
fi

XDG_CONFIG_HOME="$manage_state" "${manage_env[@]}" bin/claude-openrouter preset create team-glm \
  --config "$manage_cfg" --type preset --preset-slug cc-team-glm --model z-ai/glm-5.2 \
  --provider fireworks --no-input --yes >/dev/null 2>&1
create_conflict_rc=$?

before_dry="$(shasum -a 256 "$manage_cfg" | awk '{print $1}')"
dry_out="$(XDG_CONFIG_HOME="$manage_state" "${manage_env[@]}" bin/claude-openrouter preset update team-glm \
  --config "$manage_cfg" --provider together --dry-run --no-input 2>&1)"
after_dry="$(shasum -a 256 "$manage_cfg" | awk '{print $1}')"
if [ "$create_conflict_rc" -eq 5 ] && [ "$before_dry" = "$after_dry" ] \
  && [[ "$dry_out" == *"Plan:"* && "$dry_out" == *"provider.only: together"* ]]; then
  ok "preset mutation: conflict + dry-run"
else
  bad "preset mutation: conflict + dry-run" "conflict=$create_conflict_rc dry=$dry_out"
fi

jq '.profiles["team-glm"].description = "retain me"
    | .profiles["team-glm"].provider.allow_fallbacks = false' \
  "$manage_cfg" > "$manage_cfg.extra"
mv "$manage_cfg.extra" "$manage_cfg"
update_out="$(XDG_CONFIG_HOME="$manage_state" "${manage_env[@]}" bin/claude-openrouter preset update team-glm \
  --config "$manage_cfg" --provider together --no-input --yes 2>&1)"
if [ "$(jq -r '.profiles["team-glm"].provider.only[0]' "$manage_cfg")" = "together" ] \
  && jq -e '.profiles["team-glm"].description == "retain me"
      and .profiles["team-glm"].provider.allow_fallbacks == false' "$manage_cfg" >/dev/null \
  && [ -f "$manage_cfg.bak" ] && [[ "$update_out" == *"preset 'cc-team-glm' is ready"* ]]; then
  ok "preset update: retains unmanaged fields + writes backup"
else
  bad "preset update: retains unmanaged fields + writes backup" "$update_out"
fi

apply_cfg="$tmpstate/preset-apply.json"; cp "$COL_CONFIG" "$apply_cfg"
apply_state="$tmpstate/preset-apply-state"
apply_out="$(XDG_CONFIG_HOME="$apply_state" "${manage_env[@]}" bin/claude-openrouter \
  --config "$apply_cfg" preset apply glm-fireworks 2>&1)"
if [ -f "$apply_state/claude-openrouter/presets/cc-glm-fireworks.json" ] \
  && [[ "$apply_out" == *"preset 'cc-glm-fireworks' is ready"* ]]; then
  ok "preset apply: global --config + one profile"
else
  bad "preset apply: global --config + one profile" "$apply_out"
fi

# 29d. Fusion creation, validation failures, locking, and machine errors.
fusion_cfg="$tmpstate/preset-fusion.json"; cp "$COL_CONFIG" "$fusion_cfg"
fusion_state="$tmpstate/preset-fusion-state"
fusion_out="$(XDG_CONFIG_HOME="$fusion_state" "${manage_env[@]}" bin/claude-openrouter preset create team-fusion \
  --config "$fusion_cfg" --type fusion --preset-slug cc-team-fusion \
  --panel-model acme/one --panel-model acme/two --judge-model acme/judge \
  --fallback openrouter/fusion --no-input --yes 2>&1)"
if jq -e '.profiles["team-fusion"].panel_models == ["acme/one","acme/two"]
    and .profiles["team-fusion"].judge_model == "acme/judge"' "$fusion_cfg" >/dev/null \
  && [ -f "$fusion_state/claude-openrouter/presets/cc-team-fusion.json" ] \
  && [[ "$fusion_out" == *"preset 'cc-team-fusion' is ready"* ]]; then
  ok "preset create: fusion profile"
else
  bad "preset create: fusion profile" "$fusion_out"
fi

validation_cfg="$tmpstate/preset-validation.json"; cp "$COL_CONFIG" "$validation_cfg"
validation_before="$(shasum -a 256 "$validation_cfg" | awk '{print $1}')"
"${manage_env[@]}" bin/claude-openrouter preset create incomplete --config "$validation_cfg" \
  --type preset --preset-slug cc-incomplete --no-input --yes >/dev/null 2>&1
missing_fields_rc=$?
"${manage_env[@]}" bin/claude-openrouter preset create empty-provider --config "$validation_cfg" \
  --type preset --preset-slug cc-empty-provider --model acme/model --provider , \
  --no-input --yes >/dev/null 2>&1
empty_provider_rc=$?
"${manage_env[@]}" bin/claude-openrouter preset create local-link --config "$validation_cfg" \
  --type preset --preset-slug cc-fusion --model acme/model --provider acme \
  --no-input --yes >/dev/null 2>&1
local_conflict_rc=$?
"${manage_env[@]}" bin/claude-openrouter preset create orphan-link --config "$validation_cfg" \
  --type preset --preset-slug cc-orphan --model acme/model --provider acme \
  --no-input --yes >/dev/null 2>&1
remote_conflict_rc=$?
"${manage_env[@]}" bin/claude-openrouter preset update fusion --config "$validation_cfg" \
  --preset-slug cc-orphan --no-input --yes >/dev/null 2>&1
update_remote_conflict_rc=$?
validation_after="$(shasum -a 256 "$validation_cfg" | awk '{print $1}')"
mkdir "$validation_cfg.lock"
"${manage_env[@]}" bin/claude-openrouter preset create locked --config "$validation_cfg" \
  --type preset --preset-slug cc-locked --model acme/model --provider acme \
  --no-input --yes >/dev/null 2>&1
locked_rc=$?
rmdir "$validation_cfg.lock"
json_error="$tmpstate/preset-json-error.txt"
"${manage_env[@]}" bin/claude-openrouter preset list --json --config 2> "$json_error" >/dev/null
json_error_rc=$?
invalid_json_cfg="$tmpstate/preset-invalid.json"
printf '{' > "$invalid_json_cfg"
invalid_json_error="$tmpstate/preset-invalid-error.txt"
"${manage_env[@]}" bin/claude-openrouter preset list -o json --config "$invalid_json_cfg" \
  2> "$invalid_json_error" >/dev/null
invalid_json_rc=$?
if [ "$missing_fields_rc" -eq 2 ] && [ "$empty_provider_rc" -eq 2 ] \
  && [ "$local_conflict_rc" -eq 5 ] && [ "$remote_conflict_rc" -eq 5 ] \
  && [ "$update_remote_conflict_rc" -eq 5 ] \
  && [ "$locked_rc" -eq 5 ] && [ "$validation_before" = "$validation_after" ] \
  && [ "$json_error_rc" -eq 2 ] \
  && [ "$(jq -r '.error.code' "$json_error" 2>/dev/null)" = "usage" ] \
  && [ "$invalid_json_rc" -eq 1 ] \
  && [ "$(jq -r '.error.code' "$invalid_json_error" 2>/dev/null)" = "invalid_config" ]; then
  ok "preset mutation: validation/remote conflict/lock/errors"
else
  bad "preset mutation: validation/remote conflict/lock/errors" \
    "missing=$missing_fields_rc empty=$empty_provider_rc local=$local_conflict_rc remote=$remote_conflict_rc update-remote=$update_remote_conflict_rc lock=$locked_rc json=$json_error_rc invalid=$invalid_json_rc"
fi

# 29d2. Additive fusion panel edits keep the rest of the panel.
add_out="$(XDG_CONFIG_HOME="$fusion_state" "${manage_env[@]}" bin/claude-openrouter preset update team-fusion \
  --config "$fusion_cfg" --add-panel-model acme/three --no-input --yes 2>&1)"; add_rc=$?
if [ "$add_rc" -eq 0 ] \
  && jq -e '.profiles["team-fusion"].panel_models == ["acme/one","acme/two","acme/three"]' "$fusion_cfg" >/dev/null \
  && jq -e 'select(.tools[0].parameters.analysis_models == ["acme/one","acme/two","acme/three"])' "$manage_body_log" >/dev/null \
  && [[ "$add_out" == *"preset 'cc-team-fusion' is ready"* ]]; then
  ok "preset update: --add-panel-model keeps the panel + syncs"
else
  bad "preset update: --add-panel-model keeps the panel + syncs" "$add_out"
fi

XDG_CONFIG_HOME="$fusion_state" "${manage_env[@]}" bin/claude-openrouter preset update team-fusion \
  --config "$fusion_cfg" --add-panel-model acme/two --no-input --yes >/dev/null 2>&1
idem_rc=$?
combo_out="$(XDG_CONFIG_HOME="$fusion_state" "${manage_env[@]}" bin/claude-openrouter preset update team-fusion \
  --config "$fusion_cfg" --add-panel-model acme/four --remove-panel-model acme/one --no-input --yes 2>&1)"
combo_rc=$?
if [ "$idem_rc" -eq 0 ] && [ "$combo_rc" -eq 0 ] \
  && jq -e '.profiles["team-fusion"].panel_models == ["acme/two","acme/three","acme/four"]' "$fusion_cfg" >/dev/null \
  && [[ "$combo_out" == *"preset 'cc-team-fusion' is ready"* ]]; then
  ok "preset update: idempotent add + combined add/remove"
else
  bad "preset update: idempotent add + combined add/remove" "idem=$idem_rc combo=$combo_rc $combo_out"
fi

panel_before="$(jq -c '.profiles["team-fusion"].panel_models' "$fusion_cfg")"
XDG_CONFIG_HOME="$fusion_state" "${manage_env[@]}" bin/claude-openrouter preset update team-fusion \
  --config "$fusion_cfg" --remove-panel-model acme/nope --no-input --yes >/dev/null 2>&1
rm_missing_rc=$?
XDG_CONFIG_HOME="$fusion_state" "${manage_env[@]}" bin/claude-openrouter preset update team-fusion \
  --config "$fusion_cfg" --remove-panel-model acme/two --remove-panel-model acme/three \
  --remove-panel-model acme/four --no-input --yes >/dev/null 2>&1
rm_all_rc=$?
XDG_CONFIG_HOME="$fusion_state" "${manage_env[@]}" bin/claude-openrouter preset update team-fusion \
  --config "$fusion_cfg" --panel-model acme/x --add-panel-model acme/y --no-input --yes >/dev/null 2>&1
mix_rc=$?
XDG_CONFIG_HOME="$fusion_state" "${manage_env[@]}" bin/claude-openrouter preset create add-probe \
  --config "$validation_cfg" --type fusion --preset-slug cc-add-probe \
  --panel-model acme/one --judge-model acme/judge --add-panel-model acme/two \
  --no-input --yes >/dev/null 2>&1
create_add_rc=$?
XDG_CONFIG_HOME="$manage_state" "${manage_env[@]}" bin/claude-openrouter preset update team-glm \
  --config "$manage_cfg" --add-panel-model acme/x --no-input --yes >/dev/null 2>&1
preset_add_rc=$?
panel_after="$(jq -c '.profiles["team-fusion"].panel_models' "$fusion_cfg")"
if [ "$rm_missing_rc" -eq 1 ] && [ "$rm_all_rc" -eq 2 ] && [ "$mix_rc" -eq 2 ] \
  && [ "$create_add_rc" -eq 2 ] && [ "$preset_add_rc" -eq 2 ] \
  && [ "$panel_before" = "$panel_after" ]; then
  ok "preset update: additive misuse rejected, panel untouched"
else
  bad "preset update: additive misuse rejected, panel untouched" \
    "missing=$rm_missing_rc all=$rm_all_rc mix=$mix_rc create=$create_add_rc preset=$preset_add_rc panel=$panel_after"
fi

dry_add_before="$(shasum -a 256 "$fusion_cfg" | awk '{print $1}')"
dry_add_out="$(XDG_CONFIG_HOME="$fusion_state" "${manage_env[@]}" bin/claude-openrouter preset update team-fusion \
  --config "$fusion_cfg" --add-panel-model acme/five --dry-run --no-input 2>&1)"
dry_add_after="$(shasum -a 256 "$fusion_cfg" | awk '{print $1}')"
if [[ "$dry_add_out" == *"Plan:"* && "$dry_add_out" == *"acme/five"* ]] \
  && [ "$dry_add_before" = "$dry_add_after" ] \
  && jq -e '.profiles["team-fusion"].panel_models == ["acme/two","acme/three","acme/four"]' "$fusion_cfg" >/dev/null; then
  ok "preset update: additive dry-run previews without writing"
else
  bad "preset update: additive dry-run previews without writing" "$dry_add_out"
fi

# 29d3. Fusion tuning knobs persist locally and remotely.
knob_cfg="$tmpstate/preset-knobs.json"; cp "$COL_CONFIG" "$knob_cfg"
knob_out="$(XDG_CONFIG_HOME="$fusion_state" "${manage_env[@]}" bin/claude-openrouter preset create team-knobs \
  --config "$knob_cfg" --type fusion --preset-slug cc-team-knobs \
  --panel-model acme/one --panel-model acme/two --judge-model acme/judge \
  --max-tool-calls 2 --temperature 0.7 --max-completion-tokens 8000 \
  --reasoning-effort medium --reasoning-max-tokens 2000 \
  --fallback openrouter/fusion --no-input --yes 2>&1)"; knob_rc=$?
if [ "$knob_rc" -eq 0 ] \
  && jq -e '.profiles["team-knobs"] == {type:"fusion",preset_slug:"cc-team-knobs",panel_models:["acme/one","acme/two"],judge_model:"acme/judge",max_tool_calls:2,temperature:0.7,max_completion_tokens:8000,reasoning:{effort:"medium",max_tokens:2000},fallback:"openrouter/fusion"}' "$knob_cfg" >/dev/null \
  && jq -e 'select(.tools[0].parameters.max_tool_calls == 2
      and .tools[0].parameters.temperature == 0.7
      and .tools[0].parameters.max_completion_tokens == 8000
      and .tools[0].parameters.reasoning == {effort:"medium",max_tokens:2000})' "$manage_body_log" >/dev/null \
  && [[ "$knob_out" == *"preset 'cc-team-knobs' is ready"* ]]; then
  ok "preset create: fusion knobs in config + remote body"
else
  bad "preset create: fusion knobs in config + remote body" "$knob_out"
fi

knob_up_out="$(XDG_CONFIG_HOME="$fusion_state" "${manage_env[@]}" bin/claude-openrouter preset update team-knobs \
  --config "$knob_cfg" --temperature 1.5 --no-input --yes 2>&1)"; knob_up_rc=$?
if [ "$knob_up_rc" -eq 0 ] \
  && jq -e '.profiles["team-knobs"].temperature == 1.5
      and .profiles["team-knobs"].max_tool_calls == 2
      and .profiles["team-knobs"].panel_models == ["acme/one","acme/two"]' "$knob_cfg" >/dev/null \
  && jq -e 'select(.tools[0].parameters.temperature == 1.5
      and .tools[0].parameters.max_tool_calls == 2)' "$manage_body_log" >/dev/null \
  && [[ "$knob_up_out" == *"preset 'cc-team-knobs' is ready"* ]]; then
  ok "preset update: one knob changes, rest inherited + synced"
else
  bad "preset update: one knob changes, rest inherited + synced" "$knob_up_out"
fi

knobs_before="$(shasum -a 256 "$knob_cfg" | awk '{print $1}')"
XDG_CONFIG_HOME="$fusion_state" "${manage_env[@]}" bin/claude-openrouter preset create bad-mtc \
  --config "$knob_cfg" --type fusion --preset-slug cc-bad-mtc \
  --panel-model acme/one --judge-model acme/judge --max-tool-calls 17 \
  --no-input --yes >/dev/null 2>&1
bad_mtc_rc=$?
XDG_CONFIG_HOME="$fusion_state" "${manage_env[@]}" bin/claude-openrouter preset create bad-temp \
  --config "$knob_cfg" --type fusion --preset-slug cc-bad-temp \
  --panel-model acme/one --judge-model acme/judge --temperature 2.5 \
  --no-input --yes >/dev/null 2>&1
bad_temp_rc=$?
XDG_CONFIG_HOME="$fusion_state" "${manage_env[@]}" bin/claude-openrouter preset create bad-mct \
  --config "$knob_cfg" --type fusion --preset-slug cc-bad-mct \
  --panel-model acme/one --judge-model acme/judge --max-completion-tokens 0 \
  --no-input --yes >/dev/null 2>&1
bad_mct_rc=$?
XDG_CONFIG_HOME="$manage_state" "${manage_env[@]}" bin/claude-openrouter preset update team-glm \
  --config "$manage_cfg" --max-tool-calls 2 --no-input --yes >/dev/null 2>&1
preset_knob_rc=$?
knobs_after="$(shasum -a 256 "$knob_cfg" | awk '{print $1}')"
if [ "$bad_mtc_rc" -eq 2 ] && [ "$bad_temp_rc" -eq 2 ] && [ "$bad_mct_rc" -eq 2 ] \
  && [ "$preset_knob_rc" -eq 2 ] && [ "$knobs_before" = "$knobs_after" ]; then
  ok "preset mutation: knob range/type rejections, config untouched"
else
  bad "preset mutation: knob range/type rejections, config untouched" \
    "mtc=$bad_mtc_rc temp=$bad_temp_rc mct=$bad_mct_rc preset=$preset_knob_rc"
fi

# 29e. A remote failure retains valid local config, removes readiness, and gives recovery.
fail_bin="$tmpstate/preset-fail-bin"; mkdir -p "$fail_bin"
cat > "$fail_bin/curl" <<'EOS'
#!/usr/bin/env bash
url="" status_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    https://*) url="$1"; shift ;;
    -w) status_only=1; shift 2 ;;
    -o|-d) shift 2 ;;
    *) shift ;;
  esac
done
case "$url" in
  */v1/key) if [ "$status_only" -eq 1 ]; then printf '200'; else printf '{"data":{"label":"smoke"}}'; fi ;;
  */v1/credits) printf '{"data":{"total_credits":10,"total_usage":1}}' ;;
  */v1/presets/*/chat/completions) printf '{"error":{"message":"rejected by smoke"}}' ;;
  */v1/presets/*) if [ "$status_only" -eq 1 ]; then printf '404'; else return 22; fi ;;
  *) return 22 ;;
esac
EOS
chmod +x "$fail_bin/curl"
fail_cfg="$tmpstate/preset-failure.json"; cp "$COL_CONFIG" "$fail_cfg"
fail_state="$tmpstate/preset-failure-state"
fail_out="$(PATH="$fail_bin:$PATH" OPENROUTER_API_KEY=test XDG_CONFIG_HOME="$fail_state" \
  bin/claude-openrouter preset create fail-glm --config "$fail_cfg" \
  --type preset --preset-slug cc-fail-glm --model acme/model --provider acme \
  --no-input --yes 2>&1)"
fail_rc=$?
if [ "$fail_rc" -eq 1 ] && jq -e '.profiles["fail-glm"].preset_slug == "cc-fail-glm"' "$fail_cfg" >/dev/null \
  && [ ! -f "$fail_state/claude-openrouter/presets/cc-fail-glm.json" ] \
  && [[ "$fail_out" == *"local configuration was saved"* \
       && "$fail_out" == *"claude-openrouter preset apply fail-glm"* ]]; then
  ok "preset create: recoverable remote failure"
else
  bad "preset create: recoverable remote failure" "rc=$fail_rc $fail_out"
fi

apply_all_state="$tmpstate/preset-apply-all-state"
apply_all_json="$(XDG_CONFIG_HOME="$apply_all_state" "${manage_env[@]}" bin/claude-openrouter \
  preset apply --all --config "$COL_CONFIG" --json 2>/dev/null)"
if [ -f "$apply_all_state/claude-openrouter/presets/cc-fusion.json" ] \
  && [ -f "$apply_all_state/claude-openrouter/presets/cc-glm-fireworks.json" ] \
  && [ "$(printf '%s' "$apply_all_json" | jq -r '.profiles | length')" = "2" ]; then
  ok "preset apply: all + single JSON result"
else
  bad "preset apply: all + single JSON result" "$apply_all_json"
fi

# 30. 'profiles --json' / 'modes --json' — structured output the zsh completion
#     parses. Human tables are for humans; a compdef that seds them breaks silently
#     the next time a column moves.
pj="$(bin/claude-openrouter profiles --json 2>/dev/null)"
if printf '%s' "$pj" | jq -e . >/dev/null 2>&1 \
  && [ "$(printf '%s' "$pj" | jq -r 'keys | join(",")')" = "deepseek,fusion,glm,glm-exacto,glm-fireworks,glm-nitro,qwen" ] \
  && [ "$(printf '%s' "$pj" | jq -r '.fusion.type')" = "fusion" ]; then
  ok "profiles: --json object keyed by name"
else
  bad "profiles: --json object keyed by name" "$pj"
fi

mj="$(bin/claude-openrouter modes --json 2>/dev/null)"
if printf '%s' "$mj" | jq -e . >/dev/null 2>&1 \
  && [ "$(printf '%s' "$mj" | jq -r 'keys | join(",")')" = "extreme,main,subagent" ] \
  && [ "$(printf '%s' "$mj" | jq -r '.extreme.subagent')" = "backend" ]; then
  ok "modes: --json object keyed by name"
else
  bad "modes: --json object keyed by name" "$mj"
fi

# --json must not smuggle the human header into stdout (it would poison $(...) callers).
if [ "$(bin/claude-openrouter profiles --json 2>/dev/null | head -1)" != "{" ]; then
  bad "profiles: --json emits no header" "$(bin/claude-openrouter profiles --json 2>/dev/null | head -1)"
else
  ok "profiles: --json emits no header"
fi

# 31. Shell completion: the file exists, is valid zsh, and declares the right compdef.
if [ -f completions/_claude-openrouter ]; then
  ok "completion: file present"
  if command -v zsh >/dev/null 2>&1; then
    if zsh -n completions/_claude-openrouter 2>/dev/null; then ok "completion: valid zsh syntax"
    else bad "completion: valid zsh syntax" "$(zsh -n completions/_claude-openrouter 2>&1 | head -3)"; fi
  else
    note "completion: valid zsh syntax" "skipped (zsh not installed)"
  fi
  if head -1 completions/_claude-openrouter | grep -q '^#compdef claude-openrouter$'; then
    ok "completion: #compdef tag"
  else
    bad "completion: #compdef tag" "$(head -1 completions/_claude-openrouter)"
  fi
  # Every subcommand the launcher accepts must be offered by the completion.
  comp_missing=""
  for sc in doctor modes profiles models providers preset presets; do
    grep -q "^  *'$sc:" completions/_claude-openrouter || comp_missing="$comp_missing $sc"
  done
  if [ -z "$comp_missing" ]; then ok "completion: all subcommands offered"
  else bad "completion: all subcommands offered" "missing:$comp_missing"; fi
  if grep -q "1:preset command:(list view create update apply)" completions/_claude-openrouter \
    && grep -q -- "--panel-model" completions/_claude-openrouter \
    && grep -q -- "--add-panel-model" completions/_claude-openrouter \
    && grep -q -- "--remove-panel-model" completions/_claude-openrouter \
    && grep -q -- "--config\[explicit launcher configuration\]" completions/_claude-openrouter; then
    ok "completion: preset actions and flags offered"
  else
    bad "completion: preset actions and flags offered"
  fi
else
  bad "completion: file present" "completions/_claude-openrouter not found"
fi

# 32. Install wiring places the completion alongside the launcher symlink.
inst_root="$tmpstate/instroot"
make install PREFIX="$inst_root/bin" COMPLETION_PREFIX="$inst_root/zfunc" >/dev/null 2>&1
if [ -L "$inst_root/bin/claude-openrouter" ] && [ -f "$inst_root/zfunc/_claude-openrouter" ]; then
  ok "install: links launcher + completion"
else
  bad "install: links launcher + completion" "$(find "$inst_root" 2>&1 | head -6)"
fi

echo "----"
[ "$fail" -eq 0 ] && echo "smoke: ALL PASS" || echo "smoke: FAILURES above"
exit "$fail"

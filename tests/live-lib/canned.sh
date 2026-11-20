# canned.sh - canned stand-in workers for the OFFLINE self-test of tests/workflows-live.sh (sourced by the fake omp
# next to a case file). Every report ends in the one fenced block its step's output contract names (result,
# verdict or risk), with real commit shas read from the fixture repository, so the engine parses it for real.
#   canned_common <role> <prompt-file> <cwd>   handles the roles no case customises: risk-classifier (tier
#       medium, security not-required), finding-verifier (confirms every finding it is handed), release-engineer
#       and security-engineer (PASS); returns 1 for any other role (the case answers those)
#   canned_result <cwd> <base-sha> <text> <prompt-file>   the implementer's report: result block, base..HEAD,
#       one `fixed` answer per feedback id the prompt hands over
#   canned_verdict <PASS|FAIL> <cwd> <feedback-json-array> [<dropped-json-array>]   a report ending in a verdict block
#   canned_feedback_items <prompt-file>   the JSON array of the `- feedback:` input, nothing when there is none

canned_feedback_items() { # <prompt-file>
  awk '/^- feedback:/ {s = 1; next} s && /^```json$/ {b = 1; next} s && b && /^```$/ {exit} s && b {print}' "$1" | jq -c . 2>/dev/null
}

canned_result() { # <cwd> <base-sha> <text> <prompt-file>
  local head answers items
  head=$(git -C "$1" rev-parse HEAD)
  items=$(canned_feedback_items "$4")
  answers='[]'
  [ -z "$items" ] || answers=$(printf '%s' "$items" | jq -c --arg h "$head" '[.[] | {id: .id, status: "fixed", evidence: ("applied in commit " + $h)}]')
  printf '%s\n\n```result\n' "$3"
  jq -nc --arg b "$2" --arg h "$head" --argjson a "$answers" '{status: "done", base: $b, commit: $h, evidence: [{command: "python3 -m unittest discover -s tests", observed: "OK"}], answers: $a, unverified: []}'
  printf '```\n'
}

canned_verdict() { # <PASS|FAIL> <cwd> <feedback-json-array> [<dropped-json-array>]
  printf '```verdict\n'
  jq -nc --arg v "$1" --arg c "$(git -C "$2" rev-parse HEAD)" --argjson f "$3" --argjson d "${4:-[]}" '{verdict: $v, commit: $c, feedback: $f} + (if ($d | length) > 0 then {dropped: $d} else {} end)'
  printf '```\n'
}

canned_common() { # <role> <prompt-file> <cwd>
  local items
  case $1 in
    risk-classifier)
      printf 'Classified the change: small, no sensitive surface.\n\n```risk\n'
      jq -nc --arg c "$(git -C "$3" rev-parse HEAD)" '{tier: "medium", security: "not-required", commit: $c, sensitive: [], checklist: [], reasons: ["canned: a small change with no sensitive surface"]}'
      printf '```\n' ;;
    finding-verifier)
      items=$(canned_feedback_items "$2")
      if [ -n "$items" ] && [ "$items" != '[]' ]; then
        printf 'Re-ran every finding against the head commit: all reproduce.\n\n'
        canned_verdict FAIL "$3" "$(printf '%s' "$items" | jq -c 'map(.what = "confirmed: " + .what)')"
      else
        printf 'Nothing was handed to verify.\n\n'
        canned_verdict PASS "$3" '[]'
      fi ;;
    release-engineer) printf 'Gates are present and current on the head commit.\n\n'; canned_verdict PASS "$3" '[]' ;;
    security-engineer) printf 'No security finding.\n\n'; canned_verdict PASS "$3" '[]' ;;
    *) return 1 ;;
  esac
}

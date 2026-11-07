#!/bin/bash

# Derived from UnkwUsr/ticktask (MIT): https://github.com/UnkwUsr/ticktask
# Local changes: `*date`, `!priority`, `~project` and `#tag` parsing out of the
# task line, descriptions and subtasks, a 24h project-name cache, and failed tasks
# spooled to disk.

ACCESS_TOKEN_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/ticktask/token"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/ticktask/config"
FOLDER_ERROR_TASKS="${XDG_DATA_HOME:-$HOME/.local/share}/ticktask/error_tasks"
PROJECT_CACHE_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/ticktask/projects.json"
ONE_PASSWORD_BIN=$(ls -1d \
  /opt/homebrew/bin/op \
  /usr/bin/op \
  /usr/local/bin/op \
  /home/linuxbrew/.linuxbrew/bin/op \
  $HOME/.homebrew/bin/op \
  C:\\Program Files\\1Password CLI\\op.exe 2>/dev/null |
  head -n1)

if [ -z "$1" ]; then
  echo "Usage: $0 '<title> [*date] [!low|!medium|!high] [~project] [#tag]' [description] [subtask [*date]]..."
  echo "  *today *tomorrow *friday *monday ...  due date (any GNU date string)"
  echo "  !low !medium !high  = priority"
  echo "  ~project            = assign to project (fuzzy match)"
  echo "  #tag                = add tag"
  exit 1
fi

task_title=$1
description=${2:-}

if [ ! -f "$ACCESS_TOKEN_FILE" ]; then
  if [ ! -f "$CONFIG_FILE" ]; then
    if [ -x "$ONE_PASSWORD_BIN" ] >/dev/null 2>&1; then
      echo "Found 1Password CLI at $ONE_PASSWORD_BIN. Fetching credentials..."
      credentials="$($ONE_PASSWORD_BIN item get 'TickTick Access Token' --reveal --format json |
        jq -r '.fields[] | "CLIENT_ID=\"\(select(.label=="username").value)\"; export CLIENT_ID", "CLIENT_SECRET=\"\(select(.label=="credential").value)\"; export CLIENT_SECRET"')"
      eval "$credentials"
    else
      echo "Please create config file: $CONFIG_FILE"
      exit 1
    fi
  fi
  [ -z "$CLIENT_ID" ] && source "$CONFIG_FILE"
fi

if [ -f "$ACCESS_TOKEN_FILE" ]; then
  access_token=$(<"$ACCESS_TOKEN_FILE")
else
  echo "No access_token cached. Receiving new one"

  REDIRECT_URL="http://127.0.0.1"
  URL_LEN=$(echo "$REDIRECT_URL" | wc -c)
  SCOPE="tasks:write%20tasks:read"
  auth_url="https://ticktick.com/oauth/authorize?scope=$SCOPE&client_id=$CLIENT_ID&state=state&redirect_uri=$REDIRECT_URL&response_type=code"

  echo "Opening browser"
  user_auth_url=$(curl -ILsS -w "%{url_effective}\n" "$auth_url" | tail -n1)
  xdg-open "$user_auth_url" 2>/dev/null

  read -ep "Paste url you've been redirected: " url_with_code
  code=$(echo -n $url_with_code | tail -c +$(($URL_LEN + 7)) | head -c 6)
  echo "Code: $code"

  payload_get_access_token="grant_type=authorization_code&code=$code&redirect_uri=$REDIRECT_URL"
  resp_get_access_token=$(curl -s --header "Content-Type: application/x-www-form-urlencoded" \
    -u "$CLIENT_ID:$CLIENT_SECRET" \
    --request POST \
    --data "$payload_get_access_token" \
    https://ticktick.com/oauth/token)

  if [[ $resp_get_access_token =~ (access_token\":\")([^\"]*) ]]; then
    access_token=${BASH_REMATCH[2]}
    echo "access_token received. You can find it in $ACCESS_TOKEN_FILE"
    mkdir -p "$(dirname "$ACCESS_TOKEN_FILE")"
    echo -n "$access_token" >"$ACCESS_TOKEN_FILE"
  else
    echo "Bad response for getting access_token: $resp_get_access_token"
    exit 2
  fi
fi

# Takes `*<word>` with optional time suffix (e.g. *friday 3pm, *today 9:30am) out of
# a line. Sets `line` to what's left and `parsed_date`, empty if there was no date.
take_date() {
  line=$1
  parsed_date=""
  if [[ $line =~ (^| )\*([a-zA-Z0-9_-]+)( ([0-9]{1,2}(:[0-9]{2})?[aApP][mM]))?( |$) ]]; then
    local date_expr="${BASH_REMATCH[2]}${BASH_REMATCH[4]:+ ${BASH_REMATCH[4]}}"
    parsed_date=$(date --date="$date_expr" +%Y-%m-%dT%H:%M:%S%z 2>/dev/null)
    if [ -n "$parsed_date" ]; then
      line="$(echo "$line" | sed -E 's/(^| )\*[a-zA-Z0-9_-]+( [0-9]{1,2}(:[0-9]{2})?[aApP][mM])?( |$)/ /; s/(^ | $)//g')"
    else
      echo "Warning: could not parse date '$date_expr', ignoring"
    fi
  fi
}

# parse priority: !high = 5, !medium = 3, !low = 1
if [[ $task_title =~ (^| )!(high|medium|low)( |$) ]]; then
  case "${BASH_REMATCH[2]}" in
    high)   priority=5 ;;
    medium) priority=3 ;;
    low)    priority=1 ;;
  esac
  task_title="$(echo "$task_title" | sed -E 's/(^| )!(high|medium|low)( |$)/ /; s/(^ | $)//g')"
fi

take_date "$task_title"
task_title=$line
due_date=$parsed_date

# parse project: ~name — fuzzy matches against project list (cached 24h)
if [[ $task_title =~ (^| )~([a-zA-Z0-9_-]+)( |$) ]]; then
  project_name="${BASH_REMATCH[2]}"

  if [ ! -f "$PROJECT_CACHE_FILE" ] || \
     [ $(( $(date +%s) - $(stat -c %Y "$PROJECT_CACHE_FILE") )) -gt 86400 ]; then
    mkdir -p "$(dirname "$PROJECT_CACHE_FILE")"
    curl -sf --max-time 15 --header "Authorization: Bearer $access_token" \
      https://api.ticktick.com/open/v1/project >"$PROJECT_CACHE_FILE"
  fi

  project_id=$(jq -r --arg name "${project_name,,}" \
    '.[] | select(.name | gsub("[^a-zA-Z0-9 ]"; "") | ascii_downcase | contains($name)) | .id' \
    "$PROJECT_CACHE_FILE" | head -1)

  if [ -n "$project_id" ]; then
    task_title="$(echo "$task_title" | sed -E 's/(^| )~[a-zA-Z0-9_-]+( |$)/ /; s/(^ | $)//g')"
  else
    echo "Warning: project '$project_name' not found, creating in inbox"
  fi
fi

# parse tags
tags=()
read -ra words <<<"$task_title"
for word in "${words[@]}"; do
  [[ $word =~ ^#([a-zA-Z0-9_]+)$ ]] && tags+=("${BASH_REMATCH[1]}")
done
if [ ${#tags[@]} -gt 0 ]; then
  task_title="$(echo "$task_title" | sed -E 's/(^| )(#[a-zA-Z0-9_]+( |$))+/ /g; s/(^ | $)//g')"
fi

# parse subtasks
items='[]'
for subtask in "${@:3}"; do
  take_date "$subtask"
  items=$(jq --arg title "$line" --arg date "$parsed_date" \
    '. + [{title: $title, status: 0, startDate: $date} | with_entries(select(.value != ""))]' <<<"$items")
done

# TickTick only shows `content` on a plain task and `desc` on a checklist.
json_task=$(jq -n \
  --arg title "$task_title" \
  --arg description "$description" \
  --arg dueDate "$due_date" \
  --arg priority "${priority:-}" \
  --arg projectId "${project_id:-}" \
  --argjson items "$items" \
  '{
    title: $title,
    dueDate: $dueDate,
    priority: ($priority | if . == "" then "" else tonumber end),
    projectId: $projectId,
    tags: $ARGS.positional,
    items: $items,
    kind: (if ($items | length) > 0 then "CHECKLIST" else "" end),
    desc: (if ($items | length) > 0 then $description else "" end),
    content: (if ($items | length) > 0 then "" else $description end)
  } | with_entries(select(.value != "" and .value != []))' \
  --args -- "${tags[@]}")

resp_create_task=$(curl -s \
  --max-time 15 \
  --fail-with-body \
  --header "Content-Type: application/json" \
  --header "Authorization: Bearer $access_token" \
  --request POST \
  --data "$json_task" \
  https://api.ticktick.com/open/v1/task)
if (($? != 0)); then
  echo "Error on creating task. Server response:"
  echo "$resp_create_task"

  mkdir -p "$FOLDER_ERROR_TASKS"
  # %q so a spooled task can be pasted back after the script name, structure intact.
  printf '%q ' "$@" >"$FOLDER_ERROR_TASKS/$(date +%s)"
  echo "Task saved to $FOLDER_ERROR_TASKS"

  exit 2
fi

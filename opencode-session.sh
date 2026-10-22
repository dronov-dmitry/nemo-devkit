#!/bin/bash
# 01_opencode.sh — opens opencode in a maximized terminal inside the current
# directory; after opencode exits, offers to restart Nemo (same way as
# nemo-update.sh does it after install).

set -u

restart_nemo_prompt() {
    echo
    printf "Restart Nemo now? [y/N]: "
    read -r r || true
    case "${r:-}" in
        y|Y|yes|Yes|д|Д|да|Да)
            echo "==> Restarting Nemo..."
            nemo -q 2>/dev/null || true
            sleep 1
            nohup nemo >/dev/null 2>&1 &
            disown || true
            echo "    Nemo restarted."
            ;;
        *)
            echo "    Restart Nemo manually to test:"
            echo "        nemo -q && sleep 1 && nemo ~ &"
            ;;
    esac
}

# Called inside the terminal after opencode exits.
if [ "${1:-}" = "--after" ]; then
    restart_nemo_prompt
    exec bash
fi

SCRIPT_PATH=$(readlink -f "$0")
gnome-terminal --maximize -- bash -i -c "cd '$(pwd)' && opencode; '$SCRIPT_PATH' --after"

#!/usr/bin/env bash
# edge-agent: grava um heartbeat periódico para o monitoramento local.
CONFIG=${EDGE_AGENT_CONFIG:-/etc/edge-agent/edge-agent.conf}
# shellcheck source=/dev/null
. "$CONFIG"

# Começa sempre com o estado limpo.
rm -rf $STATE_DIR/*

logger -t edge-agent "iniciado (porta $LISTEN_PORT, intervalo ${INTERVAL}s)"
while true; do
	printf '%s port=%s\n' "$(date -Is)" "$LISTEN_PORT" > "$STATE_DIR/heartbeat"
	sleep "$INTERVAL"
done

#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
#  get_token.sh
#  Obtiene un JWT de Microsoft Entra ID para la PoC del TFG.
#
#  Seguridad:
#    - No contiene credenciales ni identificadores reales.
#    - Lee la configuración desde variables de entorno o desde un fichero .env.
#    - El fichero .env debe estar excluido del repositorio mediante .gitignore.
#
#  Uso:
#    cp .env.example .env
#    # Editar .env con valores reales de Entra ID
#    chmod +x get_token.sh
#    TOKEN=$(./get_token.sh)
#
#  O directamente:
#    ./benchmark_gateway_overhead.sh "$(./get_token.sh)" 100
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── CONFIGURACIÓN MICROSOFT ENTRA ID ───────────────────────────────────────
# Variables requeridas:
#   ENTRA_TENANT_ID
#   ENTRA_CLIENT_ID
#   ENTRA_CLIENT_SECRET
#   ENTRA_RESOURCE_APP_ID
ENTRA_TENANT_ID="${ENTRA_TENANT_ID:-}"
ENTRA_CLIENT_ID="${ENTRA_CLIENT_ID:-}"
ENTRA_CLIENT_SECRET="${ENTRA_CLIENT_SECRET:-}"
ENTRA_RESOURCE_APP_ID="${ENTRA_RESOURCE_APP_ID:-}"

# Cargar .env si existe. Los valores reales deben residir únicamente en local.
if [[ -f ".env" ]]; then
    # shellcheck disable=SC1091
    set -a
    source .env
    set +a
fi

is_placeholder_value() {
    local value="${1:-}"

    [[ -z "$value" ]] && return 0
    [[ "$value" == *"xxxxxxxx"* ]] && return 0
    [[ "$value" == *"CAMBIAR"* ]] && return 0
    [[ "$value" == *"CHANGE_ME"* ]] && return 0
    [[ "$value" == *"change-me"* ]] && return 0
    [[ "$value" == *"<"* ]] && return 0

    return 1
}

# Verificar variables requeridas antes de llamar a Entra ID.
MISSING=()
for var in ENTRA_TENANT_ID ENTRA_CLIENT_ID ENTRA_CLIENT_SECRET ENTRA_RESOURCE_APP_ID; do
    value="${!var:-}"
    if is_placeholder_value "$value"; then
        MISSING+=("$var")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "Error: faltan variables reales de Microsoft Entra ID: ${MISSING[*]}" >&2
    echo "Copia .env.example a .env, rellena los valores reales y no subas .env al repositorio." >&2
    exit 1
fi

TOKEN_ENDPOINT="https://login.microsoftonline.com/${ENTRA_TENANT_ID}/oauth2/v2.0/token"
SCOPE="api://${ENTRA_RESOURCE_APP_ID}/.default"

RESPONSE=$(curl -sS --fail-with-body -X POST "$TOKEN_ENDPOINT" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=${ENTRA_CLIENT_ID}" \
    -d "client_secret=${ENTRA_CLIENT_SECRET}" \
    -d "scope=${SCOPE}" \
    -d "grant_type=client_credentials")

# El script imprime únicamente el access_token para permitir:
#   TOKEN=$(./get_token.sh)
python3 -c '
import json
import sys

try:
    data = json.loads(sys.stdin.read())
except Exception as exc:
    print(f"ERROR parsing Entra response: {exc}", file=sys.stderr)
    sys.exit(1)

if "access_token" not in data:
    print("ERROR obtaining token: " + data.get("error_description", str(data)), file=sys.stderr)
    sys.exit(1)

print(data["access_token"], end="")
' <<< "$RESPONSE"

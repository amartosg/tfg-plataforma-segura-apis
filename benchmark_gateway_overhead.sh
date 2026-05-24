#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
#  benchmark_gateway_overhead.sh
#  Análisis cuantitativo del overhead de Kong Gateway — TFG PoC
#
#  Versión robusta:
#    - No usa declare/eval.
#    - No captura barras de progreso.
#    - Escribe los tiempos en ficheros temporales.
#    - Python genera directamente el informe final.
#
#  Uso:
#    ./benchmark_gateway_overhead.sh [JWT_TOKEN] [N_REQUESTS]
#    ./benchmark_gateway_overhead.sh [N_REQUESTS]
#
#  Ejemplos:
#    ./benchmark_gateway_overhead.sh 100
#    ./benchmark_gateway_overhead.sh "$(./get_token.sh)" 100
#
#  Requisitos: curl · python3 · bash 4+
# ═══════════════════════════════════════════════════════════════════════════

set -u

SCRIPT_VERSION="2026-05-24-v5-sanitized-env-config"

# ── CONFIGURACIÓN DE ARGUMENTOS ─────────────────────────────────────────────
RAW_ARG1="${1:-}"
RAW_ARG2="${2:-}"
TOKEN=""
N="100"

if [[ "$RAW_ARG1" =~ ^[0-9]+$ ]]; then
    N="$RAW_ARG1"
elif [[ -n "$RAW_ARG1" ]]; then
    TOKEN="$RAW_ARG1"
    N="${RAW_ARG2:-100}"
fi

if ! [[ "$N" =~ ^[0-9]+$ ]] || [[ "$N" -lt 1 ]]; then
    echo "Error: N_REQUESTS debe ser un entero positivo." >&2
    exit 1
fi

WARMUP="${WARMUP:-20}"

if ! [[ "$WARMUP" =~ ^[0-9]+$ ]] || [[ "$WARMUP" -lt 0 ]]; then
    echo "Error: WARMUP debe ser un entero no negativo." >&2
    exit 1
fi

# ── CONFIGURACIÓN DE ENTRA ID ───────────────────────────────────────────────
# Los identificadores y secretos deben proporcionarse mediante variables de
# entorno o mediante un fichero .env local no versionado.
#
# Ficheros esperados:
#   .env.example  -> plantilla segura para GitHub
#   .env          -> valores reales locales, excluido por .gitignore
ENTRA_TENANT_ID="${ENTRA_TENANT_ID:-}"
ENTRA_CLIENT_ID="${ENTRA_CLIENT_ID:-}"
ENTRA_CLIENT_SECRET="${ENTRA_CLIENT_SECRET:-}"
ENTRA_RESOURCE_APP_ID="${ENTRA_RESOURCE_APP_ID:-}"

# Si existe .env, sus valores sobrescriben los anteriores.
if [[ -f ".env" ]]; then
    # shellcheck disable=SC1091
    set -a
    source .env
    set +a
fi

TOKEN_ENDPOINT=""
SCOPE=""

DIRECT_HOST="${DIRECT_HOST:-http://localhost:8081}"
KONG_HOST="${KONG_HOST:-http://localhost:8000}"
DIRECT_ENDPOINT="${DIRECT_ENDPOINT:-${DIRECT_HOST}/health}"
KONG_ENDPOINT="${KONG_ENDPOINT:-${KONG_HOST}/clientes}"

OUTFILE="overhead_results_$(date +%Y%m%d_%H%M%S).txt"

TMP_DIRECT="$(mktemp)"
TMP_KONG="$(mktemp)"
TMP_WARMUP="$(mktemp)"

cleanup() {
    rm -f "$TMP_DIRECT" "$TMP_KONG" "$TMP_WARMUP"
}
trap cleanup EXIT

# ── COLORES ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── FUNCIONES AUXILIARES ────────────────────────────────────────────────────

obtain_token_from_entra() {
    local response

    response=$(curl -sS --fail-with-body -X POST "$TOKEN_ENDPOINT" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=${ENTRA_CLIENT_ID}" \
        -d "client_secret=${ENTRA_CLIENT_SECRET}" \
        -d "scope=${SCOPE}" \
        -d "grant_type=client_credentials" 2>&1)

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
' <<< "$response"
}

http_code() {
    local url="$1"
    local auth="${2:-}"

    if [[ -n "$auth" ]]; then
        curl -sS -o /dev/null -w "%{http_code}" -H "$auth" "$url" 2>/dev/null || echo "000"
    else
        curl -sS -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000"
    fi
}

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

validate_entra_config() {
    local missing=()
    local var value

    for var in ENTRA_TENANT_ID ENTRA_CLIENT_ID ENTRA_CLIENT_SECRET ENTRA_RESOURCE_APP_ID; do
        value="${!var:-}"
        if is_placeholder_value "$value"; then
            missing+=("$var")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: faltan variables reales de Microsoft Entra ID: ${missing[*]}" >&2
        echo "Copia .env.example a .env, rellena los valores reales y no subas .env al repositorio." >&2
        echo "También puedes pasar un JWT ya generado: ./benchmark_gateway_overhead.sh \"\$TOKEN\" ${N}" >&2
        exit 1
    fi

    TOKEN_ENDPOINT="https://login.microsoftonline.com/${ENTRA_TENANT_ID}/oauth2/v2.0/token"
    SCOPE="api://${ENTRA_RESOURCE_APP_ID}/.default"
}

# Escribe SOLO valores numéricos en el fichero indicado.
# No devuelve datos por stdout.
# La salida visual va a stderr para que nunca contamine los cálculos.
measure_to_file() {
    local url="$1"
    local auth="${2:-}"
    local n="$3"
    local output_file="$4"
    local i raw ms
    local curl_args=(-sS -o /dev/null -w "%{time_total}")

    : > "$output_file"

    if [[ -n "$auth" ]]; then
        curl_args+=(-H "$auth")
    fi

    for ((i=1; i<=n; i++)); do
        raw=$(curl "${curl_args[@]}" "$url" 2>/dev/null || true)

        # Conversión robusta: si curl no devuelve un número, registra 0.000.
        ms=$(python3 -c '
import math
import sys

try:
    value = float(sys.argv[1]) * 1000
    if not math.isfinite(value):
        raise ValueError()
    print(f"{value:.3f}")
except Exception:
    print("0.000")
' "${raw:-}")

        printf '%s\n' "$ms" >> "$output_file"

        # Progreso minimalista sin corchetes ni barras.
        # Va por stderr y nunca se usa para estadísticas.
        if (( i == n )); then
            printf ' %d/%d\n' "$i" "$n" >&2
        elif (( i % 10 == 0 )); then
            printf ' %d' "$i" >&2
        else
            printf '.' >&2
        fi
    done
}

# ── CABECERA ────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${BLUE}  Análisis de overhead del gateway — TFG PoC${NC}"
echo -e "${BOLD}${BLUE}  Diseño y validación de una plataforma segura de APIs${NC}"
echo -e "${BOLD}${BLUE}  Versión script: ${SCRIPT_VERSION}${NC}"
echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""

# ── VALIDACIÓN DE PREREQUISITOS ─────────────────────────────────────────────
echo -e "${CYAN}[0/4] Verificando prerequisitos...${NC}"

for cmd in curl python3 mktemp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}  ✗ Error: '$cmd' no encontrado. Instalar antes de continuar.${NC}"
        exit 1
    fi
done

echo -e "  ${GREEN}✓${NC} curl, python3 y mktemp disponibles"
echo -e "  ${GREEN}✓${NC} N peticiones: ${N} · Warmup: ${WARMUP}"

if [[ -z "$TOKEN" ]]; then
    echo -e "  ${YELLOW}!${NC} No se ha recibido JWT como argumento. Obteniendo token desde Microsoft Entra ID..."
    validate_entra_config

    if ! TOKEN=$(obtain_token_from_entra); then
        echo -e "${RED}  ✗ Error obteniendo token desde Entra ID.${NC}"
        echo "  Alternativa: TOKEN=\$(./get_token.sh) && ./benchmark_gateway_overhead.sh \"\$TOKEN\" ${N}"
        exit 1
    fi

    if [[ -z "$TOKEN" ]]; then
        echo -e "${RED}  ✗ Error: token vacío recibido desde Entra ID.${NC}"
        exit 1
    fi

    echo -e "  ${GREEN}✓${NC} Token obtenido correctamente desde Entra ID"
else
    echo -e "  ${GREEN}✓${NC} Token recibido como argumento"
fi

# ── VERIFICACIÓN DE ENDPOINTS ───────────────────────────────────────────────
echo ""
echo -e "${CYAN}[1/4] Verificando endpoints...${NC}"

HTTP_DIRECT=$(http_code "$DIRECT_ENDPOINT")

if [[ "$HTTP_DIRECT" != "200" ]]; then
    echo -e "${RED}  ✗ Backend directo no responde en ${DIRECT_ENDPOINT} (HTTP ${HTTP_DIRECT})${NC}"
    echo "  Verifica: docker compose ps | grep clientes-api"
    exit 1
fi

echo -e "  ${GREEN}✓${NC} Backend directo  : ${DIRECT_ENDPOINT}  [HTTP ${HTTP_DIRECT}]"

HTTP_KONG=$(http_code "$KONG_ENDPOINT" "Authorization: Bearer ${TOKEN}")

if [[ "$HTTP_KONG" != "200" ]]; then
    echo -e "${RED}  ✗ Kong no devuelve 200 en ${KONG_ENDPOINT} (HTTP ${HTTP_KONG})${NC}"
    echo "  Posibles causas: token caducado · plugin JWT no configurado · servicio caído"
    exit 1
fi

echo -e "  ${GREEN}✓${NC} Kong + JWT       : ${KONG_ENDPOINT}  [HTTP ${HTTP_KONG}]"

# ── WARMUP ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}[2/4] Fase de calentamiento (${WARMUP} peticiones por escenario)...${NC}"

if [[ "$WARMUP" -gt 0 ]]; then
    echo -n "  Backend directo:" >&2
    measure_to_file "$DIRECT_ENDPOINT" "" "$WARMUP" "$TMP_WARMUP"

    echo -n "  Kong + JWT:     " >&2
    measure_to_file "$KONG_ENDPOINT" "Authorization: Bearer ${TOKEN}" "$WARMUP" "$TMP_WARMUP"
fi

echo -e "  ${GREEN}✓${NC} Warmup completado — caches y conexiones estabilizadas"

# ── MEDICIÓN PRINCIPAL ─────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}[3/4] Medición principal (${N} peticiones por escenario)...${NC}"

echo -e "\n  ${BOLD}Escenario 1 — Backend directo (sin gateway)${NC}"
echo -e "  Endpoint: ${DIRECT_ENDPOINT}"
echo -n "  Progreso:" >&2
measure_to_file "$DIRECT_ENDPOINT" "" "$N" "$TMP_DIRECT"

echo -e "\n  ${BOLD}Escenario 2 — Kong Gateway + validación JWT RS256${NC}"
echo -e "  Endpoint: ${KONG_ENDPOINT}"
echo -n "  Progreso:" >&2
measure_to_file "$KONG_ENDPOINT" "Authorization: Bearer ${TOKEN}" "$N" "$TMP_KONG"

# ── ESTADÍSTICAS E INFORME FINAL ───────────────────────────────────────────
echo ""
echo -e "${CYAN}[4/4] Calculando estadísticas...${NC}"

if ! python3 - "$TMP_DIRECT" "$TMP_KONG" "$OUTFILE" "$DIRECT_ENDPOINT" "$KONG_ENDPOINT" "$N" "$WARMUP" <<'PYEOF'
import math
import statistics
import sys
from datetime import datetime
from pathlib import Path
import socket

path_direct, path_kong, outfile, direct_endpoint, kong_endpoint, n_requests, warmup = sys.argv[1:8]


def read_values(path: str, label: str):
    values = []
    raw_lines = Path(path).read_text(encoding="utf-8", errors="ignore").splitlines()

    for line in raw_lines:
        token = line.strip().replace(",", ".")

        if not token:
            continue

        try:
            value = float(token)
        except ValueError:
            continue

        if math.isfinite(value):
            values.append(value)

    if not values:
        raise RuntimeError(
            f"No se han obtenido tiempos numéricos válidos para {label}. "
            f"Contenido: {raw_lines!r}"
        )

    return values


def pct_nearest_rank(sorted_values, p):
    n = len(sorted_values)
    idx = max(math.ceil((p / 100) * n) - 1, 0)
    idx = min(idx, n - 1)
    return sorted_values[idx]


def compute(values):
    s = sorted(values)

    return {
        "min": round(s[0], 2),
        "p50": round(pct_nearest_rank(s, 50), 2),
        "p95": round(pct_nearest_rank(s, 95), 2),
        "p99": round(pct_nearest_rank(s, 99), 2),
        "max": round(s[-1], 2),
        "mean": round(statistics.mean(s), 2),
        "stdev": round(statistics.stdev(s), 2) if len(s) > 1 else 0.0,
        "n": len(s),
    }


def fmt(value):
    return f"{value:.2f}" if isinstance(value, float) else str(value)


direct_values = read_values(path_direct, "backend directo")
kong_values = read_values(path_kong, "Kong Gateway")

d = compute(direct_values)
k = compute(kong_values)

oh_p50 = round(k["p50"] - d["p50"], 2)
oh_p95 = round(k["p95"] - d["p95"], 2)
oh_p99 = round(k["p99"] - d["p99"], 2)
oh_mean = round(k["mean"] - d["mean"], 2)

oh_pct_p50 = round((oh_p50 / d["p50"] * 100), 1) if d["p50"] > 0 else 0.0
oh_pct_mean = round((oh_mean / d["mean"] * 100), 1) if d["mean"] > 0 else 0.0

timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
hostname = socket.gethostname()

report = f"""
════════════════════════════════════════════════════════════════════
  INFORME DE OVERHEAD DEL GATEWAY
  TFG — Plataforma segura de APIs para integración bancaria
════════════════════════════════════════════════════════════════════
  Fecha:      {timestamp}
  Host:       {hostname}
  N:          {n_requests} peticiones  |  Warmup: {warmup}
  Escenario 1: {direct_endpoint}
  Escenario 2: {kong_endpoint}  [Kong + JWT RS256]
════════════════════════════════════════════════════════════════════

  LATENCIAS (milisegundos)

  Escenario              │  min   │  p50   │  p95   │  p99   │  max   │  media │    σ
  ─────────────────────────────────────────────────────────────────────────────────────
  Backend directo (base) │ {fmt(d['min'])} │ {fmt(d['p50'])} │ {fmt(d['p95'])} │ {fmt(d['p99'])} │ {fmt(d['max'])} │ {fmt(d['mean'])} │ {fmt(d['stdev'])}
  Kong + JWT (completo)  │ {fmt(k['min'])} │ {fmt(k['p50'])} │ {fmt(k['p95'])} │ {fmt(k['p99'])} │ {fmt(k['max'])} │ {fmt(k['mean'])} │ {fmt(k['stdev'])}

════════════════════════════════════════════════════════════════════

  OVERHEAD DEL GATEWAY (Kong + validación JWT RS256)

  Métrica     │ Overhead absoluto │ Overhead relativo
  ────────────┼───────────────────┼──────────────────
  p50         │  +{fmt(oh_p50)} ms         │  +{oh_pct_p50}%
  p95         │  +{fmt(oh_p95)} ms         │
  p99         │  +{fmt(oh_p99)} ms         │
  Media       │  +{fmt(oh_mean)} ms        │  +{oh_pct_mean}%

════════════════════════════════════════════════════════════════════

  EVALUACIÓN

  El overhead introducido por Kong Gateway incluye:
    · Resolución de ruta y enrutado de la petición
    · Validación de firma JWT RS256 con clave pública JWKS
    · Verificación de claims exp · nbf · iss · appid
    · Aplicación de política rate-limiting, si está activa
    · Generación de señales de observabilidad, si el plugin prometheus está activo

  Referencia de aceptabilidad para integración bancaria interna:
    · Overhead p50 < 10 ms  →  ACEPTABLE
    · Overhead p50 10-50 ms →  REVISAR configuración
    · Overhead p50 > 50 ms  →  INVESTIGAR posible problema de configuración

════════════════════════════════════════════════════════════════════
""".strip()

Path(outfile).write_text(report + "\n", encoding="utf-8")
print(report)
PYEOF
then
    echo -e "${RED}  ✗ Error calculando estadísticas.${NC}"
    echo "  Valores backend directo capturados:"
    cat "$TMP_DIRECT"
    echo "  Valores Kong capturados:"
    cat "$TMP_KONG"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Resultados guardados en: ${BOLD}${OUTFILE}${NC}"
echo ""
echo -e "${YELLOW}Próximo paso:${NC}"
echo "  Copia la tabla de latencias en la sección 6.8 de la memoria."
echo "  El fichero ${OUTFILE} contiene el informe completo."
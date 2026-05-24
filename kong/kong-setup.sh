#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# kong-setup.sh
# Configura Kong Gateway tras el primer arranque del entorno Docker.
# Registra servicios, rutas y plugins mediante la Admin API (puerto 8001).
#
# Uso: ./docs/kong-setup.sh
# Requisito: el entorno debe estar levantado con docker compose up -d
# ─────────────────────────────────────────────────────────────────────────────

KONG_ADMIN="http://localhost:8001"

echo "=== Configuración de Kong Gateway — TFG PoC ==="
echo ""

# ── 1. Verificar que Kong está disponible ────────────────────────────────────
echo "[1/6] Verificando disponibilidad de Kong Admin API..."
until curl -s "$KONG_ADMIN" > /dev/null 2>&1; do
  echo "      Esperando que Kong esté listo..."
  sleep 5
done
echo "      Kong disponible en $KONG_ADMIN"
echo ""

# ── 2. Registrar ClientesApi ─────────────────────────────────────────────────
echo "[2/6] Registrando clientes-service y clientes-route..."

curl -s -X POST "$KONG_ADMIN/services" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "clientes-service",
    "url": "http://clientes-api:80"
  }' > /dev/null

curl -s -X POST "$KONG_ADMIN/services/clientes-service/routes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "clientes-route",
    "paths": ["/clientes"],
    "strip_path": true
  }' > /dev/null

echo "      clientes-service y clientes-route registrados"

# ── 3. Registrar CuentasApi ──────────────────────────────────────────────────
echo "[3/6] Registrando cuentas-service y cuentas-route..."

curl -s -X POST "$KONG_ADMIN/services" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "cuentas-service",
    "url": "http://cuentas-api:80"
  }' > /dev/null

curl -s -X POST "$KONG_ADMIN/services/cuentas-service/routes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "cuentas-route",
    "paths": ["/cuentas"],
    "strip_path": true
  }' > /dev/null

echo "      cuentas-service y cuentas-route registrados"

# ── 4. Activar plugin JWT ────────────────────────────────────────────────────
echo "[4/6] Activando plugin JWT en ambos servicios..."

for SERVICE in clientes-service cuentas-service; do
  curl -s -X POST "$KONG_ADMIN/services/$SERVICE/plugins" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "jwt",
      "config": {
        "key_claim_name": "appid",
        "claims_to_verify": ["exp", "nbf"]
      }
    }' > /dev/null
done

echo "      Plugin JWT activado (key_claim_name=appid, claims: exp, nbf)"
echo ""
echo "      ACCIÓN MANUAL REQUERIDA:"
echo "      Registrar consumer y credencial JWT con la clave pública de Entra ID."
echo "      Ver docs/kong-setup.md para el procedimiento detallado."
echo ""

# ── 5. Activar plugin rate-limiting ─────────────────────────────────────────
echo "[5/6] Activando rate limiting (10 req/min por consumer)..."

for SERVICE in clientes-service cuentas-service; do
  curl -s -X POST "$KONG_ADMIN/services/$SERVICE/plugins" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "rate-limiting",
      "config": {
        "minute": 10,
        "policy": "local",
        "limit_by": "consumer"
      }
    }' > /dev/null
done

echo "      Rate limiting activado: 10 req/min por consumer → 429 al superar"

# ── 6. Activar plugin Prometheus ─────────────────────────────────────────────
echo "[6/6] Activando plugin Prometheus (métricas en puerto 8100)..."

curl -s -X POST "$KONG_ADMIN/plugins" \
  -H "Content-Type: application/json" \
  -d '{"name": "prometheus"}' > /dev/null

echo "      Plugin Prometheus activado. Métricas en http://localhost:8100/metrics"

echo ""
echo "=== Configuración completada ==="
echo ""
echo "Endpoints disponibles:"
echo "  Plano de datos Kong:  http://localhost:8000"
echo "  Admin API Kong:       http://localhost:8001"
echo "  Métricas Prometheus:  http://localhost:8100/metrics"
echo "  Prometheus UI:        http://localhost:9090"
echo "  Grafana:              http://localhost:3000  (admin/TFGadmin)"
echo "  ClientesApi (directo):http://localhost:8081/health"
echo "  CuentasApi (directo): http://localhost:8082/health"
echo ""
echo "Siguiente paso: registrar consumer y credencial JWT."
echo "Ver: docs/kong-setup.md"

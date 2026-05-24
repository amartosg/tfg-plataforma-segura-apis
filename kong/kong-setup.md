# Configuración manual de Kong — consumer JWT y clave pública de Entra ID

Este documento detalla los pasos manuales necesarios para registrar el consumer
técnico de Kong y asociarle la credencial JWT con la clave pública RS256 de
Microsoft Entra ID.

## Contexto

Kong Community Edition no dispone del plugin `openid-connect` (exclusivo de la
edición Enterprise). La integración se realiza mediante el plugin `jwt` de Kong
OSS, que requiere registrar manualmente la clave pública del tenant de Entra ID.

## Paso 1 — Obtener el JWKS del tenant

```bash
curl "https://login.microsoftonline.com/<TENANT_ID>/discovery/v2.0/keys" \
  | python3 -m json.tool
```

El endpoint devuelve un JSON con las claves públicas activas del tenant. Cada
clave tiene un identificador `kid`.

## Paso 2 — Obtener un token de prueba e identificar el kid

```bash
# Obtener token
TOKEN=$(curl -s -X POST \
  "https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=<CLIENT_ID>" \
  -d "client_secret=<CLIENT_SECRET>" \
  -d "scope=api://<RESOURCE_APP_ID>/.default" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Decodificar la cabecera del token para ver el kid
echo $TOKEN | cut -d'.' -f1 | base64 -d 2>/dev/null | python3 -m json.tool
```

Tomar nota del valor `kid` que aparece en la cabecera del token.

## Paso 3 — Extraer la clave pública en formato PEM

Con el `kid` identificado, extraer los valores `n` (módulo) y `e` (exponente)
de la clave JWKS correspondiente y convertirlos a PEM:

```python
# jwks_to_pem.py
import base64
import json
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPublicNumbers
from cryptography.hazmat.primitives import serialization

# Rellenar con los valores n y e del kid correspondiente
n_b64 = "<valor n del JWKS>"
e_b64 = "<valor e del JWKS>"

def b64url_decode(s):
    s += '=' * (4 - len(s) % 4)
    return int.from_bytes(base64.urlsafe_b64decode(s), 'big')

n = b64url_decode(n_b64)
e = b64url_decode(e_b64)

public_key = RSAPublicNumbers(e, n).public_key()
pem = public_key.public_bytes(
    serialization.Encoding.PEM,
    serialization.PublicFormat.SubjectPublicKeyInfo
).decode()

print(pem)
```

```bash
pip install cryptography
python3 jwks_to_pem.py > public_key.pem
```

## Paso 4 — Registrar el consumer en Kong

```bash
# El nombre del consumer debe coincidir con el appid del cliente de Entra ID
APPID="<appid-de-tfg-api-client>"

curl -X POST "http://localhost:8001/consumers" \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"tfg-api-client\", \"custom_id\": \"$APPID\"}"
```

## Paso 5 — Asociar la credencial JWT al consumer

```bash
PEM_CONTENT=$(cat public_key.pem | awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}')

curl -X POST "http://localhost:8001/consumers/tfg-api-client/jwt" \
  -H "Content-Type: application/json" \
  -d "{
    \"key\": \"$APPID\",
    \"algorithm\": \"RS256\",
    \"rsa_public_key\": \"$(cat public_key.pem)\"
  }"
```

## Paso 6 — Verificar la autenticación

```bash
# Obtener token fresco
TOKEN=$(curl -s -X POST \
  "https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=<CLIENT_ID>" \
  -d "client_secret=<CLIENT_SECRET>" \
  -d "scope=api://<RESOURCE_APP_ID>/.default" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Invocar la API a través de Kong
curl -H "Authorization: Bearer $TOKEN" http://localhost:8000/clientes
# Respuesta esperada: 200 OK + array JSON de clientes

# Probar sin token
curl http://localhost:8000/clientes
# Respuesta esperada: 401 Unauthorized
```

## Resolución de problemas frecuentes

| Síntoma | Causa probable | Solución |
|---------|---------------|----------|
| 401 con token válido | `kid` en el token no coincide con la credencial registrada | Consultar JWKS, identificar kid correcto, recrear credencial |
| 401 desde el backend (.NET) | El backend intenta validar audiencia | El backend solo debe evaluar roles; Kong valida el token completo |
| 401 "token expired" | Token caducado | Reobtener token (expiran en ~3600 s) |
| Consumer no encontrado | `key_claim_name: appid` no coincide con el `key` de la credencial | Verificar que `key` de la credencial == `appid` del token |

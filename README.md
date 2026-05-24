# TFG — Diseño y validación de una plataforma segura de APIs para integración bancaria

**Autor:** Antonio Martos Gavilán  
**Tutor:** Oscar Martín Salas  
**Titulación:** Grado de Ingeniería Informática — Sistemas de Gestión del Conocimiento  
**Institución:** Universitat Oberta de Catalunya (UOC)  
**Curso:** 2025-26

---

## Descripción

Este repositorio contiene el código fuente, la configuración de infraestructura y los ficheros de despliegue de la **Prueba de Concepto (PoC)** del Trabajo de Fin de Grado.

La PoC implementa una plataforma segura de APIs para integrar, en un entorno controlado y anonimizado, una plataforma de banca comercial y un sistema de banca privada heredado. El objetivo es demostrar cómo una capa de APIs gobernada puede mejorar la interoperabilidad, la seguridad, la trazabilidad y la observabilidad de servicios bancarios expuestos de forma controlada.

La solución demuestra los siguientes principios:

- **Gobierno de APIs** centralizado mediante Kong Gateway.
- **Identidad federada** con Microsoft Entra ID mediante OAuth 2.0 / OpenID Connect.
- **Autenticación JWT** con validación RS256 en el gateway.
- **Autorización diferencial** por roles de aplicación en los backends .NET.
- **Observabilidad operativa** con Prometheus y Grafana.
- **Validación de seguridad** alineada con OWASP API Security Top 10.

> Este repositorio no debe contener credenciales reales, secretos de cliente, tokens JWT, claves privadas ni ficheros `.env` con configuración sensible.

---

## Arquitectura de la PoC

La PoC se ejecuta en local mediante contenedores Docker y se apoya en Microsoft Entra ID únicamente para la emisión de tokens JWT.

```
Cliente técnico
     │
     │ OAuth2 client credentials
     ▼
Microsoft Entra ID
     │
     │ JWT
     ▼
Kong Gateway
     │
     ├── ClientesApi (.NET 8)
     └── CuentasApi (.NET 8)

Prometheus ──> métricas Kong / APIs
Grafana    ──> visualización operativa
```

---

## Estructura del repositorio

```
tfg-api-poc/
├── docker-compose.yml
├── prometheus.yml
├── .env.example
├── .gitignore
├── README.md
├── get_token.sh
├── benchmark_gateway_overhead.sh
│
├── ClientesApi/
│   ├── ClientesApi.csproj
│   ├── Dockerfile
│   ├── Program.cs
│   └── Controllers/
│       └── ClientesController.cs
│
├── CuentasApi/
│   ├── CuentasApi.csproj
│   ├── Dockerfile
│   ├── Program.cs
│   └── Controllers/
│       └── CuentasController.cs
│
└── docs/
    ├── kong-setup.md
    └── kong-setup.sh
```

---

## Requisitos previos

| Herramienta | Versión recomendada | Uso |
|-------------|---------------------|-----|
| Docker Engine | 24.x o superior | Ejecución de contenedores |
| Docker Compose | 2.x | Orquestación local |
| .NET SDK | 8.0 o superior | Desarrollo y pruebas locales |
| Bash | 4.x o superior | Scripts auxiliares |
| curl | — | Pruebas HTTP y obtención de tokens |
| Python | 3.x | Procesado auxiliar en scripts |
| Microsoft Entra ID | — | Emisión de tokens OAuth2/JWT |

---

## Configuración segura de variables

Crear el fichero local `.env` a partir de la plantilla:

```bash
cp .env.example .env
```

Editar `.env` con los valores reales del tenant y de las aplicaciones registradas en Microsoft Entra ID:

```env
ENTRA_TENANT_ID=<tenant-id>
ENTRA_CLIENT_ID=<client-id-aplicacion-cliente>
ENTRA_CLIENT_SECRET=<client-secret-local>
ENTRA_RESOURCE_APP_ID=<application-id-api-recurso>
```

El fichero `.env` está excluido mediante `.gitignore` y **no debe subirse al repositorio**.

---

## Inicio rápido

### 1. Clonar el repositorio

```bash
git clone https://github.com/<usuario>/tfg-plataforma-segura-apis.git
cd tfg-plataforma-segura-apis
```

### 2. Preparar la configuración local

```bash
cp .env.example .env
nano .env
```

### 3. Arrancar la PoC

```bash
docker compose up -d --build
docker compose ps
```

### 4. Configurar Kong Gateway

```bash
chmod +x docs/kong-setup.sh
./docs/kong-setup.sh
```

El script debe registrar los servicios, rutas y plugins necesarios en Kong Gateway, incluyendo validación JWT, rate limiting y métricas Prometheus.

### 5. Obtener un token JWT

```bash
chmod +x get_token.sh
TOKEN=$(./get_token.sh)
```

### 6. Invocar las APIs protegidas

```bash
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/clientes
```

---

## Endpoints principales

Todos los endpoints funcionales se consumen a través de Kong Gateway en el puerto `8000`.

| Endpoint | Método | Permiso esperado | Descripción |
|----------|--------|------------------|-------------|
| `/clientes` | GET | `Clientes.Read.App` | Consulta de clientes |
| `/clientes` | POST | `Clientes.Write.App` | Alta de cliente |
| `/clientes/{id}` | GET | `Clientes.Read.App` | Consulta de cliente por identificador |
| `/cuentas` | GET | `Cuentas.Read.App` | Consulta de cuentas |
| `/cuentas/{id}` | GET | `Cuentas.Read.App` | Consulta de cuenta por identificador |
| `/cuentas/{id}/saldo` | GET | `Cuentas.Read.App` | Consulta de saldo |

---

## Control de acceso esperado

| Situación | Código HTTP esperado | Componente responsable |
|-----------|----------------------|------------------------|
| Petición sin `Authorization` | `401` | Kong Gateway |
| Token ausente, expirado o inválido | `401` | Kong Gateway |
| Token válido sin rol suficiente | `403` | Backend .NET |
| Token válido con rol suficiente | `200` | Backend .NET |
| Exceso de peticiones por consumer | `429` | Kong Gateway |

Este reparto de responsabilidades permite separar autenticación y autorización: Kong actúa como punto central de autenticación y control de tráfico, mientras que las APIs backend aplican reglas de autorización de negocio basadas en roles.

---

## Observabilidad

| Componente | URL local | Credenciales |
|------------|-----------|--------------|
| Prometheus | `http://localhost:9090` | Sin autenticación local |
| Grafana | `http://localhost:3000` | Definidas en `.env` |
| Métricas Kong | `http://localhost:8100/metrics` | Sin autenticación local |

Consultas PromQL utilizadas en la PoC:

```promql
rate(kong_nginx_requests_total[1m])
```

```promql
sum by (code) (rate(kong_http_status[5m]))
```

```promql
rate(kong_latency_ms_sum[1m]) / rate(kong_latency_ms_count[1m])
```

---

## Benchmark de overhead del gateway

El script `benchmark_gateway_overhead.sh` permite comparar la latencia del backend directo frente a la latencia de acceso a través de Kong Gateway con validación JWT.

Uso con token generado automáticamente desde `.env`:

```bash
chmod +x benchmark_gateway_overhead.sh get_token.sh
./benchmark_gateway_overhead.sh 100
```

Uso pasando el token explícitamente:

```bash
TOKEN=$(./get_token.sh)
./benchmark_gateway_overhead.sh "$TOKEN" 100
```

El resultado se genera en un fichero local con patrón:

```text
overhead_results_YYYYMMDD_HHMMSS.txt
```

Estos ficheros se excluyen del repositorio por defecto. Para incorporarlos a la memoria del TFG, se recomienda copiar únicamente las tablas o capturas necesarias en la documentación académica.

---

## Configuración de Microsoft Entra ID

La integración requiere, al menos, dos registros de aplicación:

### API protegida

Representa el recurso expuesto por la PoC.

Roles de aplicación definidos:

- `Clientes.Read.App`
- `Clientes.Write.App`
- `Cuentas.Read.App`

### Cliente técnico

Representa la aplicación de tipo daemon que consume las APIs mediante el flujo OAuth2 `client credentials`.

Permisos esperados:

- Asignación de roles de aplicación.
- Consentimiento de administrador cuando sea necesario.
- `client_secret` almacenado únicamente en `.env` local.

También puede configurarse un cliente limitado con un subconjunto de roles para demostrar respuestas `403 Forbidden` en servicios no autorizados.

---

## Validación de seguridad

La PoC se valida mediante:

- Ejecución de casos funcionales de alta y consulta de clientes.
- Consulta de cuentas y saldos.
- Pruebas con token válido, token ausente y token sin permisos suficientes.
- Verificación de rate limiting.
- Revisión de métricas operativas en Prometheus y Grafana.
- Checklist de riesgos alineado con OWASP API Security Top 10.

---

## Buenas prácticas de seguridad del repositorio

Antes de publicar cambios:

```bash
git status
git diff --staged
```

Comprobar que no se incluyen:

- Ficheros `.env`.
- Secretos de cliente.
- Tokens JWT.
- Claves privadas.
- Contraseñas reales.
- Capturas con datos sensibles.
- Identificadores internos no necesarios para la defensa académica.

Si un secreto real se ha subido previamente al repositorio, debe considerarse comprometido y rotarse en Microsoft Entra ID antes de continuar.

---

## Referencias

- Kong Gateway Documentation: https://docs.konghq.com/gateway/
- Microsoft Entra ID Documentation: https://learn.microsoft.com/en-us/entra/identity/
- OAuth 2.0 Framework — RFC 6749: https://www.rfc-editor.org/rfc/rfc6749
- JSON Web Token Profile for OAuth 2.0 — RFC 9068: https://www.rfc-editor.org/rfc/rfc9068
- OWASP API Security Top 10 2023: https://owasp.org/API-Security/

---

## Licencia

Este trabajo está sujeto a la licencia **Reconocimiento-NoComercial-SinObraDerivada 3.0 España de Creative Commons**.

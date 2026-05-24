using Microsoft.AspNetCore.Http.HttpResults;
using System.IdentityModel.Tokens.Jwt;

var builder = WebApplication.CreateBuilder(args);

// Se mantiene Swagger para facilitar pruebas durante la PoC.
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI();

/// <summary>
/// Extrae el token Bearer de la cabecera Authorization.
/// Si la cabecera no existe o no tiene formato Bearer, devuelve null.
/// </summary>
static string? ObtenerToken(HttpRequest request)
{
    var authorization = request.Headers.Authorization.ToString();

    if (string.IsNullOrWhiteSpace(authorization) || !authorization.StartsWith("Bearer "))
    {
        return null;
    }

    return authorization["Bearer ".Length..].Trim();
}

/// <summary>
/// Comprueba si el JWT contiene un rol concreto dentro de la claim "roles".
/// Kong ya ha validado el token; aquí se aplica autorización funcional.
/// </summary>
static bool TieneRol(HttpRequest request, string rolRequerido)
{
    var token = ObtenerToken(request);

    if (string.IsNullOrWhiteSpace(token))
    {
        return false;
    }

    var handler = new JwtSecurityTokenHandler();

    if (!handler.CanReadToken(token))
    {
        return false;
    }

    var jwt = handler.ReadJwtToken(token);

    return jwt.Claims
        .Where(c => c.Type == "roles")
        .Select(c => c.Value)
        .Contains(rolRequerido, StringComparer.OrdinalIgnoreCase);
}

/// <summary>
/// Devuelve 403 Forbidden cuando el rol requerido no está presente en el token.
/// </summary>
static IResult AutorizarPorRol(HttpRequest request, string rolRequerido)
{
    if (!TieneRol(request, rolRequerido))
    {
        return Results.Json(
            new
            {
                error = "forbidden",
                message = "El token no contiene el rol requerido.",
                requiredRole = rolRequerido
            },
            statusCode: StatusCodes.Status403Forbidden);
    }

    return Results.Ok();
}

// Endpoint raíz sin lógica de negocio.
app.MapGet("/", () =>
{
    return Results.Ok(new
    {
        message = "Cuentas API operativa",
        service = "cuentas-api",
        version = "v1"
    });
});

// Endpoint de salud. Requiere rol de lectura de cuentas.
app.MapGet("/health", (HttpRequest request) =>
{
    var autorizacion = AutorizarPorRol(request, "Cuentas.Read.App");
    if (autorizacion is not Ok<object> && autorizacion is not Ok)
    {
        return autorizacion;
    }

    return Results.Ok(new
    {
        status = "ok",
        service = "cuentas-api",
        timestamp = DateTime.UtcNow
    });
});

// Endpoint de consulta de cuentas.
app.MapGet("/cuentas", (HttpRequest request) =>
{
    var autorizacion = AutorizarPorRol(request, "Cuentas.Read.App");
    if (autorizacion is not Ok<object> && autorizacion is not Ok)
    {
        return autorizacion;
    }

    var cuentas = new[]
    {
        new
        {
            id = "ACC-001",
            iban = "ES9121000418450200051332",
            titular = "CLI-001",
            saldo = 125000.50,
            divisa = "EUR",
            estado = "Activa"
        },
        new
        {
            id = "ACC-002",
            iban = "ES6621000418450200051444",
            titular = "CLI-002",
            saldo = 8450.75,
            divisa = "EUR",
            estado = "Activa"
        }
    };

    return Results.Ok(cuentas);
});

// Endpoint de consulta individual de cuenta.
app.MapGet("/cuentas/{id}", (HttpRequest request, string id) =>
{
    var autorizacion = AutorizarPorRol(request, "Cuentas.Read.App");
    if (autorizacion is not Ok<object> && autorizacion is not Ok)
    {
        return autorizacion;
    }

    return Results.Ok(new
    {
        id,
        iban = "ES0000000000000000000000",
        titular = "CLI-001",
        saldo = 10000.00,
        divisa = "EUR",
        estado = "Activa"
    });
});

// Endpoint específico de saldo.
app.MapGet("/cuentas/{id}/saldo", (HttpRequest request, string id) =>
{
    var autorizacion = AutorizarPorRol(request, "Cuentas.Read.App");
    if (autorizacion is not Ok<object> && autorizacion is not Ok)
    {
        return autorizacion;
    }

    return Results.Ok(new
    {
        cuentaId = id,
        saldo = 10000.00,
        divisa = "EUR",
        fecha = DateTime.UtcNow
    });
});

app.Run();
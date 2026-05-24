<<<<<<< HEAD
using ClientesApi.Events;
using ClientesApi.Messaging;
using ClientesApi.Models;
=======
>>>>>>> 7812413 (feat: add incial API platforma segura PoC)
using Microsoft.AspNetCore.Http.HttpResults;
using System.IdentityModel.Tokens.Jwt;

var builder = WebApplication.CreateBuilder(args);

// Se mantiene Swagger para facilitar pruebas durante la PoC.
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
<<<<<<< HEAD
// Registro del publicador de eventos de integración.
// Se usa RabbitMQ como broker de mensajería asíncrona en la PoC.
builder.Services.AddScoped<IEventPublisher, RabbitMqEventPublisher>();
=======
>>>>>>> 7812413 (feat: add incial API platforma segura PoC)

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
/// En esta PoC, Kong ya ha validado la autenticación del token,
/// por lo que aquí solo se realiza autorización funcional.
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
/// Devuelve 403 Forbidden cuando el token no contiene el rol requerido.
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
        message = "Clientes API operativa",
        service = "clientes-api",
        version = "v1"
    });
});

<<<<<<< HEAD
// Endpoint técnico de salud.
// No requiere autorización porque se utiliza como línea base del benchmark
// y como comprobación operativa de disponibilidad del servicio.
app.MapGet("/health", () =>
{
=======
// Endpoint de salud. Requiere rol de lectura de clientes.
app.MapGet("/health", (HttpRequest request) =>
{
    var autorizacion = AutorizarPorRol(request, "Clientes.Read.App");
    if (autorizacion is not Ok<object> && autorizacion is not Ok)
    {
        return autorizacion;
    }

>>>>>>> 7812413 (feat: add incial API platforma segura PoC)
    return Results.Ok(new
    {
        status = "ok",
        service = "clientes-api",
        timestamp = DateTime.UtcNow
    });
<<<<<<< HEAD
})
.AllowAnonymous();
=======
});
>>>>>>> 7812413 (feat: add incial API platforma segura PoC)

// Endpoint de consulta de clientes.
app.MapGet("/clientes", (HttpRequest request) =>
{
    var autorizacion = AutorizarPorRol(request, "Clientes.Read.App");
    if (autorizacion is not Ok<object> && autorizacion is not Ok)
    {
        return autorizacion;
    }

    var clientes = new[]
    {
        new
        {
            id = "CLI-001",
            nombre = "Ana Gómez",
            segmento = "Banca Privada",
            estado = "Activo"
        },
        new
        {
            id = "CLI-002",
            nombre = "Luis Martín",
            segmento = "Banca Comercial",
            estado = "Activo"
        }
    };

    return Results.Ok(clientes);
});

<<<<<<< HEAD
// Endpoint de alta de cliente.
// Requiere rol de escritura de clientes y, tras el alta correcta,
// publica el evento ClienteCreado en RabbitMQ.
app.MapPost("/clientes", (
    HttpRequest request,
    ClienteAltaRequest clienteAlta,
    IEventPublisher eventPublisher,
    IConfiguration configuration) =>
{
    var autorizacion = AutorizarPorRol(request, "Clientes.Write.App");
    if (autorizacion is not Ok<object> && autorizacion is not Ok)
    {
        return autorizacion;
    }

    var clienteId = $"CLI-{Guid.NewGuid().ToString()[..8].ToUpper()}";

    var evento = new ClienteCreadoEvent
    {
        ClienteId = clienteId,
        Nombre = clienteAlta.Nombre,
        Segmento = clienteAlta.Segmento,
        FechaCreacionUtc = DateTime.UtcNow,
        Origen = "ClientesApi"
    };

    var queueName = configuration["RabbitMq:QueueName"] ?? "cliente-creado";

    eventPublisher.Publicar(queueName, evento);

    return Results.Created($"/clientes/{clienteId}", new
    {
        id = clienteId,
        nombre = clienteAlta.Nombre,
        segmento = clienteAlta.Segmento,
        estado = "Activo",
        eventoPublicado = "ClienteCreado"
    });
});

=======
>>>>>>> 7812413 (feat: add incial API platforma segura PoC)
// Endpoint de consulta individual de cliente.
app.MapGet("/clientes/{id}", (HttpRequest request, string id) =>
{
    var autorizacion = AutorizarPorRol(request, "Clientes.Read.App");
    if (autorizacion is not Ok<object> && autorizacion is not Ok)
    {
        return autorizacion;
    }

    return Results.Ok(new
    {
        id,
        nombre = $"Cliente {id}",
        segmento = "Banca Privada",
        estado = "Activo"
    });
});

app.Run();
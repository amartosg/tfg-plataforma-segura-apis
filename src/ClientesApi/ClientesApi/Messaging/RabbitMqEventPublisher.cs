using System.Text;
using System.Text.Json;
using RabbitMQ.Client;

namespace ClientesApi.Messaging;

public class RabbitMqEventPublisher : IEventPublisher
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<RabbitMqEventPublisher> _logger;

    public RabbitMqEventPublisher(
        IConfiguration configuration,
        ILogger<RabbitMqEventPublisher> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    public void Publicar<T>(string queueName, T evento)
    {
        var factory = new ConnectionFactory
        {
            HostName = _configuration["RabbitMq:Host"] ?? "localhost",
            UserName = _configuration["RabbitMq:User"] ?? "tfguser",
            Password = _configuration["RabbitMq:Password"] ?? "tfgpassword"
        };

        using var connection = factory.CreateConnection();
        using var channel = connection.CreateModel();

        // Declaración idempotente: si la cola no existe, RabbitMQ la crea.
        channel.QueueDeclare(
            queue: queueName,
            durable: true,
            exclusive: false,
            autoDelete: false,
            arguments: null);

        var json = JsonSerializer.Serialize(evento);
        var body = Encoding.UTF8.GetBytes(json);

        var properties = channel.CreateBasicProperties();
        properties.Persistent = true;
        properties.ContentType = "application/json";

        channel.BasicPublish(
            exchange: string.Empty,
            routingKey: queueName,
            basicProperties: properties,
            body: body);

        _logger.LogInformation(
            "Evento publicado en RabbitMQ. Cola: {QueueName}. Mensaje: {Mensaje}",
            queueName,
            json);
    }
}
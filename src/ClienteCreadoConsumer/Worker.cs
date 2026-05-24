using System.Text;
using RabbitMQ.Client;
using RabbitMQ.Client.Events;

namespace ClienteCreadoConsumer;

// Servicio de fondo que consume eventos ClienteCreado desde RabbitMQ.
// En la PoC, el procesamiento consiste en registrar el evento en logs.
public class Worker : BackgroundService
{
    private readonly ILogger<Worker> _logger;
    private readonly IConfiguration _configuration;

    public Worker(ILogger<Worker> logger, IConfiguration configuration)
    {
        _logger = logger;
        _configuration = configuration;
    }

    protected override Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var host = _configuration["RabbitMq:Host"] ?? "rabbitmq";
        var user = _configuration["RabbitMq:User"] ?? "tfguser";
        var password = _configuration["RabbitMq:Password"] ?? "tfgpassword";
        var queueName = _configuration["RabbitMq:QueueName"] ?? "cliente-creado";

        var factory = new ConnectionFactory
        {
            HostName = host,
            UserName = user,
            Password = password
        };

        var connection = factory.CreateConnection();
        var channel = connection.CreateModel();

        channel.QueueDeclare(
            queue: queueName,
            durable: true,
            exclusive: false,
            autoDelete: false,
            arguments: null);

        var consumer = new EventingBasicConsumer(channel);

        consumer.Received += (_, ea) =>
        {
            var body = ea.Body.ToArray();
            var message = Encoding.UTF8.GetString(body);

            _logger.LogInformation(
                "Evento ClienteCreado recibido desde RabbitMQ. Cola: {QueueName}. Mensaje: {Message}",
                queueName,
                message);

            channel.BasicAck(
                deliveryTag: ea.DeliveryTag,
                multiple: false);
        };

        channel.BasicConsume(
            queue: queueName,
            autoAck: false,
            consumer: consumer);

        _logger.LogInformation(
            "Consumidor ClienteCreado iniciado. Esperando mensajes en la cola {QueueName}",
            queueName);

        return Task.CompletedTask;
    }
}
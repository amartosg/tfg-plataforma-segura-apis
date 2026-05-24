namespace ClientesApi.Messaging;

public interface IEventPublisher
{
    void Publicar<T>(string queueName, T evento);
}
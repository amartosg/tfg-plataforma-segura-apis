namespace ClientesApi.Events;

// Evento de integración emitido cuando se completa el alta de un cliente.
// No se incluyen datos sensibles innecesarios para mantener el principio de minimización.
public class ClienteCreadoEvent{
    public string ClienteId { get; set; } = string.Empty;
    public string Nombre { get; set; } = string.Empty;
    public string Segmento { get; set; } = string.Empty;
    public DateTime FechaCreacionUtc { get; set; }
    public string Origen { get; set; } = "ClientesApi";
}

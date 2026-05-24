namespace ClientesApi.Models;

// Modelo de entrada para simular el alta de cliente en la PoC.
public class ClienteAltaRequest
{
    public string Nombre { get; set; } = string.Empty;
    public string Segmento { get; set; } = "Banca Comercial";
}
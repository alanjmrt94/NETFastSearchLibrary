namespace NETFastSearchLibrary
{
    /// <summary>
    /// Especifica dónde se ejecutan los manejadores de eventos durante la búsqueda.
    /// </summary>
    public enum ExecuteHandlers
    {
        /// <summary>
        /// Los manejadores se ejecutan en la misma tarea donde se encontraron los archivos.
        /// </summary>
        InCurrentTask = 0,

        /// <summary>
        /// Los manejadores se ejecutan en una tarea nueva del pool de hilos.
        /// </summary>
        InNewTask = 1
    }
}

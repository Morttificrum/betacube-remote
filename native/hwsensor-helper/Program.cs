using System.Text.Json;
using LibreHardwareMonitor.Hardware;

namespace HwSensorHelper;

// Beta Cube Remote — helper de sensores de hardware.
// Roda uma leitura, imprime um JSON no stdout, sai. Sem estado, sem laço —
// quem chama (o serviço Rust) decide a cadência. Precisa rodar elevado
// (o driver de baixo nível do LibreHardwareMonitor exige Administrador);
// como o serviço do Beta Cube Remote já roda como LocalSystem, isso não
// pede UAC extra.
public static class Program
{
    public static void Main()
    {
        var computer = new Computer
        {
            IsCpuEnabled = true,
            IsGpuEnabled = true,
            IsMotherboardEnabled = true,
            IsStorageEnabled = true,
            IsMemoryEnabled = true,
            IsControllerEnabled = true,
        };

        var readings = new List<object>();

        try
        {
            computer.Open();
            computer.Accept(new UpdateVisitor());

            foreach (var hardware in computer.Hardware)
            {
                CollectSensors(hardware, readings);
                foreach (var sub in hardware.SubHardware)
                {
                    CollectSensors(sub, readings);
                }
            }
        }
        finally
        {
            computer.Close();
        }

        Console.WriteLine(JsonSerializer.Serialize(new { sensors = readings }));
    }

    // Só os tipos relevantes pro que a Fase 3 pede (temp/voltagem/fan/uso) —
    // LibreHardwareMonitor devolve dezenas de sensores extras (clocks, D3D,
    // throughput de barramento, etc.) que só inflariam o payload à toa.
    // Level cobre "Remaining Life"/vida útil de SSD, usado no alerta crítico
    // de SMART.
    private static readonly HashSet<SensorType> RelevantTypes = new()
    {
        SensorType.Temperature,
        SensorType.Voltage,
        SensorType.Fan,
        SensorType.Load,
        SensorType.Level,
    };

    private static void CollectSensors(IHardware hardware, List<object> readings)
    {
        foreach (var sensor in hardware.Sensors)
        {
            if (sensor.Value is null) continue;
            if (!RelevantTypes.Contains(sensor.SensorType)) continue;
            readings.Add(new
            {
                hardware = hardware.Name,
                hardware_type = hardware.HardwareType.ToString(),
                sensor = sensor.Name,
                sensor_type = sensor.SensorType.ToString(),
                value = sensor.Value,
            });
        }
    }
}

internal class UpdateVisitor : IVisitor
{
    public void VisitComputer(IComputer computer) => computer.Traverse(this);

    public void VisitHardware(IHardware hardware)
    {
        hardware.Update();
        foreach (var sub in hardware.SubHardware) sub.Accept(this);
    }

    public void VisitSensor(ISensor sensor) { }
    public void VisitParameter(IParameter parameter) { }
}

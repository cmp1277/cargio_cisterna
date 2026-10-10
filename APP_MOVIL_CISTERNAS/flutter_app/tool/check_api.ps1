<#
.SYNOPSIS
Comprueba las dos rutas de disponibilidad del backend, sin iniciar sesion ni guardar registros.
.EXAMPLE
.\tool\check_api.ps1 -ConfigFile .\config\pythonanywhere.json.example
.EXAMPLE
.\tool\check_api.ps1 -ApiUrl https://crismp.pythonanywhere.com/api/mobile
#>
[CmdletBinding(DefaultParameterSetName = 'Url')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Url')]
    [string]$ApiUrl,

    [Parameter(Mandatory = $true, ParameterSetName = 'Config')]
    [string]$ConfigFile,

    [ValidateRange(1, 60)]
    [int]$TimeoutSeconds = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    if ($PSCmdlet.ParameterSetName -eq 'Config') {
        $config = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
        if (-not $config.PSObject.Properties['API_URL'] -or $config.API_URL -isnot [string]) {
            throw 'El archivo debe contener API_URL como texto.'
        }
        $ApiUrl = $config.API_URL
    }

    $endpoint = $null
    if (-not [Uri]::TryCreate($ApiUrl, [UriKind]::Absolute, [ref]$endpoint) -or
        $endpoint.Scheme -ne 'https' -or [string]::IsNullOrWhiteSpace($endpoint.Host) -or
        $endpoint.UserInfo -ne '' -or $endpoint.Query -ne '' -or $endpoint.Fragment -ne '' -or
        -not $endpoint.AbsolutePath.EndsWith('/api/mobile', [StringComparison]::Ordinal)) {
        throw 'API_URL debe ser una URL HTTPS sin credenciales, consulta ni fragmento, terminada en /api/mobile.'
    }
    $healthBuilder = [UriBuilder]::new($endpoint)
    $healthBuilder.Path = $endpoint.AbsolutePath.Substring(0, $endpoint.AbsolutePath.Length - 'mobile'.Length) + 'health'
    Add-Type -AssemblyName System.Net.Http
}
catch {
    [Console]::Error.WriteLine('Configuracion invalida. Use una URL HTTPS de la API o un archivo JSON con API_URL; la ruta debe terminar en /api/mobile.')
    exit 2
}

$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false
$handler.UseCookies = $false
$handler.UseDefaultCredentials = $false
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
$client.MaxResponseContentBufferSize = 65536
$previousSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
[Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$failed = $false

try {
    $checks = @(
        @{ Name = 'GET salud'; Method = [System.Net.Http.HttpMethod]::Get; Uri = $healthBuilder.Uri },
        @{ Name = 'POST prueba movil'; Method = [System.Net.Http.HttpMethod]::Post; Uri = $endpoint }
    )
    foreach ($check in $checks) {
        $request = [System.Net.Http.HttpRequestMessage]::new($check.Method, $check.Uri)
        $response = $null
        try {
            $request.Headers.Accept.ParseAdd('application/json')
            if ($check.Method -eq [System.Net.Http.HttpMethod]::Post) {
                $request.Content = [System.Net.Http.StringContent]::new('{"action":"test"}', [Text.Encoding]::UTF8, 'application/json')
            }
            $response = $client.SendAsync($request).GetAwaiter().GetResult()
            $status = [int]$response.StatusCode
            if (-not $response.IsSuccessStatusCode) {
                $failed = $true
                [Console]::Error.WriteLine(('{0}: HTTP {1}. No se siguen redirecciones.' -f $check.Name, $status))
                continue
            }
            $payload = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
            if (-not $payload -or -not $payload.PSObject.Properties['success'] -or
                $payload.success -isnot [bool] -or -not $payload.success) {
                $failed = $true
                [Console]::Error.WriteLine(('{0}: JSON sin success:true.' -f $check.Name))
                continue
            }
            Write-Host ('{0}: OK (HTTP {1}, success:true).' -f $check.Name, $status)
        }
        catch {
            $failed = $true
            [Console]::Error.WriteLine(('{0}: fallo de conexion, tiempo de espera ({1}s) o respuesta JSON invalida.' -f $check.Name, $TimeoutSeconds))
        }
        finally {
            if ($null -ne $response) { $response.Dispose() }
            $request.Dispose()
        }
    }
}
finally {
    $client.Dispose()
    $handler.Dispose()
    [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol
}

if ($failed) {
    [Console]::Error.WriteLine('API no validada. Revise la Web app y sus registros antes de compilar con esta direccion.')
    exit 1
}
Write-Host 'Disponibilidad validada. Esta comprobacion no verifica login, escritura ni persistencia de la base de datos.'
exit 0

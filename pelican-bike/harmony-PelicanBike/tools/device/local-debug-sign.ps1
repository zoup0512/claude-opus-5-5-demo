[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("prepare", "verify", "sign", "install", "all", "help")]
    [string]$Command = "help",

    [string]$Serial = "127.0.0.1:10178",
    [string]$UnsignedHap = "",
    [string]$SignedHap = "",
    [ValidateRange(10, 1800)]
    [int]$TimeoutSec = 180
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$script:ScriptRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$script:ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $script:ScriptRoot "..\.."))
$script:SignRoot = Join-Path $script:ProjectRoot "entry\sign\debug"
$script:BundleName = "com.riba2534.pelicanbike"
$script:KeyAlias = "pelicanbike-local-debug"
$script:ProfileAlias = "openharmony application profile debug"
$script:SdkStorePassword = "123456"
$script:SdkProfilePassword = "123456"
$script:CompatibleApi = "24"

$script:Paths = [ordered]@{
    Secrets = Join-Path $script:SignRoot ".local-signing.json"
    Store = Join-Path $script:SignRoot "pelicanbike-local-debug.p12"
    AppCert = Join-Path $script:SignRoot "pelicanbike-local-debug.cer"
    ProfileJson = Join-Path $script:SignRoot "pelicanbike-local-debug-profile.json"
    Profile = Join-Path $script:SignRoot "pelicanbike-local-debug-profile.p7b"
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-WarnMessage {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Convert-InputPath {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $PathValue
    }
    if ($PathValue -match '^/([A-Za-z])/(.*)$') {
        return "$($Matches[1].ToUpperInvariant()):\$($Matches[2] -replace '/', '\')"
    }
    return $PathValue
}

function Resolve-ProjectPath {
    param([string]$PathValue)
    $converted = Convert-InputPath $PathValue
    if (-not [System.IO.Path]::IsPathRooted($converted)) {
        $converted = Join-Path $script:ProjectRoot $converted
    }
    return [System.IO.Path]::GetFullPath($converted)
}

function Assert-ProjectIdentity {
    $appConfig = Join-Path $script:ProjectRoot "AppScope\app.json5"
    if (-not (Test-Path -LiteralPath $appConfig -PathType Leaf)) {
        throw "Project identity file is missing: $appConfig"
    }
    $text = Get-Content -LiteralPath $appConfig -Raw
    $match = [Regex]::Match($text, '"?bundleName"?\s*:\s*"([^"]+)"')
    if (-not $match.Success -or $match.Groups[1].Value -ne $script:BundleName) {
        throw "Project bundleName must be exactly '$script:BundleName'."
    }
}

function Get-Toolchain {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($root in @($env:DEVECO_SDK_HOME, $env:HOS_SDK_HOME, $env:OHOS_BASE_SDK_HOME)) {
        if (-not [string]::IsNullOrWhiteSpace($root)) {
            $candidates.Add($root.Trim('"'))
        }
    }
    $candidates.Add("C:\Program Files\Huawei\DevEco Studio\sdk")
    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA "OpenHarmony\Sdk"))
        $candidates.Add((Join-Path $env:LOCALAPPDATA "Huawei\Sdk"))
    }

    $toolDirs = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path -LiteralPath $candidate -PathType Container)) {
            continue
        }
        foreach ($relative in @("default\openharmony\toolchains", "23\toolchains", "toolchains")) {
            $dir = Join-Path $candidate $relative
            if (Test-Path -LiteralPath (Join-Path $dir "lib\hap-sign-tool.jar") -PathType Leaf) {
                $toolDirs.Add([System.IO.Path]::GetFullPath($dir))
            }
        }
        Get-ChildItem -LiteralPath $candidate -Filter "hap-sign-tool.jar" -File -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object { $toolDirs.Add([System.IO.Path]::GetFullPath((Split-Path -Parent (Split-Path -Parent $_.FullName)))) }
    }

    $toolDir = @($toolDirs | Select-Object -Unique | Select-Object -First 1)
    if (@($toolDir).Count -eq 0) {
        throw "OpenHarmony hap-sign-tool.jar was not found in the installed SDK."
    }
    $toolDir = @($toolDir)[0]

    $javaCandidates = New-Object System.Collections.Generic.List[string]
    if ($env:JAVA_HOME) {
        $javaCandidates.Add((Join-Path $env:JAVA_HOME "bin\java.exe"))
    }
    $javaCandidates.Add("C:\Program Files\Huawei\DevEco Studio\jbr\bin\java.exe")
    $javaCommand = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($javaCommand) {
        $javaCandidates.Add($javaCommand.Source)
    }
    $java = @($javaCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -Unique | Select-Object -First 1)
    if (@($java).Count -eq 0) {
        throw "Java 17 was not found. Set JAVA_HOME or install DevEco Studio."
    }
    $javaPath = @($java)[0]

    $keytoolCandidates = @(
        (Join-Path (Split-Path -Parent $javaPath) "keytool.exe"),
        (Join-Path $env:JAVA_HOME "bin\keytool.exe"),
        "C:\Program Files\Huawei\DevEco Studio\jbr\bin\keytool.exe"
    )
    $keytool = @($keytoolCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -Unique | Select-Object -First 1)
    if (@($keytool).Count -eq 0) {
        throw "keytool.exe was not found next to Java or in DevEco Studio."
    }
    $keytoolPath = @($keytool)[0]

    $lib = Join-Path $toolDir "lib"
    $required = [ordered]@{
        Hdc = Join-Path $toolDir "hdc.exe"
        SignTool = Join-Path $lib "hap-sign-tool.jar"
        SdkStore = Join-Path $lib "OpenHarmony.p12"
        ProfileChain = Join-Path $lib "OpenHarmonyProfileDebug.pem"
    }
    foreach ($entry in $required.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
            throw "Required SDK file is missing ($($entry.Key)): $($entry.Value)"
        }
    }

    return [pscustomobject]@{
        Java = $javaPath
        Keytool = $keytoolPath
        Hdc = $required.Hdc
        SignTool = $required.SignTool
        SdkStore = $required.SdkStore
        ProfileChain = $required.ProfileChain
    }
}

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [switch]$Capture,
        [switch]$Sensitive
    )

    if ($Capture -or $Sensitive) {
        $previousInformationPreference = $InformationPreference
        $InformationPreference = "SilentlyContinue"
        try {
            $lines = @(& $FilePath @Arguments 2>&1 | ForEach-Object { [string]$_.ToString() })
            $exitCode = $LASTEXITCODE
        } finally {
            $InformationPreference = $previousInformationPreference
        }
        if ($Sensitive) {
            # Native output can be emitted through PowerShell information records
            # on Windows PowerShell 5.1. Clear it before returning.
            $lines = @()
        }
        if ($exitCode -ne 0) {
            if ($Sensitive) {
                throw "Signing command failed with exit code $exitCode. Secret-bearing command arguments and output were suppressed."
            }
            throw "Command failed ($exitCode): $FilePath`n$($lines -join [Environment]::NewLine)"
        }
        if ($Capture) {
            return [pscustomobject]@{ Lines = $lines; Text = ($lines -join [Environment]::NewLine) }
        }
        # Suppress localized success text as well as all output from commands
        # whose argument vector contains credentials.
        return $null
    }

    & $FilePath @Arguments 2>&1 | ForEach-Object { Write-Host $_.ToString() }
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath"
    }
}

function Invoke-SignTool {
    param(
        $Tools,
        [string]$Action,
        [string[]]$Arguments,
        [switch]$Sensitive,
        [switch]$Capture
    )
    $all = @("-jar", $Tools.SignTool, $Action) + $Arguments
    return Invoke-External -FilePath $Tools.Java -Arguments $all -Sensitive:$Sensitive -Capture:$Capture
}

function Set-RestrictedFileAccess {
    param([string]$PathValue)
    try {
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        & icacls.exe $PathValue /inheritance:r /grant:r "${currentUser}:(F)" /c | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "icacls returned $LASTEXITCODE"
        }
    } catch {
        Write-WarnMessage "Could not fully restrict ACLs on ${PathValue}: $($_.Exception.Message)"
    }
}

function New-RandomPassword {
    $bytes = New-Object byte[] 48
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }
    return ([Convert]::ToBase64String($bytes) -replace '[+/=]', 'x')
}

function Read-Secrets {
    if (-not (Test-Path -LiteralPath $script:Paths.Secrets -PathType Leaf)) {
        return $null
    }
    try {
        $data = Get-Content -LiteralPath $script:Paths.Secrets -Raw | ConvertFrom-Json
    } catch {
        throw "Local signing secret file is unreadable. Refusing to overwrite it: $($script:Paths.Secrets)"
    }
    if ([string]::IsNullOrWhiteSpace([string]$data.storePassword) -or [string]::IsNullOrWhiteSpace([string]$data.keyPassword)) {
        throw "Local signing secret file is incomplete. Refusing to overwrite it: $($script:Paths.Secrets)"
    }
    return $data
}

function New-Secrets {
    if (Test-Path -LiteralPath $script:Paths.Secrets -PathType Leaf) {
        throw "Secret file already exists; refusing to overwrite it: $($script:Paths.Secrets)"
    }
    $storePassword = New-RandomPassword
    $data = [ordered]@{
        schemaVersion = 1
        bundleName = $script:BundleName
        keyAlias = $script:KeyAlias
        storePassword = $storePassword
        # SunPKCS12 uses one password for the store and private-key entry.
        keyPassword = $storePassword
        createdUtc = [DateTime]::UtcNow.ToString("o")
    }

    $json = $data | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($script:Paths.Secrets, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Set-RestrictedFileAccess -PathValue $script:Paths.Secrets
    return ($json | ConvertFrom-Json)
}

function Get-LiveDeviceUdid {
    param($Tools)
    if ([string]::IsNullOrWhiteSpace($Serial)) {
        throw "-Serial must name an explicit HDC target. Default is 127.0.0.1:10178 for Pura90."
    }
    $result = Invoke-External -FilePath $Tools.Hdc -Arguments @("-t", $Serial, "shell", "bm", "get", "--udid") -Capture
    $match = [Regex]::Match($result.Text, '(?im)\b([0-9A-F]{32,128})\b')
    if (-not $match.Success) {
        throw "Could not parse a live UDID from HDC target '$Serial'."
    }
    $udid = $match.Groups[1].Value.ToUpperInvariant()
    Write-Info "Live target: $Serial; UDID: $udid"
    return $udid
}

function Get-PemCertificates {
    param([string]$Text)
    return @([Regex]::Matches($Text, '-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----') | ForEach-Object {
        ($_.Value -replace "`r?`n", "`n") + "`n"
    })
}

function Normalize-Pem {
    param([string]$Pem)
    if ($null -eq $Pem) { return "" }
    return ($Pem -replace '\s', '')
}

function Export-KeytoolCertificateDer {
    param($Tools, [string]$Store, [string]$Alias, [string]$StorePassword, [string]$Destination)
    Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue

    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Tools.Keytool
    $startInfo.Arguments = (@(
        "-exportcert", "-alias", $Alias,
        "-keystore", $Store, "-storetype", "PKCS12", "-storepass", $StorePassword,
        "-file", $Destination
    ) | ForEach-Object { '"' + ($_.Replace('"', '\"')) + '"' }) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    try {
        $process.StartInfo = $startInfo
        if (-not $process.Start()) { throw "Could not start keytool certificate export." }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $null = $stdout.GetAwaiter().GetResult()
        $null = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "Keytool certificate export failed. Credential-bearing arguments and localized output were suppressed."
        }
    } finally {
        $process.Dispose()
    }

    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf) -or (Get-Item -LiteralPath $Destination).Length -lt 100) {
        throw "Could not export DER certificate for alias '$Alias'."
    }
    return
}

function Convert-DerCertificateToPem {
    param([string]$DerPath)
    $bytes = [System.IO.File]::ReadAllBytes($DerPath)
    $base64 = [Convert]::ToBase64String($bytes)
    $builder = New-Object Text.StringBuilder
    [void]$builder.AppendLine("-----BEGIN CERTIFICATE-----")
    for ($offset = 0; $offset -lt $base64.Length; $offset += 64) {
        [void]$builder.AppendLine($base64.Substring($offset, [Math]::Min(64, $base64.Length - $offset)))
    }
    [void]$builder.AppendLine("-----END CERTIFICATE-----")
    return $builder.ToString().Replace("`r`n", "`n")
}

function Get-KeytoolCertificatePem {
    param($Tools, [string]$Store, [string]$Alias, [string]$StorePassword)
    $tempDer = Join-Path ([System.IO.Path]::GetTempPath()) ("pelicanbike-cert-" + [Guid]::NewGuid().ToString("N") + ".cer")
    try {
        Export-KeytoolCertificateDer -Tools $Tools -Store $Store -Alias $Alias -StorePassword $StorePassword -Destination $tempDer
        return Convert-DerCertificateToPem -DerPath $tempDer
    } finally {
        Remove-Item -LiteralPath $tempDer -Force -ErrorAction SilentlyContinue
    }
}

function Get-SdkCaPem {
    param($Tools)
    return Get-KeytoolCertificatePem -Tools $Tools -Store $Tools.SdkStore -Alias "openharmony application ca" -StorePassword $script:SdkStorePassword
}

function Get-SdkRootCaPem {
    param($Tools)
    return Get-KeytoolCertificatePem -Tools $Tools -Store $Tools.SdkStore -Alias "openharmony application root ca" -StorePassword $script:SdkStorePassword
}

function Convert-PemCertificateToX509 {
    param([string]$Pem)
    $match = [Regex]::Match($Pem, '-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----', [Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) {
        throw "Invalid PEM certificate."
    }
    $bytes = [Convert]::FromBase64String(($match.Groups[1].Value -replace '\s', ''))
    return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($bytes)
}

function Convert-PemToDer {
    param([string]$Pem, [string]$Destination)
    $match = [Regex]::Match($Pem, '-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----', [Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $match.Success) {
        throw "Invalid PEM certificate while creating DER input."
    }
    $der = [Convert]::FromBase64String(($match.Groups[1].Value -replace '\s', ''))
    [System.IO.File]::WriteAllBytes($Destination, $der)
}

function Get-VerifiedProfile {
    param($Tools, [string]$ProfilePath)
    $resultFile = Join-Path ([System.IO.Path]::GetTempPath()) ("pelicanbike-profile-" + [Guid]::NewGuid().ToString("N") + ".json")
    try {
        Invoke-SignTool -Tools $Tools -Action "verify-profile" -Arguments @("-inFile", $ProfilePath, "-outFile", $resultFile) | Out-Null
        if (-not (Test-Path -LiteralPath $resultFile -PathType Leaf)) {
            throw "verify-profile did not create its result file."
        }
        $verified = Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json
        if (-not $verified.verifiedPassed) {
            throw "Provision profile verification failed: $($verified.message)"
        }
        return $verified
    } finally {
        Remove-Item -LiteralPath $resultFile -Force -ErrorAction SilentlyContinue
    }
}

function Test-CertificateValidity {
    param([string]$CertificatePem, [string]$ExpectedSubjectFragment, [string]$ExpectedIssuerFragment)
    $certificate = Convert-PemCertificateToX509 -Pem $CertificatePem
    try {
        if ($certificate.Subject -notlike "*$ExpectedSubjectFragment*") {
            throw "Certificate subject does not identify this project: expected '$ExpectedSubjectFragment'."
        }
        if ($certificate.Issuer -notlike "*$ExpectedIssuerFragment*") {
            throw "Certificate issuer is not the SDK OpenHarmony CA."
        }
        $now = [DateTime]::UtcNow
        if ($now -lt $certificate.NotBefore.ToUniversalTime() -or $now -gt $certificate.NotAfter.ToUniversalTime()) {
            throw "Application certificate is outside its validity window: $($certificate.NotBefore.ToString('o')) .. $($certificate.NotAfter.ToString('o'))"
        }
    } finally {
        $certificate.Dispose()
    }
}

function Assert-ExistingMaterial {
    param($Tools, [string]$Udid, $Secrets)
    $required = @($script:Paths.Store, $script:Paths.AppCert, $script:Paths.ProfileJson, $script:Paths.Profile, $script:Paths.Secrets)
    foreach ($path in $required) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Local signing material is incomplete; refusing partial reuse. Missing: $path"
        }
    }
    if ([string]$Secrets.bundleName -ne $script:BundleName -or [string]$Secrets.keyAlias -ne $script:KeyAlias) {
        throw "Secret metadata does not belong to this bundle/key alias. Refusing reuse."
    }

    Invoke-External -FilePath $Tools.Keytool -Arguments @(
        "-list", "-alias", $script:KeyAlias,
        "-keystore", $script:Paths.Store, "-storetype", "PKCS12",
        "-storepass", [string]$Secrets.storePassword
    ) -Capture -Sensitive | Out-Null

    $certText = Get-Content -LiteralPath $script:Paths.AppCert -Raw
    $appCerts = Get-PemCertificates -Text $certText
    if (@($appCerts).Count -lt 3) {
        throw "App certificate chain is incomplete."
    }
    Test-CertificateValidity -CertificatePem $appCerts[0] `
        -ExpectedSubjectFragment "CN=PelicanBike Local Debug" `
        -ExpectedIssuerFragment "CN=OpenHarmony Application CA"

    # generate-app-cert emits the issued chain separately; PKCS#12 may retain the
    # original self-signed placeholder certificate for the same private key.
    # sign-app is the authoritative private-key/certificate match check and is
    # always followed by verify-app. Here we only prove the expected private-key
    # alias can be opened with this project's local secret.
    $sdkCa = Get-SdkCaPem -Tools $Tools
    $sdkRootCa = Get-SdkRootCaPem -Tools $Tools
    if ((Normalize-Pem $sdkCa) -ne (Normalize-Pem $appCerts[1]) -or
        (Normalize-Pem $sdkRootCa) -ne (Normalize-Pem $appCerts[2])) {
        throw "App certificate chain is not anchored to this SDK's OpenHarmony Application CA/root CA."
    }

    $profileSource = Get-Content -LiteralPath $script:Paths.ProfileJson -Raw | ConvertFrom-Json
    if ($profileSource.type -ne "debug" -or $profileSource.'bundle-info'.'bundle-name' -ne $script:BundleName) {
        throw "Profile source is not a debug profile for '$script:BundleName'."
    }
    if (@($profileSource.'debug-info'.'device-ids') -notcontains $Udid) {
        throw "Existing profile is not bound to live device UDID '$Udid'. Refusing overwrite; use a fresh isolated checkout/sign directory for another device."
    }

    $verified = Get-VerifiedProfile -Tools $Tools -ProfilePath $script:Paths.Profile
    $content = $verified.content
    if ($content.type -ne "debug" -or $content.'bundle-info'.'bundle-name' -ne $script:BundleName) {
        throw "Signed profile is not a debug profile for '$script:BundleName'."
    }
    if (@($content.'debug-info'.'device-ids') -notcontains $Udid) {
        throw "Signed profile does not include live device UDID '$Udid'."
    }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($now -lt [int64]$content.validity.'not-before' -or $now -gt [int64]$content.validity.'not-after') {
        throw "Signed profile is outside its validity window."
    }
    if ((Normalize-Pem $content.'bundle-info'.'development-certificate') -ne (Normalize-Pem $certText)) {
        throw "Signed profile development-certificate does not match the project-local app certificate chain."
    }
    Write-Info "Existing local debug signing material verified and will be reused without overwrite."
    return $verified
}

function New-LocalMaterial {
    param($Tools, [string]$Udid, $Secrets)
    if (Test-Path -LiteralPath $script:Paths.Store -PathType Leaf) {
        Invoke-External -FilePath $Tools.Keytool -Arguments @(
            "-list", "-alias", $script:KeyAlias,
            "-keystore", $script:Paths.Store, "-storetype", "PKCS12",
            "-storepass", [string]$Secrets.storePassword, "-keypass", [string]$Secrets.keyPassword
        ) -Capture -Sensitive | Out-Null
        Write-Info "Verified the existing project-private key and will continue the incomplete first run without overwriting it."
    } else {
        Write-Info "Generating a project-private ECC P-256 key. Passwords remain local and are never printed."
        Invoke-SignTool -Tools $Tools -Action "generate-keypair" -Sensitive -Arguments @(
            "-keyAlias", $script:KeyAlias,
            "-keyPwd", [string]$Secrets.keyPassword,
            "-keyAlg", "ECC",
            "-keySize", "NIST-P-256",
            "-keystoreFile", $script:Paths.Store,
            "-keystorePwd", [string]$Secrets.storePassword,
            "-pwdInputMode", "0"
        )
        Set-RestrictedFileAccess -PathValue $script:Paths.Store
    }

    foreach ($derived in @($script:Paths.AppCert, $script:Paths.ProfileJson, $script:Paths.Profile)) {
        if (Test-Path -LiteralPath $derived) {
            throw "Incomplete local signing state contains a derived file that cannot yet be verified; refusing overwrite: $derived"
        }
    }

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("pelicanbike-local-sign-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    try {
        $sdkCaDer = Join-Path $tempDir "OpenHarmony-Application-CA.cer"
        $sdkRootCaDer = Join-Path $tempDir "OpenHarmony-Application-Root-CA.cer"
        $null = Export-KeytoolCertificateDer -Tools $Tools -Store $Tools.SdkStore -Alias "openharmony application ca" `
            -StorePassword $script:SdkStorePassword -Destination $sdkCaDer
        $null = Export-KeytoolCertificateDer -Tools $Tools -Store $Tools.SdkStore -Alias "openharmony application root ca" `
            -StorePassword $script:SdkStorePassword -Destination $sdkRootCaDer

        Write-Info "Issuing the project app certificate with the SDK OpenHarmony Application CA (DER CA inputs)."
        Invoke-SignTool -Tools $Tools -Action "generate-app-cert" -Sensitive -Arguments @(
            "-keyAlias", $script:KeyAlias,
            "-keyPwd", [string]$Secrets.keyPassword,
            "-issuer", "C=CN,O=OpenHarmony,OU=OpenHarmony Team,CN=OpenHarmony Application CA",
            "-issuerKeyAlias", "openharmony application ca",
            "-issuerKeyPwd", $script:SdkStorePassword,
            "-subject", "C=CN,O=riba2534,OU=Local Development,CN=PelicanBike Local Debug",
            "-validity", "3650",
            "-signAlg", "SHA256withECDSA",
            "-issuerKeystoreFile", $Tools.SdkStore,
            "-issuerKeystorePwd", $script:SdkStorePassword,
            "-keystoreFile", $script:Paths.Store,
            "-keystorePwd", [string]$Secrets.storePassword,
            "-outForm", "certChain",
            "-rootCaCertFile", $sdkRootCaDer,
            "-subCaCertFile", $sdkCaDer,
            "-outFile", $script:Paths.AppCert,
            "-pwdInputMode", "0"
        )

        $certText = Get-Content -LiteralPath $script:Paths.AppCert -Raw
        $certs = Get-PemCertificates -Text $certText
        if (@($certs).Count -lt 3) {
            throw "Generated app certificate chain is incomplete."
        }

        $now = [DateTimeOffset]::UtcNow
        $profile = [ordered]@{
            "version-name" = "2.0.0"
            "version-code" = 2
            uuid = [Guid]::NewGuid().ToString()
            validity = [ordered]@{
                "not-before" = $now.AddMinutes(-5).ToUnixTimeSeconds()
                "not-after" = $now.AddDays(3649).ToUnixTimeSeconds()
            }
            type = "debug"
            "bundle-info" = [ordered]@{
                "developer-id" = "OpenHarmony"
                "development-certificate" = ($certs -join "")
                "bundle-name" = $script:BundleName
                apl = "normal"
                "app-feature" = "hos_normal_app"
            }
            acls = [ordered]@{ "allowed-acls" = @() }
            permissions = [ordered]@{ "restricted-permissions" = @() }
            "debug-info" = [ordered]@{
                "device-ids" = @($Udid)
                "device-id-type" = "udid"
            }
            issuer = "pki_internal"
        }
        $profileJson = $profile | ConvertTo-Json -Depth 12
        [System.IO.File]::WriteAllText($script:Paths.ProfileJson, $profileJson + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

        Write-Info "Signing the bundle- and UDID-bound debug profile with the SDK debug profile signer."
        Invoke-SignTool -Tools $Tools -Action "sign-profile" -Sensitive -Arguments @(
            "-mode", "localSign",
            "-keyAlias", $script:ProfileAlias,
            "-keyPwd", $script:SdkProfilePassword,
            "-profileCertFile", $Tools.ProfileChain,
            "-inFile", $script:Paths.ProfileJson,
            "-signAlg", "SHA256withECDSA",
            "-keystoreFile", $Tools.SdkStore,
            "-keystorePwd", $script:SdkStorePassword,
            "-outFile", $script:Paths.Profile,
            "-pwdInputMode", "0"
        )
    } catch {
        # Keep the verified project-private key and secret metadata so a transient
        # generation failure can resume without rotating or overwriting the key.
        foreach ($path in @($script:Paths.Profile, $script:Paths.ProfileJson, $script:Paths.AppCert)) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
        throw
    } finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Assert-ExistingMaterial -Tools $Tools -Udid $Udid -Secrets $Secrets | Out-Null
    Write-Info "Generated local OpenHarmony debug material for $script:BundleName. This is not a HarmonyOS release signature."
}

function Ensure-Material {
    param($Tools, [string]$Udid)
    if (-not (Test-Path -LiteralPath $script:SignRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $script:SignRoot | Out-Null
    }

    $secrets = Read-Secrets
    $materialFiles = @($script:Paths.Store, $script:Paths.AppCert, $script:Paths.ProfileJson, $script:Paths.Profile)
    $existingCount = (@($materialFiles | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })).Count
    if ($null -ne $secrets -and $existingCount -eq @($materialFiles).Count) {
        Assert-ExistingMaterial -Tools $Tools -Udid $Udid -Secrets $secrets | Out-Null
        return $secrets
    }
    if ($null -ne $secrets) {
        if ([string]$secrets.bundleName -ne $script:BundleName -or [string]$secrets.keyAlias -ne $script:KeyAlias) {
            throw "Partial local signing metadata does not belong to this project; refusing any overwrite."
        }
        if ($existingCount -eq 1 -and (Test-Path -LiteralPath $script:Paths.Store -PathType Leaf)) {
            New-LocalMaterial -Tools $Tools -Udid $Udid -Secrets $secrets
            return $secrets
        }
        throw "A partial local signing set contains unverified derived files. Refusing to overwrite material under $script:SignRoot."
    }
    if ($existingCount -ne 0) {
        throw "Signing material exists without its local secret metadata. Refusing to overwrite it under $script:SignRoot."
    }

    $secrets = New-Secrets
    try {
        New-LocalMaterial -Tools $Tools -Udid $Udid -Secrets $secrets
        return $secrets
    } catch {
        # If the key was not created, remove the otherwise useless new secret file.
        # If the key exists, preserve both so the next run can verify and resume.
        if (-not (Test-Path -LiteralPath $script:Paths.Store -PathType Leaf)) {
            Remove-Item -LiteralPath $script:Paths.Secrets -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Get-HapBundleName {
    param([string]$HapPath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($HapPath)
    try {
        $entry = $archive.GetEntry("module.json")
        if ($null -eq $entry) {
            throw "HAP does not contain module.json: $HapPath"
        }
        $reader = New-Object System.IO.StreamReader($entry.Open(), [Text.Encoding]::UTF8)
        try {
            $module = $reader.ReadToEnd() | ConvertFrom-Json
        } finally {
            $reader.Dispose()
        }
        return [string]$module.app.bundleName
    } finally {
        $archive.Dispose()
    }
}

function Resolve-UnsignedHap {
    $path = $UnsignedHap
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = "entry\build\default\outputs\default\entry-default-unsigned.hap"
    }
    $resolved = Resolve-ProjectPath $path
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "Unsigned HAP does not exist: $resolved"
    }
    if ([System.IO.Path]::GetFileName($resolved) -match '(?i)local-signed|signed\.hap$') {
        throw "Input must be an unsigned HAP, not a signed/local-signed output: $resolved"
    }
    $bundle = Get-HapBundleName -HapPath $resolved
    if ($bundle -ne $script:BundleName) {
        throw "Unsigned HAP bundleName '$bundle' does not match '$script:BundleName'."
    }
    return $resolved
}

function Resolve-SignedHap {
    param([string]$UnsignedPath)
    if (-not [string]::IsNullOrWhiteSpace($SignedHap)) {
        $resolved = Resolve-ProjectPath $SignedHap
    } else {
        $resolved = Join-Path (Split-Path -Parent $UnsignedPath) "entry-default-local-signed.hap"
    }
    if ([System.IO.Path]::GetExtension($resolved) -ne ".hap") {
        throw "Signed output must use the .hap extension: $resolved"
    }
    return [System.IO.Path]::GetFullPath($resolved)
}

function Verify-SignedHap {
    param($Tools, [string]$HapPath, [string]$Udid)
    if (-not (Test-Path -LiteralPath $HapPath -PathType Leaf)) {
        throw "Signed HAP does not exist: $HapPath"
    }
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("pelicanbike-verify-app-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    try {
        $outCert = Join-Path $tempDir "app-chain.cer"
        $outProfile = Join-Path $tempDir "profile.p7b"
        $outProof = Join-Path $tempDir "proof.json"
        Invoke-SignTool -Tools $Tools -Action "verify-app" -Arguments @(
            "-inFile", $HapPath,
            "-outCertChain", $outCert,
            "-outProfile", $outProfile,
            "-outProof", $outProof,
            "-inForm", "zip"
        ) | Out-Null
        $verified = Get-VerifiedProfile -Tools $Tools -ProfilePath $outProfile
        $content = $verified.content
        if ($content.type -ne "debug" -or $content.'bundle-info'.'bundle-name' -ne $script:BundleName) {
            throw "Embedded profile is not the expected local debug profile for '$script:BundleName'."
        }
        if (@($content.'debug-info'.'device-ids') -notcontains $Udid) {
            throw "Embedded profile is not authorized for live UDID '$Udid'."
        }
        $localCert = Get-Content -LiteralPath $script:Paths.AppCert -Raw
        $verifiedCert = Get-Content -LiteralPath $outCert -Raw
        $localLeaf = (Get-PemCertificates -Text $localCert)[0]
        $verifiedLeaf = (Get-PemCertificates -Text $verifiedCert)[0]
        if ((Normalize-Pem $localLeaf) -ne (Normalize-Pem $verifiedLeaf)) {
            throw "verify-app certificate does not match the project-local app certificate."
        }
        $bundle = Get-HapBundleName -HapPath $HapPath
        if ($bundle -ne $script:BundleName) {
            throw "Signed HAP bundleName '$bundle' does not match '$script:BundleName'."
        }
    } finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Info "verify-app passed for local debug HAP: $HapPath"
}

function Sign-Hap {
    param($Tools, [string]$Udid, $Secrets)
    Assert-ExistingMaterial -Tools $Tools -Udid $Udid -Secrets $Secrets | Out-Null
    $unsignedPath = Resolve-UnsignedHap
    $signedPath = Resolve-SignedHap -UnsignedPath $unsignedPath
    $parent = Split-Path -Parent $signedPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $signedPath -PathType Leaf) {
        Verify-SignedHap -Tools $Tools -HapPath $signedPath -Udid $Udid
        $unsignedHash = (Get-FileHash -LiteralPath $unsignedPath -Algorithm SHA256).Hash
        $marker = "$signedPath.source.sha256"
        if (Test-Path -LiteralPath $marker -PathType Leaf) {
            $recorded = (Get-Content -LiteralPath $marker -Raw).Trim()
            if ($recorded -eq $unsignedHash) {
                Write-Info "Existing local-signed HAP matches this unsigned input and will be reused."
                return $signedPath
            }
        }
        Write-Info "Unsigned HAP changed; replacing only the derived local-signed output."
        Remove-Item -LiteralPath $signedPath -Force
    }

    $tempOutput = "$signedPath.tmp-$([Guid]::NewGuid().ToString('N')).hap"
    try {
        Write-Info "Signing local debug HAP. This output is never a release artifact."
        Invoke-SignTool -Tools $Tools -Action "sign-app" -Sensitive -Arguments @(
            "-mode", "localSign",
            "-keyAlias", $script:KeyAlias,
            "-keyPwd", [string]$Secrets.keyPassword,
            "-appCertFile", $script:Paths.AppCert,
            "-profileFile", $script:Paths.Profile,
            "-profileSigned", "1",
            "-inForm", "zip",
            "-inFile", $unsignedPath,
            "-signAlg", "SHA256withECDSA",
            "-keystoreFile", $script:Paths.Store,
            "-keystorePwd", [string]$Secrets.storePassword,
            "-outFile", $tempOutput,
            "-compatibleVersion", $script:CompatibleApi,
            "-signCode", "1",
            "-pwdInputMode", "0"
        )
        Verify-SignedHap -Tools $Tools -HapPath $tempOutput -Udid $Udid
        Move-Item -LiteralPath $tempOutput -Destination $signedPath -Force
        $unsignedHash = (Get-FileHash -LiteralPath $unsignedPath -Algorithm SHA256).Hash
        [System.IO.File]::WriteAllText("$signedPath.source.sha256", $unsignedHash + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    } finally {
        Remove-Item -LiteralPath $tempOutput -Force -ErrorAction SilentlyContinue
    }
    Write-Info "Local-signed HAP: $signedPath"
    return $signedPath
}

function Install-Hap {
    param($Tools, [string]$HapPath, [string]$Udid)
    Verify-SignedHap -Tools $Tools -HapPath $HapPath -Udid $Udid
    Write-WarnMessage "Installing a local OpenHarmony debug HAP on '$Serial'; this is not a HarmonyOS release package."
    $process = New-Object Diagnostics.Process
    try {
        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName = $Tools.Hdc
        $startInfo.Arguments = (@("-t", $Serial, "install", "-r", "-w", [string]($TimeoutSec * 1000), $HapPath) | ForEach-Object {
            '"' + ($_.Replace('"', '\"')) + '"'
        }) -join ' '
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw "Failed to start HDC install."
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSec * 1000)) {
            try { $process.Kill() } catch {}
            throw "HDC install timed out after $TimeoutSec seconds."
        }
        $process.WaitForExit()
        $text = (($stdoutTask.GetAwaiter().GetResult(), $stderrTask.GetAwaiter().GetResult()) | Where-Object { $_ }) -join [Environment]::NewLine
        if ($text) { Write-Host $text.TrimEnd() }
        if ($process.ExitCode -ne 0 -or $text -notmatch '(?i)install bundle successfully') {
            throw "Local debug HAP installation failed. The script never uninstalls the existing app or treats this artifact as release."
        }
    } finally {
        $process.Dispose()
    }
    Write-Info "Local debug install succeeded on $Serial."
}

function Show-Help {
    @"
PelicanBike project-local OpenHarmony debug signer

Usage:
  .\tools\device\local-debug-sign.ps1 prepare [-Serial 127.0.0.1:10178]
  .\tools\device\local-debug-sign.ps1 verify  [-Serial 127.0.0.1:10178]
  .\tools\device\local-debug-sign.ps1 sign    [-UnsignedHap <path>] [-SignedHap <path>]
  .\tools\device\local-debug-sign.ps1 install [-SignedHap <path>] [-Serial <target>]
  .\tools\device\local-debug-sign.ps1 all     [-UnsignedHap <path>] [-Serial <target>]

Safety:
  - Reads the UDID live from the selected HDC target (default Pura90 127.0.0.1:10178).
  - Generates a project-private ECC key for exactly $script:BundleName.
  - Uses the SDK OpenHarmony CA only for local simulator debug.
  - This is NOT a HarmonyOS publishing/release signature.
  - Secrets stay in entry\sign\debug\.local-signing.json with restricted ACLs and are never printed.
  - Existing material is verified for bundle/certificate/device/validity and reused; it is never overwritten.
  - No build-profile or source file is modified, and no other project's signing material is read.
"@ | Write-Host
}

try {
    if ($Command -eq "help") {
        Show-Help
        exit 0
    }
    Assert-ProjectIdentity
    $tools = Get-Toolchain
    $udid = Get-LiveDeviceUdid -Tools $tools

    switch ($Command) {
        "prepare" {
            Ensure-Material -Tools $tools -Udid $udid | Out-Null
        }
        "verify" {
            $secrets = Read-Secrets
            if ($null -eq $secrets) { throw "Local signing secrets do not exist. Run prepare first." }
            Assert-ExistingMaterial -Tools $tools -Udid $udid -Secrets $secrets | Out-Null
        }
        "sign" {
            $secrets = Ensure-Material -Tools $tools -Udid $udid
            Sign-Hap -Tools $tools -Udid $udid -Secrets $secrets | Out-Null
        }
        "install" {
            $secrets = Ensure-Material -Tools $tools -Udid $udid
            $unsignedPath = Resolve-UnsignedHap
            $signedPath = Resolve-SignedHap -UnsignedPath $unsignedPath
            if (-not (Test-Path -LiteralPath $signedPath -PathType Leaf)) {
                throw "Local-signed HAP does not exist. Run sign or all first: $signedPath"
            }
            Assert-ExistingMaterial -Tools $tools -Udid $udid -Secrets $secrets | Out-Null
            Install-Hap -Tools $tools -HapPath $signedPath -Udid $udid
        }
        "all" {
            $secrets = Ensure-Material -Tools $tools -Udid $udid
            $signedPath = Sign-Hap -Tools $tools -Udid $udid -Secrets $secrets
            Install-Hap -Tools $tools -HapPath $signedPath -Udid $udid
        }
    }
} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

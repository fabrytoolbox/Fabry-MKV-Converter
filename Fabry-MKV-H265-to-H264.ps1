# Fabry-MKV-H265-to-H264.ps1 - v1.0
# Converte MKV da H.265 (HEVC) a H.264, mantenendo il contenitore MKV
# Auto-download FFmpeg, log su file, gestione errori, fallback CPU

param(
    [string]$InputPath,
    [string]$OutputPath,
    [switch]$Batch,
    [switch]$Interactive,
    [switch]$Deinterlace,
    [switch]$KeepTemp
)

# ============================================
# AUTO-FFMPEG
# ============================================
$script:workDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$ffmpegPath = Join-Path $script:workDir "ffmpeg.exe"
$ffprobePath = Join-Path $script:workDir "ffprobe.exe"

function Initialize-FFmpeg {
    if ((Test-Path $ffmpegPath) -and (Test-Path $ffprobePath)) { return $true }

    $resp = [System.Windows.Forms.MessageBox]::Show("FFmpeg non trovato. Vuoi scaricarlo automaticamente nella cartella dello script?", "FFmpeg Missing", [System.Windows.Forms.MessageBoxButtons]::YesNo)
    if ($resp -eq "No") { return $false }

    $zipPath = Join-Path $env:TEMP "ffmpeg_dl.zip"
    $extractPath = Join-Path $env:TEMP "ffmpeg_temp"
    $url = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"

    try {
        Write-Host "Download FFmpeg in corso..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
        Write-Host "Estrazione..." -ForegroundColor Cyan
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        Get-ChildItem -Path $extractPath -Include "ffmpeg.exe", "ffprobe.exe" -Recurse | ForEach-Object {
            Move-Item $_.FullName $script:workDir -Force
        }
        Remove-Item $zipPath -Force
        Remove-Item $extractPath -Recurse -Force
        Write-Host "[OK] FFmpeg scaricato." -ForegroundColor Green
        return $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Errore download: $($_.Exception.Message)", "Errore", "OK", "Error")
        return $false
    }
}

Add-Type -AssemblyName System.Windows.Forms
if (-not (Initialize-FFmpeg)) { exit }

# ============================================
# LOGGING
# ============================================
$script:logFile = $null

function Start-Log {
    param([string]$Folder)
    if (-not (Test-Path $Folder)) { New-Item -ItemType Directory -Path $Folder -Force | Out-Null }
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:logFile = Join-Path $Folder "mkv_h265_to_h264_$timestamp.log"
    @(
        "============================================================",
        " MKV H.265 -> H.264 - LOG",
        "============================================================",
        "Data inizio: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "============================================================",
        ""
    ) | Set-Content -Path $script:logFile -Encoding UTF8
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    if (-not $script:logFile) { return }
    $line = "[$(Get-Date -Format 'HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $script:logFile -Value $line -Encoding UTF8
}

# ============================================
# UTILITA
# ============================================
function Write-Step { param([string]$Message, [string]$Color = "Cyan") Write-Host ""; Write-Host ("=" * 60) -ForegroundColor $Color; Write-Host "  $Message" -ForegroundColor $Color; Write-Host ("=" * 60) -ForegroundColor $Color }
function Write-Success { param([string]$Message) Write-Host "  [OK] $Message" -ForegroundColor Green }
function Write-ErrorMsg { param([string]$Message) Write-Host "  [X] $Message" -ForegroundColor Red }
function Write-Info { param([string]$Message) Write-Host "  [i] $Message" -ForegroundColor Yellow }
function Write-Warning { param([string]$Message) Write-Host "  [!] $Message" -ForegroundColor Magenta }

function Format-FileSize { param([long]$Size) if ($Size -gt 1GB) { return "{0:N2} GB" -f ($Size / 1GB) } elseif ($Size -gt 1MB) { return "{0:N2} MB" -f ($Size / 1MB) } else { return "$Size bytes" } }

function Test-NVENC {
    try {
        $result = & $ffmpegPath -hide_banner -encoders 2>&1 | Select-String "h264_nvenc"
        return ($result -ne $null)
    } catch { return $false }
}

# ============================================
# CONVERSIONE SINGOLO FILE
# ============================================
function Convert-Single {
    param(
        [string]$InputFile,
        [string]$OutputFolder,
        [switch]$Deinterlace,
        [switch]$AddSuffix
    )

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
    if ($AddSuffix) { $outputName = "${baseName}_h264.mkv" } else { $outputName = "${baseName}.mkv" }
    $OutputFile = Join-Path $OutputFolder $outputName

    if (-not (Test-Path $OutputFolder)) { New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null }

    Write-Info "Input:  $(Split-Path $InputFile -Leaf)"
    Write-Info "Output: $(Split-Path $OutputFile -Leaf)"
    Write-Log "Input: $InputFile" "INFO"
    Write-Log "Output: $OutputFile" "INFO"

    $useNVENC = Test-NVENC
    if (-not $useNVENC) { Write-Warning "NVENC non disponibile - uso CPU (libx264)" }

    # Costruisci filtro video
    $vfFilters = @()
    if ($useNVENC -and $Deinterlace) {
        $vfFilters += "hwdownload,format=nv12"
    }
    if ($Deinterlace) { $vfFilters += "yadif" }
    $vfString = if ($vfFilters.Count -gt 0) { $vfFilters -join "," } else { $null }

    # Costruisci comando FFmpeg
    $ffmpegArgs = @("-y")
    if ($useNVENC) { $ffmpegArgs += @("-hwaccel", "cuda", "-hwaccel_output_format", "cuda") }
    $ffmpegArgs += @("-i", $InputFile)

    if ($vfString) { $ffmpegArgs += @("-vf", $vfString) }

    # Encoder (DOPO l'input)
    if ($useNVENC) {
        $maxRate = "20M"
        $bufSize = "40M"
        $ffmpegArgs += @("-c:v", "h264_nvenc", "-preset", "p5", "-rc", "vbr", "-cq", "19", "-spatial-aq", "1", "-maxrate", $maxRate, "-bufsize", $bufSize)
    } else {
        $ffmpegArgs += @("-c:v", "libx264", "-preset", "medium", "-crf", "19")
    }

    # Audio e sottotitoli: copia
    $ffmpegArgs += @("-c:a", "copy", "-c:s", "copy")

    $ffmpegArgs += @("-map", "0", "-movflags", "+faststart", $OutputFile)

    Write-Host ""
    Write-Host "  Avvio conversione..." -ForegroundColor Yellow
    Write-Host "  Comando: $ffmpegPath $($ffmpegArgs -join ' ')" -ForegroundColor DarkGray
    Write-Log "Comando: $ffmpegPath $($ffmpegArgs -join ' ')" "INFO"

    $startTime = Get-Date
    try {
        $output = & $ffmpegPath @ffmpegArgs 2>&1
        $exitCode = $LASTEXITCODE
    } catch {
        Write-ErrorMsg "Errore: $($_.Exception.Message)"
        Write-Log "Errore: $($_.Exception.Message)" "ERROR"
        return $false
    }
    $elapsed = ($(Get-Date) - $startTime).TotalSeconds

    if ($exitCode -eq 0) {
        Write-Success "Conversione completata in $([math]::Round($elapsed, 1)) secondi"
        Write-Log "Completato in $([math]::Round($elapsed, 1))s" "OK"
        if (Test-Path $OutputFile) {
            $inputSize = (Get-Item $InputFile).Length
            $outputSize = (Get-Item $OutputFile).Length
            $ratio = [math]::Round(($outputSize / $inputSize) * 100, 1)
            Write-Host "  Input:  $(Format-FileSize $inputSize)" -ForegroundColor White
            Write-Host "  Output: $(Format-FileSize $outputSize) ($ratio%)" -ForegroundColor White
        }
        return $true
    } else {
        Write-ErrorMsg "Errore durante la conversione (codice: $exitCode)"
        if ($output) {
            Write-Host "  Output FFmpeg:" -ForegroundColor DarkGray
            $output | Select-Object -Last 20 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            Write-Log "Errore (exit $exitCode): $output" "ERROR"
        }
        return $false
    }
}

# ============================================
# CONVERSIONE BATCH
# ============================================
function Convert-Batch {
    param(
        [string]$InputFolder,
        [string]$OutputFolder,
        [switch]$Deinterlace,
        [switch]$AddSuffix
    )

    $mkvFiles = @(Get-ChildItem -Path $InputFolder -Filter "*.mkv" -File)
    $total = $mkvFiles.Count
    $current = 0
    $successCount = 0
    $failCount = 0
    $batchStart = Get-Date

    Write-Info "Avvio conversione batch di $total file..."
    Write-Log "Batch avviato: $total file in $InputFolder" "INFO"

    foreach ($file in $mkvFiles) {
        $current++
        Write-Step "FILE $current di ${total}: $($file.Name)" "Cyan"
        $ok = Convert-Single -InputFile $file.FullName -OutputFolder $OutputFolder -Deinterlace:$Deinterlace -AddSuffix:$AddSuffix
        if ($ok) { $successCount++ } else { $failCount++ }
    }

    $batchElapsed = ($(Get-Date) - $batchStart).TotalMinutes
    Write-Step "CONVERSIONE BATCH COMPLETATA" "Green"
    Write-Host "  Totale:       ${total} file" -ForegroundColor White
    Write-Host "  Successi:     $successCount" -ForegroundColor Green
    if ($failCount -gt 0) { Write-Host "  Fallimenti:   $failCount" -ForegroundColor Red }
    Write-Host "  Tempo totale: $([math]::Round($batchElapsed, 1)) min" -ForegroundColor White
    Write-Log "Batch completato: $successCount successi, $failCount fallimenti, $([math]::Round($batchElapsed,1)) min" "INFO"
}

# ============================================
# MODALITA INTERATTIVA
# ============================================
function Start-InteractiveMode {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Magenta
    Write-Host "      FABRY MKV H.265 -> H.264 CONVERTER v1.0               " -ForegroundColor Magenta
    Write-Host "============================================================" -ForegroundColor Magenta

    Write-Info "Verifica NVENC..."
    if (Test-NVENC) { Write-Success "NVENC disponibile (GPU)" } else { Write-Warning "NVENC non disponibile - uso CPU" }

    # STEP 1: Selezione input
    Write-Step "STEP 1: Selezione input" "Cyan"
    Write-Host "  1. Converti un singolo file MKV"
    Write-Host "  2. Converti tutti gli MKV in una cartella (BATCH)"
    Write-Host ""
    do {
        $modeChoice = Read-Host "Scegli (1-2, default 1)"
        if ([string]::IsNullOrWhiteSpace($modeChoice)) { $modeChoice = "1" }
        if ($modeChoice -notmatch '^[1-2]$') { Write-Warning "Inserisci 1 o 2"; $modeChoice = $null }
    } while (-not $modeChoice)

    if ($modeChoice -eq "2") {
        $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderBrowser.Description = "Seleziona la cartella con i file MKV"
        if ($folderBrowser.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { Write-ErrorMsg "Nessuna cartella selezionata."; return }
        $InputPath = $folderBrowser.SelectedPath
        $BatchMode = $true
        $mkvFiles = @(Get-ChildItem -Path $InputPath -Filter "*.mkv" -File)
        if ($mkvFiles.Count -eq 0) { Write-ErrorMsg "Nessun file MKV trovato."; return }
        Write-Success "Trovati $($mkvFiles.Count) file MKV"
    } else {
        $fileBrowser = New-Object System.Windows.Forms.OpenFileDialog
        $fileBrowser.Filter = "File MKV (*.mkv)|*.mkv|Tutti i file (*.*)|*.*"
        if ($fileBrowser.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { Write-ErrorMsg "Nessun file selezionato."; return }
        $InputPath = $fileBrowser.FileName
        $BatchMode = $false
    }

    # STEP 2: Deinterlace
    Write-Step "STEP 2: Deinterlace" "Cyan"
    Write-Host "  Applicare deinterlace? (S/N, default N)"
    $deintChoice = Read-Host "Scegli"
    if ($deintChoice -eq 'S' -or $deintChoice -eq 's') { $Deinterlace = $true; Write-Success "Deinterlace attivato" } else { Write-Info "Deinterlace disattivato" }

    # STEP 3: Output
    Write-Step "STEP 3: Destinazione" "Cyan"
    if ($BatchMode) {
        Write-Host "  1. Sottocartella 'Convertiti_H264' (consigliato)"
        Write-Host "  2. Stessa cartella (suffisso _h264)"
        Write-Host ""
        $outputChoice = Read-Host "Scegli (1-2, default 1)"
        if ([string]::IsNullOrWhiteSpace($outputChoice)) { $outputChoice = "1" }
        if ($outputChoice -eq "1") { $OutputPath = Join-Path $InputPath "Convertiti_H264"; $addSuffix = $false } else { $OutputPath = $InputPath; $addSuffix = $true }
    } else {
        $OutputPath = Split-Path $InputPath -Parent
        $addSuffix = $true
    }
    Write-Success "Output: $OutputPath"

    # Riepilogo
    Write-Step "RIEPILOGO FINALE" "Yellow"
    Write-Host "  Modalita:   $(if ($BatchMode) { "BATCH ($($mkvFiles.Count) file)" } else { "Singolo file" })"
    Write-Host "  Output:     $OutputPath"
    Write-Host "  Deinterlace: $(if ($Deinterlace) { "SI" } else { "NO" })"
    Write-Host "  Formato:    MKV (H.265 -> H.264)"
    Write-Host ""

    $confirm = Read-Host "Procedere? (S/N)"
    if ($confirm -ne 'S' -and $confirm -ne 's') { Write-ErrorMsg "Annullato."; return }

    Start-Log -Folder $OutputPath

    if ($BatchMode) {
        Convert-Batch -InputFolder $InputPath -OutputFolder $OutputPath -Deinterlace:$Deinterlace -AddSuffix:$addSuffix
    } else {
        Convert-Single -InputFile $InputPath -OutputFolder $OutputPath -Deinterlace:$Deinterlace -AddSuffix:$addSuffix
    }
}

# ============================================
# ESECUZIONE
# ============================================
if (-not $InputPath -and -not $PSBoundParameters.ContainsKey('Interactive')) { $Interactive = $true }

if ($Interactive) {
    Start-InteractiveMode
} elseif ($Batch -and $InputPath) {
    if (-not $OutputPath) { $OutputPath = Join-Path $InputPath "Convertiti_H264" }
    Start-Log -Folder $OutputPath
    Convert-Batch -InputFolder $InputPath -OutputFolder $OutputPath -Deinterlace:$Deinterlace
} elseif ($InputPath) {
    if (-not $OutputPath) { $OutputPath = Split-Path $InputPath -Parent }
    Start-Log -Folder $OutputPath
    Convert-Single -InputFile $InputPath -OutputFolder $OutputPath -Deinterlace:$Deinterlace -AddSuffix
} else {
    Write-Host "Fabry MKV H.265 -> H.264 Converter v1.0" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "USO:" -ForegroundColor Yellow
    Write-Host "  Modalita interattiva: .\Fabry-MKV-H265-to-H264.ps1" -ForegroundColor Gray
    Write-Host "  Batch:                .\Fabry-MKV-H265-to-H264.ps1 -InputPath C:\Video -Batch" -ForegroundColor Gray
}

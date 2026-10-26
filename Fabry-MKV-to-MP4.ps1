# Fabry-MKV-to-MP4.ps1 - v1.2
# Converte MKV in MP4 H.264 con NVENC (GPU) o libx264 (CPU)
# Auto-download FFmpeg, log su file, gestione errori
# FIX v1.2: aggiunto maxrate/bufsize per evitare file enormi

param(
    [string]$InputPath,
    [string]$OutputPath,
    [switch]$Batch,
    [switch]$Interactive,
    [ValidateSet("light", "medium", "strong", "custom", "none")]
    [string]$Sharpening = "light",
    [ValidateSet("high", "balanced", "fast", "custom")]
    [string]$QualityPreset = "balanced",
    [int]$CustomCQ = 0,
    [ValidateSet("aac", "copy", "eac3")]
    [string]$AudioCodec = "aac",
    [int]$AudioBitrate = 192,
    [ValidateSet("keep", "burn", "none")]
    [string]$Subtitles = "keep",
    [switch]$KeepTemp,
    [switch]$Preview,
    [switch]$Deinterlace,
    [ValidateSet("none", "bilinear", "bicubic", "lanczos")]
    [string]$ResizeFilter = "none",
    [string]$ResizeResolution = ""
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
    $script:logFile = Join-Path $Folder "mkv_to_mp4_$timestamp.log"
    @(
        "============================================================",
        " MKV TO MP4 - LOG",
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
# PROFILI
# ============================================
$QualityProfiles = @{
    "high"     = @{ CQ = 19; Preset = "p5"; Description = "Alta qualita (file piu grandi)" }
    "balanced" = @{ CQ = 22; Preset = "p5"; Description = "Bilanciato (consigliato)" }
    "fast"     = @{ CQ = 25; Preset = "p4"; Description = "Veloce (file piu piccoli)" }
}

$SharpeningProfiles = @{
    "light"  = @{ Strength = "0.3"; Description = "Leggero - Naturale" }
    "medium" = @{ Strength = "0.5"; Description = "Medio - Dettagli visibili" }
    "strong" = @{ Strength = "0.8"; Description = "Forte - Video morbidi" }
    "custom" = @{ Strength = "0.4"; Description = "Personalizzato" }
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
function Format-Duration { param([double]$Seconds) $ts = [TimeSpan]::FromSeconds($Seconds); if ($ts.Hours -gt 0) { return "{0}:{1:D2}:{2:D2}" -f $ts.Hours, $ts.Minutes, $ts.Seconds } else { return "{0}:{1:D2}" -f $ts.Minutes, $ts.Seconds } }

function Get-VideoInfo {
    param([string]$FilePath)
    try {
        $info = & $ffprobePath -v quiet -print_format json -show_format -show_streams "$FilePath" 2>&1 | ConvertFrom-Json
        $videoStream = $info.streams | Where-Object { $_.codec_type -eq 'video' } | Select-Object -First 1
        $audioStreams = @($info.streams | Where-Object { $_.codec_type -eq 'audio' })
        $subtitleStreams = @($info.streams | Where-Object { $_.codec_type -eq 'subtitle' })
        return @{
            VideoCodec = $videoStream.codec_name
            Resolution = "$($videoStream.width)x$($videoStream.height)"
            Width = [int]$videoStream.width
            Height = [int]$videoStream.height
            FrameRate = $videoStream.r_frame_rate
            Duration = [double]$info.format.duration
            DurationFormatted = Format-Duration -Seconds $info.format.duration
            FileSize = [long]$info.format.size
            BitRate = [math]::Round($info.format.bit_rate / 1000000, 1)
            AudioTracks = $audioStreams.Count
            SubtitleTracks = $subtitleStreams.Count
            IsH265 = ($videoStream.codec_name -match 'hevc|h265')
            IsH264 = ($videoStream.codec_name -match 'h264|avc')
            IsInterlaced = ($videoStream.field_order -ne 'progressive')
        }
    } catch {
        Write-Warning "Impossibile analizzare: $FilePath - $_"
        return $null
    }
}

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
        [string]$Sharpening = "light",
        [string]$QualityPreset = "balanced",
        [int]$CustomCQ = 0,
        [string]$AudioCodec = "aac",
        [int]$AudioBitrate = 192,
        [string]$Subtitles = "keep",
        [switch]$Deinterlace,
        [switch]$Preview,
        [switch]$AddSuffix
    )

    if ($QualityPreset -eq "custom") { $cq = $CustomCQ; $preset = "p5" } else { $cq = $QualityProfiles[$QualityPreset].CQ; $preset = $QualityProfiles[$QualityPreset].Preset }

    $sharpenValue = if ($Sharpening -ne "none") { $SharpeningProfiles[$Sharpening].Strength } else { $null }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
    if ($AddSuffix) { $outputName = "${baseName}_H264.mp4" } else { $outputName = "${baseName}.mp4" }
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
    if ($useNVENC -and ($sharpenValue -or $Deinterlace)) {
        $vfFilters += "hwdownload,format=nv12"
    }
    if ($sharpenValue) { $vfFilters += "unsharp=5:5:$sharpenValue" }
    if ($Deinterlace) { $vfFilters += "yadif" }
    $vfString = if ($vfFilters.Count -gt 0) { $vfFilters -join "," } else { $null }

    # Costruisci comando FFmpeg (ordine corretto!)
    $ffmpegArgs = @("-y")
    if ($useNVENC) { $ffmpegArgs += @("-hwaccel", "cuda", "-hwaccel_output_format", "cuda") }
    $ffmpegArgs += @("-i", $InputFile)

    if ($vfString) { $ffmpegArgs += @("-vf", $vfString) }

    # Encoder (DOPO l'input!)
    if ($useNVENC) {
        # Priorità: QUALITÀ (per uso in VisoMaster, editing, ecc.)
        # CQ 21 = alta qualità, maxrate alto = NVENC libero di usare bitrate
        $maxRate = "20M"   # Limite alto per non strozzare la qualità
        $bufSize = "40M"   # Buffer abbondante
        $ffmpegArgs += @("-c:v", "h264_nvenc", "-preset", $preset, "-rc", "vbr", "-cq", $cq, "-spatial-aq", "1", "-maxrate", $maxRate, "-bufsize", $bufSize)
    } else {
        $ffmpegArgs += @("-c:v", "libx264", "-preset", "medium", "-crf", $cq)
    }

    if ($AudioCodec -eq "copy") { $ffmpegArgs += @("-c:a", "copy") }
    elseif ($AudioCodec -eq "aac") { $ffmpegArgs += @("-c:a", "aac", "-b:a", "${AudioBitrate}k") }
    else { $ffmpegArgs += @("-c:a", $AudioCodec, "-b:a", "${AudioBitrate}k") }

    switch ($Subtitles) {
        "keep" { $ffmpegArgs += @("-c:s", "mov_text") }
        "burn" { $ffmpegArgs += @("-vf", "subtitles=$InputFile") }
        "none" { $ffmpegArgs += @("-sn") }
    }

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
        [string]$Sharpening = "light",
        [string]$QualityPreset = "balanced",
        [int]$CustomCQ = 0,
        [string]$AudioCodec = "aac",
        [int]$AudioBitrate = 192,
        [string]$Subtitles = "keep",
        [switch]$Deinterlace,
        [switch]$Preview,
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
        $ok = Convert-Single -InputFile $file.FullName -OutputFolder $OutputFolder -Sharpening $Sharpening -QualityPreset $QualityPreset -CustomCQ $CustomCQ -AudioCodec $AudioCodec -AudioBitrate $AudioBitrate -Subtitles $Subtitles -Deinterlace:$Deinterlace -Preview:$false -AddSuffix:$AddSuffix
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
    Write-Host "      FABRY MKV TO MP4 CONVERTER v1.2                       " -ForegroundColor Magenta
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

    # STEP 2: Analisi file
    Write-Step "STEP 2: Analisi file sorgente" "Cyan"
    if ($BatchMode) { $info = Get-VideoInfo -FilePath $mkvFiles[0].FullName } else { $info = Get-VideoInfo -FilePath $InputPath }

    if ($info) {
        Write-Host ""
        Write-Host "  File:      $(Split-Path $InputPath -Leaf)" -ForegroundColor White
        Write-Host "  Codec:     $($info.VideoCodec.ToUpper()) -> H.264" -ForegroundColor White
        Write-Host "  Risoluz.:  $($info.Resolution)" -ForegroundColor White
        Write-Host "  FrameRate: $($info.FrameRate)" -ForegroundColor White
        Write-Host "  Durata:    $($info.DurationFormatted)" -ForegroundColor White
        Write-Host "  Dimens.:   $(Format-FileSize $info.FileSize)" -ForegroundColor White
        Write-Host "  Audio:     $($info.AudioTracks) tracce" -ForegroundColor White
        Write-Host "  Sub:       $($info.SubtitleTracks) tracce" -ForegroundColor White
    }

    # STEP 3: Qualita
    Write-Step "STEP 3: Qualita video output" "Cyan"
    Write-Host "  1. Alta qualita  - CQ 17"
    Write-Host "  2. Bilanciato    - CQ 21 (consigliato)"
    Write-Host "  3. Veloce        - CQ 25"
    Write-Host "  4. Personalizzato"
    Write-Host ""
    do {
        $qualityChoice = Read-Host "Scegli (1-4, default 2)"
        if ([string]::IsNullOrWhiteSpace($qualityChoice)) { $qualityChoice = "2" }
        if ($qualityChoice -notmatch '^[1-4]$') { Write-Warning "1-4"; $qualityChoice = $null }
    } while (-not $qualityChoice)

    switch ($qualityChoice) {
        "1" { $QualityPreset = "high"; Write-Success "Alta qualita" }
        "2" { $QualityPreset = "balanced"; Write-Success "Bilanciato" }
        "3" { $QualityPreset = "fast"; Write-Success "Veloce" }
        "4" { 
            $QualityPreset = "custom"
            do {
                $CustomCQ = Read-Host "CQ (1-51, default 21)"
                if ([string]::IsNullOrWhiteSpace($CustomCQ)) { $CustomCQ = 21 }
                if ($CustomCQ -notmatch '^\d+$' -or [int]$CustomCQ -lt 1 -or [int]$CustomCQ -gt 51) { Write-Warning "1-51"; $CustomCQ = $null }
            } while (-not $CustomCQ)
            Write-Success "CQ personalizzato: $CustomCQ"
        }
    }

    # STEP 4: Audio
    Write-Step "STEP 4: Audio" "Cyan"
    Write-Host "  1. AAC Stereo (192kbps) - consigliato"
    Write-Host "  2. AAC Multicanal (384kbps)"
    Write-Host "  3. Copia originale"
    Write-Host "  4. E-AC3 (384kbps)"
    Write-Host ""
    do {
        $audioChoice = Read-Host "Scegli (1-4, default 1)"
        if ([string]::IsNullOrWhiteSpace($audioChoice)) { $audioChoice = "1" }
        if ($audioChoice -notmatch '^[1-4]$') { Write-Warning "1-4"; $audioChoice = $null }
    } while (-not $audioChoice)

    switch ($audioChoice) {
        "1" { $AudioCodec = "aac"; $AudioBitrate = 192 }
        "2" { $AudioCodec = "aac"; $AudioBitrate = 384 }
        "3" { $AudioCodec = "copy" }
        "4" { $AudioCodec = "eac3"; $AudioBitrate = 384 }
    }

    # STEP 5: Sottotitoli
    Write-Step "STEP 5: Sottotitoli" "Cyan"
    if ($info.SubtitleTracks -gt 0) {
        Write-Host "  1. Mantieni (embed MP4)"
        Write-Host "  2. Masterizza (burn-in)"
        Write-Host "  3. Rimuovi"
        Write-Host ""
        do {
            $subChoice = Read-Host "Scegli (1-3, default 1)"
            if ([string]::IsNullOrWhiteSpace($subChoice)) { $subChoice = "1" }
            if ($subChoice -notmatch '^[1-3]$') { Write-Warning "1-3"; $subChoice = $null }
        } while (-not $subChoice)
        switch ($subChoice) {
            "1" { $Subtitles = "keep" }
            "2" { $Subtitles = "burn" }
            "3" { $Subtitles = "none" }
        }
    } else {
        Write-Info "Nessun sottotitolo rilevato"
        $Subtitles = "none"
    }

    # STEP 6: Filtri
    Write-Step "STEP 6: Sharpening e filtri" "Cyan"
    Write-Host "  1. Leggero (0.3)"
    Write-Host "  2. Medio (0.5)"
    Write-Host "  3. Forte (0.8)"
    Write-Host "  4. Custom"
    Write-Host "  5. Nessuno"
    Write-Host ""
    do {
        $sharpenChoice = Read-Host "Scegli (1-5, default 1)"
        if ([string]::IsNullOrWhiteSpace($sharpenChoice)) { $sharpenChoice = "1" }
        if ($sharpenChoice -notmatch '^[1-5]$') { Write-Warning "1-5"; $sharpenChoice = $null }
    } while (-not $sharpenChoice)

    switch ($sharpenChoice) {
        "1" { $Sharpening = "light" }
        "2" { $Sharpening = "medium" }
        "3" { $Sharpening = "strong" }
        "4" { 
            $Sharpening = "custom"
            $customStr = Read-Host "Strength (0.0-2.0, default 0.4)"
            if (-not $customStr) { $customStr = "0.4" }
            $SharpeningProfiles.custom.Strength = $customStr
        }
        "5" { $Sharpening = "none" }
    }
    Write-Success "Sharpening: $Sharpening"

    if ($info.IsInterlaced) {
        Write-Host ""
        Write-Warning "Video interlacciato rilevato!"
        $deintChoice = Read-Host "Applicare deinterlace? (S/N, default S)"
        if ($deintChoice -ne 'N' -and $deintChoice -ne 'n') { $Deinterlace = $true; Write-Success "Deinterlace attivato" }
    }

    # STEP 7: Output
    Write-Step "STEP 7: Destinazione" "Cyan"
    if ($BatchMode) {
        Write-Host "  1. Sottocartella 'Convertiti_MP4' (consigliato)"
        Write-Host "  2. Stessa cartella (suffisso _H264)"
        Write-Host ""
        $outputChoice = Read-Host "Scegli (1-2, default 1)"
        if ([string]::IsNullOrWhiteSpace($outputChoice)) { $outputChoice = "1" }
        if ($outputChoice -eq "1") { $OutputPath = Join-Path $InputPath "Convertiti_MP4"; $addSuffix = $false } else { $OutputPath = $InputPath; $addSuffix = $true }
    } else {
        $OutputPath = Split-Path $InputPath -Parent
        $addSuffix = $true
    }
    Write-Success "Output: $OutputPath"

    # Riepilogo
    $qualityInfo = if ($QualityPreset -eq "custom") { "CQ $CustomCQ" } else { $QualityProfiles[$QualityPreset].Description }
    $sharpenInfo = if ($Sharpening -ne "none") { $SharpeningProfiles[$Sharpening].Description } else { "Disabilitato" }

    Write-Step "RIEPILOGO FINALE" "Yellow"
    Write-Host "  Modalita:   $(if ($BatchMode) { "BATCH ($($mkvFiles.Count) file)" } else { "Singolo file" })"
    Write-Host "  Output:     $OutputPath"
    Write-Host "  Qualita:    $qualityInfo"
    Write-Host "  Audio:      $AudioCodec ($AudioBitrate kbps)"
    Write-Host "  Sharpening: $sharpenInfo"
    Write-Host ""

    $confirm = Read-Host "Procedere? (S/N)"
    if ($confirm -ne 'S' -and $confirm -ne 's') { Write-ErrorMsg "Annullato."; return }

    Start-Log -Folder $OutputPath

    if ($BatchMode) {
        Convert-Batch -InputFolder $InputPath -OutputFolder $OutputPath -Sharpening $Sharpening -QualityPreset $QualityPreset -CustomCQ $CustomCQ -AudioCodec $AudioCodec -AudioBitrate $AudioBitrate -Subtitles $Subtitles -Deinterlace:$Deinterlace -Preview:$Preview -AddSuffix:$addSuffix
    } else {
        Convert-Single -InputFile $InputPath -OutputFolder $OutputPath -Sharpening $Sharpening -QualityPreset $QualityPreset -CustomCQ $CustomCQ -AudioCodec $AudioCodec -AudioBitrate $AudioBitrate -Subtitles $Subtitles -Deinterlace:$Deinterlace -Preview:$Preview -AddSuffix:$addSuffix
    }
}

# ============================================
# ESECUZIONE
# ============================================
if (-not $InputPath -and -not $PSBoundParameters.ContainsKey('Interactive')) { $Interactive = $true }

if ($Interactive) {
    Start-InteractiveMode
} elseif ($Batch -and $InputPath) {
    if (-not $OutputPath) { $OutputPath = Join-Path $InputPath "Convertiti_MP4" }
    Start-Log -Folder $OutputPath
    Convert-Batch -InputFolder $InputPath -OutputFolder $OutputPath -Sharpening $Sharpening -QualityPreset $QualityPreset -CustomCQ $CustomCQ -AudioCodec $AudioCodec -AudioBitrate $AudioBitrate -Subtitles $Subtitles -Deinterlace:$Deinterlace -Preview:$Preview
} elseif ($InputPath) {
    if (-not $OutputPath) { $OutputPath = Split-Path $InputPath -Parent }
    Start-Log -Folder $OutputPath
    Convert-Single -InputFile $InputPath -OutputFolder $OutputPath -Sharpening $Sharpening -QualityPreset $QualityPreset -CustomCQ $CustomCQ -AudioCodec $AudioCodec -AudioBitrate $AudioBitrate -Subtitles $Subtitles -Deinterlace:$Deinterlace -Preview:$Preview -AddSuffix
} else {
    Write-Host "Fabry MKV to MP4 Converter v1.2" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "USO:" -ForegroundColor Yellow
    Write-Host "  Modalita interattiva: .\Fabry-MKV-to-MP4.ps1" -ForegroundColor Gray
    Write-Host "  Batch:                .\Fabry-MKV-to-MP4.ps1 -InputPath C:\Video -Batch -Sharpening medium -QualityPreset high" -ForegroundColor Gray
}
	
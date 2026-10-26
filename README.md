# 🎬 Fabry MKV Converter

Due tool in uno: converti MKV in MP4 (H.264) o MKV H.265 in H.264, con NVENC (GPU) o CPU.

## 📦 I due script

### 1. `Fabry-MKV-to-MP4.ps1`
Converte **MKV in MP4 H.264**. Mantiene audio, sottotitoli e gestisce deinterlace.
- Qualità: Alta (CQ 19), Bilanciata (CQ 22), Veloce (CQ 25), Custom
- Audio: AAC, E-AC3, Copy
- Sottotitoli: Mantieni, Masterizza, Rimuovi
- Deinterlace automatico

### 2. `Fabry-MKV-H265-to-H264.ps1`
Converte **MKV H.265 in MKV H.264** (mantiene il contenitore MKV).
- Audio e sottotitoli copiati
- Deinterlace opzionale
- Perfetto per lettori che supportano MKV ma non H.265

## ✨ Feature comuni

- ✅ **Auto-download FFmpeg** (nessuna installazione manuale)
- ✅ **NVENC** (GPU) con fallback su **libx264** (CPU)
- ✅ **Modalità singolo file** e **batch**
- ✅ **Log su file** con dettagli per file
- ✅ **Gestione errori** con cattura output FFmpeg
- ✅ **Preset qualità** per ogni esigenza

## 📋 Requisiti

- **Windows 10 / 11**
- **PowerShell 7+**
- **FFmpeg** (scaricato automaticamente al primo avvio)
- **GPU NVIDIA** (opzionale, per NVENC)

## 🚀 Quick start

### GUI (interattivo)

```powershell
git clone https://github.com/fabrytoolbox/Fabry-MKV-Converter.git
cd Fabry-MKV-Converter
Unblock-File .\Fabry-MKV-to-MP4.ps1
.\Fabry-MKV-to-MP4.ps1

Oppure doppio click su avvia-MP4.bat o avvia-H264.bat .
CLI (batch)
powershell
.\Fabry-MKV-to-MP4.ps1 -InputPath "C:\Video" -Batch -QualityPreset high -Sharpening mediu
m
🎚
 Profili di qualità
Profilo
Alta qualità
Bilanciato
Veloce
CQ
19
22
25
Uso
VisoMaster, editing, qualità massima
Uso generico, buon compromesso
File più piccoli, qualità buona
Nota: con CQ 19 e maxrate 20M , il file può essere 3-4x l'input. Per VisoMaster, è il
compromesso giusto.
�
�
 Problemi comuni
"FFmpeg non trovato"
Il tool chiede se scaricarlo. Rispondi Sì. Se fallisce, scaricalo manualmente da
https://www.gyan.dev/ffmpeg/builds/
"NVENC non funziona"
Verifica di avere GPU NVIDIA e driver aggiornati. Se non funziona, il tool usa
automaticamente la CPU ( libx264 ).
"Il file di output è enorme"
Normale con CQ 19 (qualità alta). Se vuoi file più piccoli, usa Bilanciato (CQ 22) o Veloce
(CQ 25).
"Audio/sottotitoli mancanti"
Verifica che il file originale li avesse. Il tool li copia se presenti.
📜
 Licenza
MIT (vedi LICENSE ).
🙏
 Crediti
FFmpeg per l'elaborazione video
NVIDIA NVENC per l'accelerazione GPU

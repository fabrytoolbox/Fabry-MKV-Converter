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
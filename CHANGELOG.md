# Changelog

## [1.0.0] - 2025-01-26

### Added
- **Fabry-MKV-to-MP4.ps1**: converte MKV in MP4 H.264 (NVENC o CPU)
  - Auto-download FFmpeg
  - Fallback CPU (libx264) se NVENC non disponibile
  - Qualita: Alta (CQ 19), Bilanciata (CQ 22), Veloce (CQ 25), Custom
  - Audio: AAC, E-AC3, Copy
  - Sottotitoli: Mantieni, Masterizza, Rimuovi
  - Deinterlace automatico
  - Modalita singolo file e batch
  - Log su file
  - Gestione errori con cattura output FFmpeg
- **Fabry-MKV-H265-to-H264.ps1**: converte MKV da H.265 a H.264 (mantiene MKV)
  - Auto-download FFmpeg
  - Fallback CPU (libx264)
  - Deinterlace opzionale
  - Audio e sottotitoli copiati
  - Modalita singolo file e batch
  - Log su file

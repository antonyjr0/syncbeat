# Icona SyncBeat

`app_icon.png` è l'immagine originale fornita dall'utente, copiata senza modifiche
da Downloads. Il file originale è rimasto al suo posto.

Per rigenerare le risorse Android e Windows, dalla cartella del progetto:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/generate-app-icons.ps1
```

Il comando usa System.Drawing di Windows e non aggiunge dipendenze Flutter.
Genera le cinque densità Android, il foreground adattivo e il file ICO Windows
con sette dimensioni da 16 a 256 pixel. Il foreground Android usa una tela da
108 dp e colloca l'immagine nei 66 dp centrali, secondo la
[guida Android](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive).

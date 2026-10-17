# The 3rd Birthday (PSP) - Proyecto launcher (notas para retomar)
Inicio: 16 de octubre de 2026

## Objetivo
Launcher propio (Electron, plantilla de Pandora's Tower) que arranca PPSSPP portable con:
- Animaciones de inicio y cierre, tema propio del juego, cursor tematico.
- Iconos de botones Xbox y teclado dentro del juego (texturas de reemplazo de PPSSPP).
- "Motor" para modificar el juego (mods/cheats/texturas/archivos) y camara libre con raton y stick derecho.
- Parche al espanol NATIVO del launcher: el usuario pone su ISO americana (ULUS-10567) o europea (ULES-01513)
  y el launcher aplica la traduccion solo. No se redistribuye nada del juego.

## Material en la carpeta
- `The 3rd Birthday(PSP)\juego\The 3rd Birthday(PSP).iso` (1 387 694 080 bytes): version en espanol ya parcheada.
  Segun la ficha publica es el parche de Traducciones del Tio Victor v1.5B (31/07/2021) sobre la europea ULES-01513
  (creditos: SkyBladeCloud, el_capo, Ventus, auron, Akareh, Axxel, Vash, Phoenix, Joghi, eliden, IlDucci). POR CONFIRMAR con el SFO.
- `3rd Birthday, The (Japan).iso` (1 466 368 000 bytes): japonesa (posible fuente de voces JP / undub).
- Imagenes de referencia para el arte del launcher.

## Scripts (scripts\, logs en scripts\logs\)
| Script | Que hace |
|---|---|
| `00_PASOS_1_Y_2.bat` | Ejecuta 01 y 02 seguidos |
| `01_DESCARGAR_PPSSPP.bat` | Descarga PPSSPP Windows (ultima version de GitHub/ppsspp.org) a `PPSSPP\`, modo portable (`PPSSPP\memstick\PSP\...`) |
| `02_EXTRAER_JUEGOS.bat` | Lee cada ISO con un lector ISO9660 propio: PARAM.SFO, hashes (MD5/SHA1), extrae a `extraido\<DISC_ID>__<nombre>\`, inventario con LBA+MD5 en `logs\lista_*.tsv`, copia SFO/iconos/EBOOT a `para_claude\` |

## Plan del parche nativo
1. Extraer la ISO en espanol (hecho con 02) y confirmar region base por DISC_ID.
2. Conseguir hashes de la ISO original EU/US del usuario (Redump) y generar la receta:
   diferencias por archivo (xdelta/VCDIFF) original -> espanol, y para US un mapa de archivos equivalentes.
3. El launcher identifica la ISO del usuario por MD5/DISC_ID, aplica la receta y guarda la ISO en espanol en `cache\`
   (o arranca una carpeta de disco virtual que PPSSPP admite), sin tocar la original.

## Resultados pasos 1 y 2 (16/10/2026)
- PPSSPP 1.20.4 portable en `PPSSPP\` (zip en `descargas\`).
- JP `ULJM05798` v1.01: MD5 688CC341... = Redump limpio. 13 archivos; datos en `USRDIR\3rd.pkg` (1 344 296 960) + indice `3rd.fsd` (7 932).
- ES: volumen **UNDUB**, DISC_ID ULES01513, MD5 C0E56A15C0D92450BDB1BE09426B7300 (no es Redump: esta parcheada).
  Usa **Prometheus Loader**: `EBOOT.BIN` (23 KB) es el cargador, `EBOOT.OLD` el ejecutable, `BOOT.BIN` modificado, + 12 .prx de sistema.
  `3rd.pkg` 1 344 243 712 y `3rd.fsd` distinto al JP.
- MD5 Redump (PPSSPP\assets\redump.csv): USA ULUS-10567 = 47A7CB8E9E73D8AABEF8139DB7EE522B; EU ULES-01513 = D7C2309DA1FB349B8DFCE11F1B6C90A7 (ambas 1 467 547 648 bytes).
- Formato fsd (por investigar): cabecera 0x18, tabla de grupos hasta 0x72C, luego 762 entradas de 8 bytes (u16 inicio + u16 tam/flags + u32=1).

## Paso 3 (parche nativo)
- `03_CREAR_PARCHE.bat`: descarga xdelta3 a `herramientas\`, identifica ISOs en `originales\` por MD5 Redump,
  crea `parche\T3B_ES_desde_<ID>.xdelta` (original -> espanol) y lo verifica aplicandolo. Genera `parche\receta.json`.
- El launcher: identifica la ISO del usuario por MD5 -> aplica el xdelta -> `cache\T3B_ES.iso`. La original nunca se toca.
- Las voces JP (undub) ya vienen en la ISO ES; la JP se guarda para opciones de voz futuras.

## Paso 3 hecho (16/10/2026)
- `parche\T3B_ES_desde_ULUS10567.xdelta` (550 857 087 bytes, MD5 6537BB47...) creado y VERIFICADO (USA -> ES da el MD5 exacto).
- `parche\receta.json` lista la fuente USA. Europa: pendiente (el usuario no tiene la EU original; si la consigue, volver a ejecutar 03).

## Launcher (16/10/2026) - basado en "Concepto Lanzador cinematografico de The 3rd Birthday.png"
- `launcher\resources\app\main.js`: PPSSPP portable, identifica ISOs por MD5 (cache en data\isos.json), parche nativo
  (xdelta3 -> cache\T3B_ES.iso + verificacion MD5), ppsspp.ini/controls.ini en cada inicio, iconos de botones (data\botones\xbox|teclado
  -> TEXTURES\<ID>\botones), motor de mods (mods\<x>\mod.json + textures\ cheats.ini plugin\ ppsspp.ini), pausa F1/L3+R3 (exit.html),
  volumen en vivo, partidas (SAVEDATA), capturas (pt://shots/), tiempo de juego, sesiones, ultima version jugada.
- `launcher\ui\index.html`: lienzo 1600x900 escalado. Paginas INICIO (titulo + emblema, JUGAR, estado, ficha Aya, tarjetas Edicion /
  Ultima partida / Extras), JUGAR (Espanol undub / English / Japones + iconos), CONFIGURACION (Graficos, Sonido, Controles con reasignacion
  teclado/raton/mando, Launcher), EXTRAS (Mods, Galeria, Creditos). Intro "CTI ARCHIVE" + emblema, animacion OVERDIVE al jugar,
  salida CRT + "The end is only the beginning.". Mando (Gamepad API) + teclado + raton, modo automatico. ES/EN.
- Quitado del concepto: marca Square Enix, indicador ONLINE, Noticias (sustituida por Edicion).
- `exit.html` pausa con estilo T3B; `toast.html` aviso de logro (aun sin sistema de logros).
- Fuentes: Special Elite, Share Tech Mono, Barlow (las baja el paso 04; si no, Courier/Consolas/Bahnschrift).
- `scripts\04_INSTALAR_LAUNCHER.bat`: copia el motor Electron de Pandora's Tower -> launcher\The3rdBirthday.exe, fuentes, rcedit (icono),
  carpetas mods\ y juego\, accesos directos.

## Cambios 16/10/2026 (tarde)
- Pausa del launcher: ESC (antes F1). START del juego en teclado: ENTER. ESC/F1 nunca se asignan al juego (main.js los filtra).
- Quitada la pestana MODS de Extras (el motor de mods sigue en main.js por si se usa en el futuro).
- Inicio: quitadas tarjetas Edicion y Extras; menu lateral JUGAR -> selector VERSION (‹ ›, ←/→). Botones de ventana ocultos en
  pantalla completa. Zona de arrastre fuera del lienzo escalado (#drag) porque -webkit-app-region con transform bloqueaba el raton.
  Cursor nuevo (flecha angular negra/roja). El mando solo toma el control al pulsar algo (no por deriva del stick).

## Arreglos 16/10/2026 (noche)
- Lienzo corrido/raton sin respuesta: scrollIntoView desplazaba #stage (overflow:hidden se puede desplazar por codigo). Ahora solo se
  desplaza el .scroll y un 'pin' devuelve stage/body a 0; focusin -> blur; Tab desactivado. #top/#nav con z-index sobre .page.
- Mando por zonas: menu lateral (↑↓, → al contenido) / contenido (geometrico; ← o B vuelve al menu; LB/RB pestanas).
- Quitado CONTINUAR. Rendimiento: bg pre-oscurecido (bg_dark.jpg, sin filter), grano estatico, sin backdrop-filter,
  ceniza con sprites a ~30 fps y pausada al jugar.
- Musica: dos pistas con fundido cruzado de 4.5 s en el bucle; volumen = (mvol/100)^2 * 0.35.
- Error JS del proceso principal: EPIPE al escribir al puente cerrado -> stdin.on('error'), uncaughtException/unhandledRejection al log,
  comprobaciones alive() de ventanas.

## Arreglos 16/10/2026 20:15
- Stick invertido: en XInput (dispositivo 20) el eje Y arriba es POSITIVO (An.Up=20-4002, RightAn.Up=20-4028); en DirectInput (10)
  arriba es negativo (10-4003). Raton: eje 27 negativo = arriba (2-4055).
- Icono/titulo: bridge.ps1 'SKIN <pid>' pone icon.ico (WM_SETICON + GCLP_HICON) y el titulo "The 3rd Birthday" a la ventana PPSSPPWnd cada 1 s.
- Buscador de camara: FindWindow con $null fallaba (PowerShell pasa ""): ahora FindPPSSPP() en C#.
- Al volver del juego ya no se ve la pantalla OVERDIVE: resetLaunchFx() sin transiciones al ocultarse la ventana y al volver.

## Modo ventana / sin bordes (16/10/2026 20:30) - mismo fallo que Vagrant Story (pendiente 1 de su LOG)
- Causas: (1) WindowWidth/Height se escribian en [Graphics]; PPSSPP los lee de [General] (WindowX/Y=-1 centra). (2) El launcher seguia
  en pantalla completa + alwaysOnTop mientras PPSSPP abria su ventana, y se ocultaba por tiempo, no al estar lista la ventana
  (ademas el titulo puesto por SKIN hacia creer que ya estaba lista).
- Solucion: bridge WAITWIN <pid> -> GAMEWIN cuando PPSSPPWnd es visible, >200 px y WM 0xB119 (en partida) != 0 (tope 20 s).
  Luego FOCUSPID (ShowWindow 9 + TOPMOST/NOTOPMOST + Alt) y despues se oculta el launcher. En ventana el launcher no va alwaysOnTop.
  Ventana = 16:9 al 80% de la pantalla en pixeles reales; sin bordes = pantalla completa en pixeles reales + BORDERLESS.
- Aplicar lo mismo en Vagrant Story (esperar ventana lista antes de ocultar, no alwaysOnTop en ventana).

## Camara libre (investigacion)
- Metodo elegido: SIN red ni plugin. PPSSPP Windows responde a WM_APP+0x3118 (0xB118) con Memory::base (lParam 0=low, 1=high);
  0xB119 = en partida; 0xB11A = ID del juego (wParam 0..3). Con ReadProcessMemory/WriteProcessMemory sobre base+direccion_PSP
  el puente (bridge.ps1, ya lee XInput) podra escribir el angulo de camara con el stick derecho/raton.
  (Alternativa descartada: depurador WebSocket -> abre puerto en todas las interfaces y comparte ISOs en la red.)
- `scripts\05_BUSCAR_CAMARA.bat`: con el juego abierto, 10 pasos con F7 -> para_claude\camara\NN_*.bin (RAM 0x08800000, 24 MB) + pasos.json.
  Siguiente: analizar las fotos aqui (floats que cambian con el giro/apuntado y no al caminar), luego herramienta de prueba en vivo.
- EBOOT.OLD (ES) es un ELF/PRX descifrado (tipo 0xFFA0, 4.5 MB de codigo) -> analisis estatico con llvm-objdump (mipsel).
- Fuente de PPSSPP v1.20.4 clonada para consultar (git funciona; raw.githubusercontent/npm/pip bloqueados en este entorno).

## Pendiente
- Ejecutar 04 y probar el launcher (primer arranque: identifica las ISOs por MD5, tarda unos segundos).
- Texturas de botones Xbox/teclado dentro del juego: volcar texturas (Volcar texturas = SI), localizar los iconos de botones PSP
  en TEXTURES\<ID>\new, y generar data\botones\xbox|teclado con textures.ini.
- Camara libre (raton/stick derecho): el juego no tiene control de camara manual; hace falta investigar la RAM (direccion del angulo
  de camara) y hacer un plugin/CWCheat que lea el stick derecho. En la UI figura como EN DESARROLLO.
- Logros (opcional), instaladores (07), README/creditos.

## Camara: hallazgos de las fotos (16/10/2026 20:30, ES ULES01513)
- Foto 01 no valida (10 MB distintos respecto a la 02: aun cargando). Pasos reales: 02 yaw 3.139, 03 2.498, 04 0.080, 05 0.000,
  06 -0.011, 07 (apuntar) 3.090, 08-10 -2.07. Al apuntar NO cambia la inclinacion (-0.022) -> el juego no tiene camara vertical.
- Matriz de vista dibujada (estatica): 0x08C9B7C0 (filas 4x4; forward en +0x60/+0x64/+0x68; yaw = atan2(fx, fz)).
  Mundo/inversa en 0x08C9B800, posicion de camara 0x08C9B830.
- Estructura de camara (4 copias en el heap: 0x09B84AD4, 0x09CAD044, 0x09CAD324, 0x09CAD9F4 = direccion del angulo):
  -0x34 ojo xyz | -0x24 objetivo xyz (Aya + 130 de altura) | -0x10 = 1.0 | -0x04 inclinacion (rad) | +0x00 ANGULO (rad) |
  +0x04 distancia (420 normal, 1000 apuntando) | +0x0C campo de vision (0.698 = 40 grados; 0.628 apuntando).
- `scripts\06_PROBAR_CAMARA.bat`: busca la firma en vivo, prueba cada copia (+0.6 rad durante 0.5 s) midiendo la matriz dibujada,
  y deja un modo libre (stick derecho / teclado numerico). Resultado en para_claude\camara\prueba_camara.txt.
- Dialogo SALIR: ambos botones neutros; solo el enfocado/raton en rojo.

## Camara: prueba 06 (16/10/2026 20:30)
- Escribir angulo/inclinacion en cualquiera de las 16 estructuras NO mueve la camara: el juego las RECALCULA cada fotograma desde
  ojo/objetivo. Hay que encontrar el controlador. Punteros globales hacia las estructuras: tabla en 0x08C3C58C-0x08C3C664 (datos del ejecutable).
- `scripts\07_RASTREAR_CAMARA.bat`: depurador WebSocket local (puerto 45690, solo mientras existe launcher\data\depurador.on; main.js
  pone RemoteDebuggerOnStartup=False si no existe). Fase 1: memory.breakpoint (write, log, logFormat con PC/RA/SP/a0-a2/s0-s3/v0) sobre
  ojo/objetivo/angulos 10 s. Fase 2: cpu.breakpoint en cada PC -> cpu.getAllRegs. Salida para_claude\camara\rastreo.json.
- Mando: B suelta la seleccion -> menu lateral (nunca abre Salir); A en opciones de Configuracion = confirmar y bajar a la siguiente.

## Camara libre IMPLEMENTADA (16/10/2026 21:00) - version ES (ULES01513 traducida)
- Rastreo (07): cadena de la camara del jugador: controlador (funcion que llama desde 0x08AC16A0) calcula ojo ($17+0x130) y objetivo,
  llama setEyeTarget(cam=0x09B84C20, ojo, objetivo) = 0x08B209CC (copia ojo +0x10, objetivo +0x20; luego 0x08B21A8C calcula
  inclinacion +0x40 / angulo +0x44). Despues se copia con 0x08B20780 a 0x09B84A50 y a 0x09CAD9B0 (la que se dibuja).
  Objeto camara: +0x10 ojo, +0x20 objetivo, +0x40 incl, +0x44 angulo, +0x48 dist, +0x50 fov.
- La RAM tiene emuhacks de PPSSPP (0x68xxxxxx): para leer codigo usar EBOOT.OLD (RAM = 0x08804000 + vaddr; jal reubicados).
- Parche: rutina MIPS en 0x08800200 (hueco libre 0x08800000-0x08804000), datos en 0x08800100 (activo, cos/sin giro, cos/sin incl,
  ojo girado en +0x120). Gira el ojo alrededor del objetivo (conserva distancia) y salta a 0x08B209CC. Callsite 0x08AC16A0:
  jal 0x08B209CC (0x0E2C8273) -> jal 0x08800200 (0x0E200080). Verificado con simulador MIPS (dist 420 conservada).
  Fuente: herramientas\camara\camara_libre.s; lineas CWCheat: herramientas\camara\camara_libre_cwcheat.txt.
- main.js: con version 'es' y freecam != off escribe Cheats\ULES01513.ini (cabecera _S ULES-01513 + _C1 Camara libre + mods),
  EnableCheats=True, y manda al puente FREECAM <pid> <raton> <sens> <invX> <invY> <padInvY> <vk teclas rs_*>.
- bridge.ps1 (clase TLSBridge.Cam): 60 Hz; stick derecho (zona muerta 0.2), raton (centra el cursor en la ventana solo con el juego
  delante), teclas rs_* si Camara con teclado = Teclas; R3 solo = centrar; sin tocar 3 s + caminando = vuelve detras de Aya.
  Inclinacion limitada a [-0.85, 0.75] rad.
- PENDIENTE: comprobar sentido de giro/inclinacion en el juego; camara al apuntar (otro controlador, buscar su callsite);
  versiones USA/EU originales (otro ejecutable: buscar por firma de bytes).

## Camara libre v2 (16/10/2026 21:10) - tras la primera prueba del usuario
- v1 (desplazamiento sobre la camara automatica) giraba raro al caminar, ejes invertidos y chocaba con la cruceta (camara del juego).
- v2: rutina de 39 instr. Datos: +0x100 activo, +0x104/108/10C vector unitario deseado (ojo-objetivo), +0x120 ojo resultante,
  +0x130 dx,dy,dz ORIGINALES del juego (se publican siempre). El ojo = objetivo + direccion * distancia del juego.
- Puente: camara fija en el mundo. Al mover stick/raton toma la direccion del juego y gira desde ahi. Cruceta (mando o teclas du/dd/dl/dr)
  -> active=false (manda el juego). R3 o 3 s sin tocar + caminando -> vuelve suave a la direccion del juego y se desactiva.
  Ejes: stick derecha = vista a la derecha (yaw ojo disminuye), arriba = camara sube; raton igual. Inclinacion ojo [-0.55, 1.25].

## Camara libre v2.1 (16/10/2026 21:10)
- Eje vertical invertido otra vez (stick, raton y teclas): ahora stick arriba = camara baja (mira arriba). Horizontal OK.
- Apuntando (LT>60, LB, clic derecho o tecla de L): la camara libre se desactiva (manda el juego). Camara al apuntar = otro controlador: PENDIENTE.
- Reporte del usuario: "dispara sin parar" y "al apuntar no puede ir hacia atras" -> pendiente de aislar (probar con Camara libre = NO).

## Camara libre v3 (16/10/2026 21:15)
- "Mirar arriba" en camara orbital bajaba el ojo contra el suelo. v3: rutina 47 instr; +0x110 = elevacion: sube el objetivo
  (copia en +0x140) -> la vista se inclina arriba. Puente: inclinacion del ojo >= PMIN (-0.02, altura de Aya); lo que baje de ahi
  se convierte en elevacion = dist * tan(PMIN - p) (max 1.1 rad). Stick/raton arriba = mirar arriba. Disparo continuo era PPSSPP (tecla pegada).

## Camara al apuntar: DESCARTADA (16/10/2026 21:30, decision del usuario: "con la del juego me basta")
- La camara libre (v3) queda como esta: al apuntar (LT>60, LB, clic derecho o tecla de L) se desactiva y manda el juego.
- Intentos: 08_BUSCAR_APUNTADO (busqueda en vivo del angulo de apuntado, v2): demasiados candidatos y variaciones minimas al girar;
  ademas probaba escrituras dentro de la zona de codigo (fallo de la herramienta). 09_RASTREAR_APUNTADO (= 07 con -Apuntar) nunca se ejecuto.
- 08/09 quedan sin uso. Si existe launcher\data\depurador.on, borrarlo (o ejecutar 07 y cerrarlo) para que PPSSPP no abra el depurador.
- Si se retoma: buscar el controlador de camara de apuntado igual que el del jugador (otro callsite a setEyeTarget 0x08B209CC
  que solo se ejecute apuntando: breakpoint en 0x08B209CC con logFormat {ra:x} apuntando vs. sin apuntar).

## Texturas HD + botones Xbox / teclado (16/10/2026 21:45)
- Volcado del usuario: 749 PNG en TEXTURES\ULES01513\new. 627 son 04154400... (VRAM, fotogramas de video) y 6 04178000 (capturas): no sirven.
- Texturas clave (hash = direccion + CLUT + datos):
  - Fuente principal 512x256: 0998048021b90c72aff9c741 (paleta "a": blanco con alfa) y 099804806e408c26aff9c741 (paleta "b": con contorno negro).
    Misma imagen de 4 bits: indices = intensidad del glifo (8 niveles) + contorno (8 niveles). Celdas de 17x17, glifo 14x14.
    Iconos en la fila y=221: cuadrado x170, triangulo 187, circulo 204, cruz 221, analogico 238 y 255, cruceta arr 272 / ab 289 /
    izq 306 / der 323, L 340 (34 px), R 374 (34), SELECT 408 (51), START 459 (51).
  - Atlas del HUD 256x512: 08ce4da0c05252b9fadd3775 (gris 128 = blanco, alfa 238). Botones grandes 16x16: circulo (129,11),
    cruz (129,31), triangulo (129,51), cuadrado (129,71); L (33,131,16x12), R (53,131,16x12). Por debajo de y~285 hay basura de memoria
    (si el hash cambia en otra mision, volver a volcar).
  - Fuentes del HUD: 09c5d380... (512x128) y 09c63c00... (512x64), mismas dos paletas, sin iconos.
  - Otras con botones que NO se tocan: 08ce20e02833 (aviso de guardado prerenderizado con "(x) Aceptar"), 08d258b07e8d (titulo "PULSA START").
- herramientas\texturas\hd_base.py: escalado x4 (Scale2x x2 + suavizado + curva de contraste) -> ui\assets\botones\fuente_a/b, hud,
  fuente2_a/b, fuente3_a/b (bases HD con los iconos PSP originales).
- ui\botones.html: dibuja con canvas los iconos Xbox (A/B/X/Y de color, LT/RT, LB/RB, View/Menu, cruceta, sticks) o teclado/raton
  (teclas segun la asignacion actual, raton con boton marcado) encima de las bases. main.js lo abre en una ventana oculta
  (renderGlyphs), cachea en data\botones\cache\<set>_<firma> y copia a TEXTURES\ULES01513\botones y ULUS10567\botones.
- textures.ini lo genera el launcher en cada inicio (marca "# The 3rd Birthday - generado por el launcher"): botones + HD
  (cada hash tambien con 00000000 en la direccion = comodin "sin direccion" de PPSSPP), texturas de mods y textures.user.ini
  (si habia un textures.ini propio del usuario se renombra a textures.user.ini y se fusiona).
- Ajustes nuevos (Graficos > Calidad): Mejora de texturas (4xBRZ / MMPX / Suave / No: Vulkan = TexHardwareScaling + TextureShader
  Tex4xBRZ / TexMMPXAdvanced / TexSpline36_4x; DX11/OpenGL = TexScalingLevel 3 por CPU, xBRZ o bicubico) + TexDeposterize;
  Texto, HUD y botones en HD (hdTex); Filtro de imagen ([PostShaderList] PostShader1 = Sharpen / FXAA / NaturalA / Off).

## Sin avisos de PPSSPP + iconos en vivo (16/10/2026 21:55)
- "ShowOnScreenMessages" NO existe en PPSSPP 1.20.4 (no hacia nada). Lo correcto: [General] NotificationPos = -1 (posicion "ninguna":
  OnScreenDisplay.cpp salta esos avisos) + [Achievements] AchievementsEnable = False.
- Iconos en vivo (Iconos de botones = Automatico): main.js dibuja los dos juegos (xbox y kb) al iniciar; el puente (DEVWATCH 1) mira,
  con el juego delante, si se usa el mando (botones, sticks >14000, LT) o teclado/raton (cualquier tecla salvo Alt/BloqDespl/ESC)
  y emite DEV pad / DEV kb. main.js copia los 3 PNG con iconos a TEXTURES\<ID>\botones y manda TEXRELOAD: el puente pulsa
  Bloq Despl dos veces (controls.ini: Texture Replacement = 1-116). En PPSSPP eso apaga el reemplazo (Decimate ALL) y lo vuelve a
  encender (LoadIni + cache de texturas limpia) -> relee los PNG. Minimo 1,5 s entre cambios.

## Iconos en vivo: QUITADO (16/10/2026 22:00)
- Probado por el usuario: alternando mando/teclado los iconos no cambiaban. Se quito todo (DEVWATCH/TEXRELOAD del puente,
  Texture Replacement = Bloq Despl en controls.ini). Iconos de botones = solo XBOX o TECLADO (sin Automatico ni PSP).
- Posible causa si se retoma: la tecla virtual no llegaba (entrada sintetica / RawInput) o PPSSPP no reactiva el reemplazo; probar a mano
  con Bloq Despl mapeado y mirar el log de PPSSPP.
- Aviso de guardado del inicio (08ce20e028333f3153a656a7, 512x128 opaco): ahora tambien en HD con el icono de aceptar (celda 208,72 12x12).

## Botones/HD en la version en ingles + camara libre multi-version (16/10/2026 22:10)
- Volcado ULUS10567: mismas posiciones que la ES. Hashes: fuente 09973c8021b90c722128ceb2 / 09973c806e408c262128ceb2,
  HUD 08ce4da0f75bf2e1358b383d, aviso 08ce20e0482166f676a926dd (icono en 225,72 12x12), fuentes HUD 09c6238021b9017217ea854f /
  09c623806e40812617ea854f y 09c64c0021b9017240e68a53 / 09c64c006e40812640e68a53 (512x32).
  Bases HD en ui\assets\botones\us (hd_base.py ... us). main.js TEXSETS: los dos juegos (es, us) se instalan en botones\es y botones\us
  de cada ID y el textures.ini lista ambos (vale el que coincida).
- Camara: ejecutables PSP descifrados con pspdecrypt (github John-K/pspdecrypt, compilado en el contenedor). PRX con base 0,
  cargados en 0x08804000. Firma (48 palabras, j/jal enmascarados) de setEyeTarget y del callsite:
  ES (EBOOT.OLD): fn 0x08B209CC, site 0x08AC16A0 (jal 0x0E2C8273). JP (ULJM05798 EBOOT.BIN): fn 0x08B20008, site 0x08AC0D68 (jal 0x0E2C8002).
  USA (ULUS10567, descifrado de para_claude\eboot): MISMAS direcciones que la ES (el EBOOT.OLD espanol sale del ejecutable USA).
- Truco multi-version: un _C1 por version que empieza con 0xC<site> <jal original> (si no coincide, el truco se detiene: seguro en
  versiones desconocidas); la rutina es la misma salvo el salto final (j fn). freecamOn ya no depende de la version.

## ISO japonesa no detectada (16/10/2026 22:20)
- La ISO japonesa esta suelta en la raiz del proyecto ("3rd Birthday, The (Japan).iso", MD5 688CC341... = Redump, OK) y el launcher
  solo buscaba en juego\, originales\ y The 3rd Birthday(PSP)\juego\. Ahora tambien busca en la raiz del proyecto ('..', sin subcarpetas).
  (La carpeta extraido\ no sirve para jugar: PPSSPP necesita la ISO.)

=====================================================================================================
## BITACORA - ESTADO AL CIERRE DEL 16/10/2026 (para retomar manana)
=====================================================================================================
HECHO Y PROBADO POR EL USUARIO
- Launcher Electron (concepto cinematografico), navegacion raton/mando, modo ventana/sin bordes/completa, icono del juego, musica,
  pausa con ESC / L3+R3, dialogo de salida, B = volver, A en ajustes = aplicar y bajar.
- Parche espanol nativo (xdelta desde USA ULUS10567 -> cache\T3B_ES.iso, UNDUB: texto ES + voces JP).
- Camara libre v3 (raton + stick derecho) en la version espanola. Camara al apuntar: DESCARTADA.
- Texturas HD (fuente, HUD, fuentes del HUD, aviso de guardado) + iconos Xbox / teclado-raton en la version ES ("ya funciona").
- Sin avisos de PPSSPP (NotificationPos = -1, logros desactivados).
- Iconos de botones: solo XBOX o TECLADO (el cambio en vivo se intento y no funciono: quitado).

HECHO, PENDIENTE DE QUE EL USUARIO LO PRUEBE
- Iconos Xbox/teclado + HD en la version en ingles (USA): juego de texturas 'us' (ui\assets\botones\us).
- Camara libre en USA y JP (truco multi-version con comprobacion 0xC). USA = mismas direcciones que ES; JP: site 0x08AC0D68, fn 0x08B20008.
- Deteccion de la ISO japonesa en la raiz del proyecto.

PENDIENTE PARA MANANA
1. El usuario abre la version japonesa y hace un volcado (Graficos > Herramientas > Volcar texturas = SI): aviso inicial, titulo,
   partida con HUD y botones, menu de pausa. Luego: stagear TEXTURES\ULJM05798\new, localizar fuente con iconos (buscar celdas
   iguales a las de la fila y=221; la fuente JP probablemente es otra), HUD 08ce4da0..., aviso 08ce20e0..., anadir set 'jp' a
   hd_base.py (SETS) y a TEXSETS de main.js (dir 'jp', lang 'en' o etiquetas en japones si se quiere), revisar posiciones.
2. Confirmar que la camara libre funciona en USA y JP (si en JP no, comprobar la direccion de carga del modulo con 05_BUSCAR_CAMARA).
3. Opcional: "PULSA START" del titulo (08d258b07e8d...) con icono Xbox/teclado; version europea en ingles (ULES01513 original) si el
   usuario consigue la ISO (anadir xdelta desde EU con scripts\03 y su firma de camara).

NOTAS TECNICAS UTILES
- Ejecutables descifrados con pspdecrypt (git clone github.com/John-K/pspdecrypt + make en el contenedor). scripts\10_COPIAR_EBOOT
  copia los EBOOT.BIN de las ISOs a para_claude\eboot. Firma: /tmp sig.py (48 palabras alrededor, j/jal y lui enmascarados).
- Al subir archivos al PC: VERIFICAR siempre (volver a stagear y comparar). Dos veces el commit dijo "written" pero dejo el archivo
  viejo; usar un nombre de archivo nuevo en outputs\ para cada commit lo soluciono.
- El launcher solo carga main.js al arrancar: tras cambios, cerrar del todo (The3rdBirthday.exe en el Administrador de tareas).

## 16/10/2026 22:20 - El usuario YA HIZO el volcado de la version japonesa
- Esta en PPSSPP\memstick\PSP\TEXTURES\ULJM05798\new. Manana: empezar directamente por el punto 1 de PENDIENTE (sin pedir otro volcado).

## 17/10/2026 09:10 - Version japonesa (texturas)
- Volcado JP (ULJM05798): la fuente esta en 3 paginas: 09921a80 (512x512), 09941a80 (512x512) y 09961a80 (512x128, iconos).
  La pagina 3 tiene 5 hashes distintos: solo cambian las filas 125-126 (basura de memoria). Solucion: [hashranges]
  0x09961a80,512,128 = 512,96 (el launcher lo escribe en TEXTURES\ULJM05798\textures.ini). Con eso el hash cambia y HAY QUE
  VOLVER A VOLCAR para conocerlo (y el de la paleta con contorno 6e40, que no salio). Celdas JP: fila y=51 (cuadrado x187 ... SELECT 425),
  START en (0,68). Aviso JP 08ce16e085af7cf3d075151e: icono del circulo (acepta) en 225,72 -> avisoAct 'circle'.
  El HUD JP (08ce43a0?) no salio en el volcado: hace falta jugar un poco con el HUD en pantalla.
- Kanji: el escalado Scale2x los empasta; para JP se usa bloques x4 + suavizado 0.8 + curva 0.40-0.60 (hd_base.py kanji=True).
- TEXSETS 'jp' en main.js: aviso + paginas 1/2 + fuente pequena 09c65a00 ya activas; fuente_a/b (pagina 3) dibujadas pero SIN hash todavia.
- PENDIENTE: tras el nuevo volcado JP, buscar 09961a80xxxxxxxx (21b9 y 6e40) y el HUD, y anadirlos a TEXSETS jp (glyph).

- Decision del usuario (17/10 09:03): en la version japonesa se mantiene fiel: aceptar = circulo = B de Xbox (no se intercambian controles).

## 17/10/2026 09:15 - Segundo volcado JP
- El [hashranges] funciona: pagina 3 de la fuente (rango 512x96) = 09961a8021b9037233f4e3ad (identica a las filas 0-95 de antes).
  Anadida a TEXSETS jp (fuente_a.png). Nuevas variantes de paginas 1/2: 09921a806e408d2653583b63 (b), 09941a8021b90d7281beb8d9 (a).
- Siguen sin salir: pagina 3 con paleta de contorno (09961a806e40....) y el atlas del HUD japones (~08ce43a0, 256x512).
  Probablemente el volcado no llego a la partida con HUD. PENDIENTE si el usuario vuelve a volcar jugando.

## 17/10/2026 09:25 - Volcado final JP + arranque lento
- Volcado final JP: no aparece el atlas del HUD japones ni la pagina 3 con contorno. El usuario dice que todo se ve bien:
  probablemente el HUD JP es identico (CLUT+datos) al de la USA en otra direccion y lo reemplaza la entrada comodin
  00000000f75bf2e1358b383d (PPSSPP no vuelca texturas ya reemplazadas). Version JP: TERMINADA.
- Arranque lento (log: 6-14 s entre "Launcher iniciado" y la interfaz): ahora
  - clearCache de Chromium solo si cambian index/exit/toast/botones.html (data\ui_firma.txt),
  - las ventanas de pausa y avisos se crean 2,5 s despues,
  - el log muestra "Interfaz lista en N ms" para medirlo.
- Al jugar: applyButtons copia texturas solo a la carpeta del juego que se abre y solo si cambiaron (antes ~60 MB por inicio).


## Publicacion v1.0.0 (17-oct-2026)
- Repositorio: https://github.com/kaiwolft/3rd-BIrthday-Launcher (README es/en/fr, aviso legal, creditos, Ko-fi, capturas).
- Release v1.0.0 publicado por GitHub Actions (.github/workflows/build.yml, se dispara al cambiar VERSION):
  - The_3rd_Birthday_Instalador_Windows_v1.0.0.zip (709 MB, PPSSPP 1.20.4 incluido)
  - Instalar_The_3rd_Birthday-x86_64.AppImage (658 MB, usa el PPSSPP del usuario, Flatpak recomendado)
- El instalador pide la ISO USA (ULUS-10567) y/o la japonesa (ULJM-05798), verificadas por MD5; con la USA crea el espanol UNDUB.
- Parche en parche/partes (6 trozos de 95 MB, script 11); el workflow los une y verifica MD5 6537bb47f88eece50d126cf40fd24ea5.
- Para una version nueva: corregir, actualizar NOTAS_RELEASE_vX.Y.Z.md / CHANGELOG.md y cambiar VERSION.
- Steam en Linux: steam/agregar_a_steam.sh + agregar_a_steam.py (Python 3, VDF binario, Steam nativo/Flatpak/Steam Deck).
  Tambien agregado a Fragile Dreams, The Last Story y Pandora's Tower (scripts, instalador, README). Astral Chain es solo Windows.
- Carpeta final: script 12 ahora usa F:\Juegos de DIonis Con launcher personalizado (o E:\ si no hay F:).
  El AGREGAR_A_STEAM.ps1 general usa su propia carpeta ($PSScriptRoot): sigue funcionando tras moverla a F:.


## Logros (17-oct-2026, v1.1.0)
- Set RetroAchievements juego 3511 (74 logros, 1205 pts, autor zizom; el servidor agrega un aviso 101000001 de 0 pts que se filtra).
- Motor: herramientas/logros/t3b_logros.c (rcheevos v11.6.0, API peek(addr, n, ud) devuelve el valor). Compilar: sh herramientas/logros/build.sh.
  - Memoria RA PSP: 0x0-0x1FFFFFF = PSP 0x08000000+. Windows: base con SendMessage(PPSSPPWnd, WM_APP+0x3118, 0, 0/1);
    juego cargado = WM_APP+0x311A != 0; en partida = WM_APP+0x3119. Linux: /dev/shm/ppsspp_N.ram (deleted) via /proc/<pid>/fd, RAM en 0x204000 (0x214000 con pagina nula).
  - Probado en Linux con memoria simulada (UNLOCK y PROGRESS OK). Windows: falta confirmar en partida real ("HOOKED" en launcher.log).
- Launcher: Extras -> LOGROS (lista, puntos, progreso), descarga con login2 + patch (no guarda contrasena ni token) -> data/logros/ra_3511.json,
  iconos en ui/assets/logros, progreso en data/logros/progreso.json, traducciones en resources/app/logros_traducciones.json.
  Solo versiones us y es (la ES UNDUB tiene ID ULES01513 pero el mismo codigo que USA). Opciones achievements / achToast.
- GitHub: job "nativos" compila t3b_logros para Linux y Windows. Release v1.1.0 publicado.
  PENDIENTE: borrar a mano los assets sueltos t3b_logros y t3b_logros.exe del release v1.1.0 (ya corregido el workflow).

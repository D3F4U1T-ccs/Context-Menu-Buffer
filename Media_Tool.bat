@echo off
rem ============================================================================
rem  MEDIA TOOL - комбайн для видео, аудио и картинок через ПКМ (на базе ffmpeg)
rem  Сохранять в UTF-8 без BOM. Нужны ffmpeg и ffprobe в PATH.
rem  Шкала прогресса и отмена работают через встроенный PowerShell:
rem  его код лежит в самом низу этого файла, после метки PSCODE.
rem  Запуск: MediaTool.bat "путь\к\файлу.mp4"
rem ============================================================================
chcp 65001 >nul
title Media Tool

setlocal DisableDelayedExpansion
if "%~1"=="" goto NOARG
if not exist "%~1" goto NOFILE
set "MT_SELF=%~f0"
set "INPUT=%~f1"
set "IN_DIR=%~dp1"
set "IN_NAME=%~n1"
set "IN_EXT=%~x1"
set "IN_SIZE=%~z1"
setlocal EnableDelayedExpansion

where ffmpeg >nul 2>&1 || goto NOFFMPEG
where ffprobe >nul 2>&1 || goto NOFFMPEG
where powershell >nul 2>&1 || goto NOPS

call :INFO
if "!BADFILE!"=="1" goto NOMEDIA
goto MAIN


rem ============================================================================
rem  ГЛАВНОЕ МЕНЮ
rem ============================================================================
:MAIN
set "ABR=" & set "LOSSY=0" & set "FIXEXT=0" & set "CRF=18"
call :HEADER
set "MN=0"
call :ADDM "Конвертировать" CONVERT
call :ADDM "Сжать" COMPRESS
if "!CAN_TRIM!"=="1"  call :ADDM "Обрезать" TRIM
if "!CAN_MUTE!"=="1"  call :ADDM "Удалить звук" MUTE
if "!CAN_RES!"=="1"   call :ADDM "Изменить разрешение" RES
if "!CAN_SPEED!"=="1" call :ADDM "Изменить скорость" SPEED
if "!CAN_ROT!"=="1"   call :ADDM "Повернуть / отзеркалить" ROTATE
if "!CAN_VOL!"=="1"   call :ADDM "Громкость" VOLUME
set "MI=0"
:MAIN_SHOW
set /a "MI+=1"
if !MI! GTR !MN! goto MAIN_ASK
echo   !MI!  !ML%MI%!
goto MAIN_SHOW
:MAIN_ASK
echo   0  Выход
echo(
set "CH="
set /p "CH=  Выбор: "
call :TRIMVAR CH
if "!CH!"=="0" goto EXIT
set "MI=0"
:MAIN_FIND
set /a "MI+=1"
if !MI! GTR !MN! goto MAIN
if "!CH!"=="!MI!" goto !MG%MI%!
goto MAIN_FIND


rem ============================================================================
rem  1. КОНВЕРТАЦИЯ
rem ============================================================================
:CONVERT
call :HEADER
echo   КОНВЕРТАЦИЯ - выбери формат
echo(
set "LCOUNT=0"
if "!IS_IMG!"=="1" goto CONV_L_IMG
if "!IS_AUDIO!"=="1" goto CONV_L_AUDIO
set "LIST_V=mp4 mkv avi mov webm gif wmv flv mpg ts 3gp m4v ogv"
set "LIST_A=mp3 wav flac m4a aac ogg opus wma aiff ac3 mka"
echo   Видео:
set "LIST=!LIST_V!" & call :SHOWLIST
echo(
echo   Аудио:
set "LIST=!LIST_A!" & call :SHOWLIST
set "ALLLIST=!LIST_V! !LIST_A!"
goto CONV_ASK

:CONV_L_AUDIO
set "ALLLIST=mp3 wav flac m4a aac ogg opus wma aiff ac3 mka mp2 wv"
set "LIST=!ALLLIST!" & call :SHOWLIST
goto CONV_ASK

:CONV_L_IMG
set "ALLLIST=jpg png webp gif bmp tiff ico avif tga"
if "!IS_ANIM!"=="1" set "ALLLIST=gif webp apng mp4 webm mkv mov jpg png bmp tiff ico avif"
if "!IS_ANIM!"=="1" echo   Анимация: в gif, webp, apng и видео остается анимацией, в остальные берется первый кадр.
if "!IS_ANIM!"=="1" echo(
set "LIST=!ALLLIST!" & call :SHOWLIST

:CONV_ASK
set /a "CIDX=LCOUNT+1"
echo(
echo   !CIDX!  Другой формат - ввести самому
echo(
echo   0  Назад
echo(
set "CH="
set /p "CH=  Выбор: "
call :TRIMVAR CH
if "!CH!"=="0" goto MAIN
if "!CH!"=="" goto CONVERT
for /f "delims=0123456789" %%x in ("!CH!") do goto CONVERT
set "EXTX="
set "CI=0"
for %%E in (!ALLLIST!) do (
    set /a "CI+=1"
    if "!CI!"=="!CH!" set "EXTX=%%E"
)
if defined EXTX goto CONVERT_GO
if "!CH!"=="!CIDX!" goto CONVERT_CUSTOM
goto CONVERT

:CONVERT_CUSTOM
echo(
echo   Введи расширение нового файла, например wmv, ogg, jp2.   b = назад
set "EXTX="
set /p "EXTX=  Формат: "
call :TRIMVAR EXTX
if /i "!EXTX!"=="b" goto CONVERT
if "!EXTX:~0,1!"=="." set "EXTX=!EXTX:~1!"
if "!EXTX!"=="" goto CONVERT_CUSTOM
if not "!EXTX:~8!"=="" goto CONVERT_CUSTOM_BAD
for /f "delims=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" %%x in ("!EXTX!") do goto CONVERT_CUSTOM_BAD
goto CONVERT_GO
:CONVERT_CUSTOM_BAD
echo   Неверный формат, нужны только буквы и цифры, до 8 символов.
goto CONVERT_CUSTOM

:CONVERT_GO
call :SETFMT
if "!KIND!"=="V" if "!IS_AUDIO!"=="1" goto NOVIDEO
if "!KIND!"=="V" if "!IS_IMG!"=="1" if "!IS_ANIM!"=="0" goto NOSTATIC2VIDEO
if "!KIND!"=="A" if "!IS_IMG!"=="1" goto NOAUDIOIMG
if "!KIND!"=="A" if "!HAS_AUDIO!"=="0" goto NOAUDIO
if "!KIND!"=="I" if "!IS_AUDIO!"=="1" goto NOIMGFROMAUDIO
if "!KIND!"=="G" if "!IS_AUDIO!"=="1" goto NOVIDEO
if "!KIND!"=="G" goto CONVERT_GIF
set "OSUF="
call :MAKEOUT
set "ACT=Конвертирую в !OEXT!..."
set "FFARGS=-i "!INPUT!" !COPTS! "!OUT!""
call :RUN
goto MAIN

:CONVERT_GIF
if "!IS_AUDIO!"=="1" goto NOVIDEO
echo(
echo   Совет: GIF лучше делать из короткого куска - сначала обрежь видео в пункте 3.
set "AI_PROMPT=  Ширина GIF в пикселях, от 16 до 1920, например 480, b = назад:"
set "AI_MIN=16" & set "AI_MAX=1920"
call :ASKINT
if /i "!NUM!"=="b" goto CONVERT
set "GW=!NUM!"
set "AI_PROMPT=  Кадров в секунду, от 1 до 60, например 15, b = назад:"
set "AI_MIN=1" & set "AI_MAX=60"
call :ASKINT
if /i "!NUM!"=="b" goto CONVERT
set "GF=!NUM!"
set "OSUF=" & set "OEXT=gif"
call :MAKEOUT
set "GVF=fps=!GF!,scale=!GW!:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse"
set "ACT=Конвертирую в GIF..."
set "FFARGS=-i "!INPUT!" -an -vf "!GVF!" -loop 0 "!OUT!""
call :RUN
goto MAIN


rem ============================================================================
rem  2. СЖАТИЕ
rem ============================================================================
:COMPRESS
if "!IS_IMG!"=="1" goto COMPRESS_IMG
call :HEADER
echo   СЖАТИЕ
echo(
echo   1  Lossless - без потерь, файл может получиться БОЛЬШЕ оригинала
echo   2  С потерей - готовые уровни
echo   3  С потерей - свое качество
echo(
echo   0  Назад
echo(
set "CH="
set /p "CH=  Выбор: "
call :TRIMVAR CH
if "!CH!"=="0" goto MAIN
if "!CH!"=="1" goto COMP_LOSSLESS
if "!CH!"=="2" goto COMP_PRESET
if "!CH!"=="3" goto COMP_CUSTOM
goto COMPRESS

:COMP_LOSSLESS
set "OSUF=_lossless"
if "!IS_AUDIO!"=="1" (
    set "OEXT=flac"
    set "COPTS=-vn -c:a flac -compression_level 8"
) else (
    set "OEXT=mkv"
    set "COPTS=-map 0:v:0 -map 0:a? -c:v libx264 -crf 0 -preset medium -c:a copy"
)
call :MAKEOUT
set "ACT=Сжимаю без потерь..."
set "FFARGS=-i "!INPUT!" !COPTS! "!OUT!""
call :RUN
goto MAIN

:COMP_PRESET
call :HEADER
echo   СЖАТИЕ С ПОТЕРЕЙ - выбери уровень
echo(
if "!IS_AUDIO!"=="1" goto COMP_PRESET_A
echo   1  Почти без потерь    CRF 18
echo   2  Легкое              CRF 23
echo   3  Среднее             CRF 28
echo   4  Сильное             CRF 32
goto COMP_PRESET_ASK
:COMP_PRESET_A
echo   1  Высокое     256 кбит/с
echo   2  Хорошее     192 кбит/с
echo   3  Среднее     128 кбит/с
echo   4  Сильное      64 кбит/с
:COMP_PRESET_ASK
echo(
echo   0  Назад
echo(
set "CH="
set /p "CH=  Выбор: "
call :TRIMVAR CH
if "!CH!"=="0" goto COMPRESS
set "Q="
if "!IS_AUDIO!"=="1" (
    if "!CH!"=="1" set "Q=256"
    if "!CH!"=="2" set "Q=192"
    if "!CH!"=="3" set "Q=128"
    if "!CH!"=="4" set "Q=64"
) else (
    if "!CH!"=="1" set "Q=18"
    if "!CH!"=="2" set "Q=23"
    if "!CH!"=="3" set "Q=28"
    if "!CH!"=="4" set "Q=32"
)
if not defined Q goto COMP_PRESET
goto COMP_RUN

:COMP_CUSTOM
if "!IS_AUDIO!"=="1" (
    set "AI_PROMPT=  Битрейт в кбит/с, от 32 до 320, например 128, b = назад:"
    set "AI_MIN=32" & set "AI_MAX=320"
) else (
    set "AI_PROMPT=  CRF от 0 до 51. Меньше = лучше качество. 18 почти без потерь, 23 норма, 28 сильнее, b = назад:"
    set "AI_MIN=0" & set "AI_MAX=51"
)
call :ASKINT
if /i "!NUM!"=="b" goto COMPRESS
set "Q=!NUM!"
goto COMP_RUN

:COMP_RUN
set "OSUF=_compressed"
if "!IS_AUDIO!"=="1" (
    set "ABR=!Q!" & set "LOSSY=1"
    call :SETAUDIO
    set "OEXT=!AEXT!"
    set "COPTS=-vn !AENC!"
) else (
    set "CRF=!Q!" & set "FIXEXT=0"
    call :SETVIDEO
    set "OEXT=!VEXT!"
    set "COPTS=-map 0:v:0 -map 0:a? !VENC! !AKEEP!"
)
call :MAKEOUT
set "ACT=Сжимаю..."
set "FFARGS=-i "!INPUT!" !COPTS! "!OUT!""
call :RUN
goto MAIN


rem ============================================================================
rem  2а. СЖАТИЕ КАРТИНОК
rem ============================================================================
:COMPRESS_IMG
call :HEADER
echo   СЖАТИЕ КАРТИНКИ
echo(
echo   1  С потерей - готовые уровни
echo   2  С потерей - свое качество
echo   3  Без потерь - файл может получиться БОЛЬШЕ оригинала
echo(
echo   JPG остается JPG, WebP остается WebP, AVIF остается AVIF.
echo   Остальные форматы с потерей сжимаются в WebP: он меньше
echo   и сохраняет прозрачность.
echo(
echo   0  Назад
echo(
set "CH="
set /p "CH=  Выбор: "
call :TRIMVAR CH
if "!CH!"=="0" goto MAIN
if "!CH!"=="1" goto CIMG_PRESET
if "!CH!"=="2" goto CIMG_CUSTOM
if "!CH!"=="3" goto CIMG_LOSSLESS
goto COMPRESS_IMG

:CIMG_PRESET
call :HEADER
echo   СЖАТИЕ КАРТИНКИ - выбери уровень
echo(
echo   1  Высокое    качество 90
echo   2  Хорошее    качество 80
echo   3  Среднее    качество 65
echo   4  Сильное    качество 45
echo(
echo   0  Назад
echo(
set "CH="
set /p "CH=  Выбор: "
call :TRIMVAR CH
if "!CH!"=="0" goto COMPRESS_IMG
set "Q="
if "!CH!"=="1" set "Q=90"
if "!CH!"=="2" set "Q=80"
if "!CH!"=="3" set "Q=65"
if "!CH!"=="4" set "Q=45"
if not defined Q goto CIMG_PRESET
set "LL=0"
goto CIMG_RUN

:CIMG_CUSTOM
set "AI_PROMPT=  Качество от 1 до 100, больше = лучше, например 80, b = назад:"
set "AI_MIN=1" & set "AI_MAX=100"
call :ASKINT
if /i "!NUM!"=="b" goto COMPRESS_IMG
set "Q=!NUM!"
set "LL=0"
goto CIMG_RUN

:CIMG_LOSSLESS
set "Q=100"
set "LL=1"

:CIMG_RUN
set "OSUF=_compressed"
call :CIMGENC
call :MAKEOUT
set "ACT=Сжимаю картинку, формат !OEXT!..."
set "FFARGS=-i "!INPUT!" !COPTS! "!OUT!""
call :RUN
goto MAIN


rem ============================================================================
rem  3. ОБРЕЗКА
rem ============================================================================
:TRIM
call :HEADER
echo   ОБРЕЗКА
echo   Время вводи так: 2:39  или  1:02:39  или просто секунды.
echo   0 в начале = с самого начала.  0 в конце = до самого конца.
echo   b = назад
echo(
:TRIM_S
set "TS="
set /p "TS=  Начало: "
call :TRIMVAR TS
if /i "!TS!"=="b" goto MAIN
if "!TS!"=="" goto TRIM_S
for /f "delims=0123456789:." %%x in ("!TS!") do (
    echo   Неверный формат времени.
    goto TRIM_S
)
:TRIM_E
set "TE="
set /p "TE=  Конец:  "
call :TRIMVAR TE
if /i "!TE!"=="b" goto TRIM_S
if "!TE!"=="" goto TRIM_E
for /f "delims=0123456789:." %%x in ("!TE!") do (
    echo   Неверный формат времени.
    goto TRIM_E
)
set "SA=" & set "EA="
set "Z=!TS::=!" & set "Z=!Z:.=!" & set "Z=!Z:0=!"
if not "!Z!"=="" set "SA=-ss !TS!"
set "Z=!TE::=!" & set "Z=!Z:.=!" & set "Z=!Z:0=!"
if not "!Z!"=="" set "EA=-to !TE!"
if not defined SA if not defined EA goto TRIM_NOTHING
if "!IS_IMG!"=="1" goto TRIM_PRECISE
echo(
echo   1  Точно - с перекодированием, медленнее, режет по кадрам
echo   2  Быстро - без перекодирования и без потери качества,
echo      начало может сместиться до ближайшего ключевого кадра
echo(
echo   0  Назад
echo(
:TRIM_MODE
set "CH="
set /p "CH=  Выбор: "
call :TRIMVAR CH
if "!CH!"=="0" goto TRIM
if "!CH!"=="1" goto TRIM_PRECISE
if "!CH!"=="2" goto TRIM_FAST
goto TRIM_MODE

:TRIM_NOTHING
echo(
echo   Нечего обрезать: и начало, и конец равны 0.
call :WAIT
goto MAIN

:TRIM_PRECISE
set "OSUF=_trim"
if "!IS_IMG!"=="1" goto TRIM_IMG
if "!IS_AUDIO!"=="1" (
    call :SETAUDIO
    set "OEXT=!AEXT!"
    set "COPTS=-vn !AENC!"
) else (
    set "CRF=18" & set "FIXEXT=0"
    call :SETVIDEO
    set "OEXT=!VEXT!"
    set "COPTS=-map 0:v:0 -map 0:a? !VENC! !VAENC!"
)
call :MAKEOUT
if defined SA set "MT_SS=!TS!"
if defined EA set "MT_TO=!TE!"
set "ACT=Обрезаю..."
set "FFARGS=-i "!INPUT!" !SA! !EA! !COPTS! "!OUT!""
call :RUN
goto MAIN

:TRIM_IMG
set "VFX="
call :SETANIM
call :MAKEOUT
if defined SA set "MT_SS=!TS!"
if defined EA set "MT_TO=!TE!"
set "ACT=Обрезаю анимацию..."
set "FFARGS=-i "!INPUT!" !SA! !EA! !COPTS! "!OUT!""
call :RUN
goto MAIN

:TRIM_FAST
set "OSUF=_trim"
set "OEXT=!IN_EXT:~1!"
call :MAKEOUT
if defined SA set "MT_SS=!TS!"
if defined EA set "MT_TO=!TE!"
set "ACT=Обрезаю без перекодирования..."
set "FFARGS=!SA! !EA! -i "!INPUT!" -map 0:v? -map 0:a? -c copy -avoid_negative_ts make_zero "!OUT!""
call :RUN
goto MAIN


rem ============================================================================
rem  4. УДАЛИТЬ ЗВУК
rem ============================================================================
:MUTE
if "!HAS_AUDIO!"=="0" (
    echo(
    echo   В этом файле и так нет звука.
    call :WAIT
    goto MAIN
)
set "OSUF=_nosound"
set "OEXT=!IN_EXT:~1!"
call :MAKEOUT
set "ACT=Удаляю звук..."
set "FFARGS=-i "!INPUT!" -map 0:v -c copy -an "!OUT!""
call :RUN
goto MAIN


rem ============================================================================
rem  5. РАЗРЕШЕНИЕ
rem ============================================================================
:RES
if not defined VW goto NODIMS
call :HEADER
echo   РАЗРЕШЕНИЕ   сейчас: !VW!x!VH!
echo(
echo   1  480p
echo   2  720p
echo   3  1080p
echo   4  1440p
echo   5  2160p  4K
echo   6  Свое - ввести ширину и высоту
if "!IS_IMG!"=="1" echo   7  50%% от исходного
if "!IS_IMG!"=="1" echo   8  25%% от исходного
echo(
echo   0  Назад
echo(
set "CH="
set /p "CH=  Выбор: "
call :TRIMVAR CH
if "!CH!"=="0" goto MAIN
if "!CH!"=="6" goto RES_CUSTOM
if "!CH!"=="7" if "!IS_IMG!"=="1" set "PCT=50" & goto RES_PCT
if "!CH!"=="8" if "!IS_IMG!"=="1" set "PCT=25" & goto RES_PCT
set "RS="
if "!CH!"=="1" set "RS=480"
if "!CH!"=="2" set "RS=720"
if "!CH!"=="3" set "RS=1080"
if "!CH!"=="4" set "RS=1440"
if "!CH!"=="5" set "RS=2160"
if not defined RS goto RES
rem Пресет задает меньшую сторону кадра, поэтому вертикальные видео тоже работают верно
set "VF=scale=-2:!RS!"
set "SS=!VH!"
if !VW! LSS !VH! set "VF=scale=!RS!:-2"
if !VW! LSS !VH! set "SS=!VW!"
if !RS! GEQ !SS! echo   Внимание: новый размер не меньше исходного, это будет увеличение.
set "OSUF=_!RS!p"
goto RES_RUN

:RES_CUSTOM
set "AI_PROMPT=  Ширина в пикселях, b = назад:"
set "AI_MIN=2" & set "AI_MAX=16384"
call :ASKINT
if /i "!NUM!"=="b" goto RES
set "NW=!NUM!"
set "AI_PROMPT=  Высота в пикселях, b = назад:"
call :ASKINT
if /i "!NUM!"=="b" goto RES
set "NH=!NUM!"
rem H.264 требует четные числа
if "!IS_IMG!"=="0" set /a "NW=NW/2*2, NH=NH/2*2"
set "OSUF=_!NW!x!NH!"
set /a "A1=VW*NH, A2=VH*NW, DF=A1-A2"
if !DF! LSS 0 set /a "DF=-DF"
set /a "TOL=A1/100"
if !DF! LEQ !TOL! (
    set "VF=scale=!NW!:!NH!,setsar=1"
    goto RES_RUN
)
:RES_ASPECT
echo(
echo   Пропорции отличаются. Исходник !VW!x!VH!, новый размер !NW!x!NH!.
echo   Что сделать с пропорциями?
echo(
echo   1  Растянуть - картинка будет искажена
echo   2  Вписать по центру - пустое место будет черным
echo   3  Обрезать лишнее - кадр заполнится полностью
echo(
echo   0  Назад
echo(
set "CH="
set /p "CH=  Выбор: "
call :TRIMVAR CH
if "!CH!"=="0" goto RES
if "!CH!"=="1" set "VF=scale=!NW!:!NH!,setsar=1" & goto RES_RUN
if "!CH!"=="2" set "VF=scale=!NW!:!NH!:force_original_aspect_ratio=decrease,pad=!NW!:!NH!:(ow-iw)/2:(oh-ih)/2:black,setsar=1" & goto RES_RUN
if "!CH!"=="3" set "VF=scale=!NW!:!NH!:force_original_aspect_ratio=increase,crop=!NW!:!NH!,setsar=1" & goto RES_RUN
goto RES_ASPECT

:RES_RUN
if "!IS_IMG!"=="1" goto RES_IMG
set "CRF=18" & set "FIXEXT=0"
call :SETVIDEO
set "OEXT=!VEXT!"
call :MAKEOUT
set "ACT=Меняю разрешение..."
set "FFARGS=-i "!INPUT!" -map 0:v:0 -map 0:a? -vf "!VF!" !VENC! !AKEEP! "!OUT!""
call :RUN
goto MAIN


:RES_PCT
set "VF=scale=trunc(iw*!PCT!/100):trunc(ih*!PCT!/100)"
set "OSUF=_!PCT!pct"
goto RES_RUN

:RES_IMG
set "VFX=!VF!"
if "!IS_ANIM!"=="1" (call :SETANIM) else call :SETIMGOUT
call :MAKEOUT
set "ACT=Меняю разрешение..."
set "FFARGS=-i "!INPUT!" !COPTS! "!OUT!""
call :RUN
goto MAIN


rem ============================================================================
rem  6. СКОРОСТЬ
rem ============================================================================
:SPEED
call :HEADER
echo   СКОРОСТЬ
echo(
echo   1  x0.5    в 2 раза медленнее
echo   2  x0.75
echo   3  x1.25
echo   4  x1.5
echo   5  x2      в 2 раза быстрее
echo   6  x3
echo   7  x4
echo   8  Свое значение, от 0.25 до 4
echo(
echo   0  Назад
echo(
set "CH="
set /p "CH=  Выбор: "
call :TRIMVAR CH
if "!CH!"=="0" goto MAIN
if "!CH!"=="8" goto SPEED_CUSTOM
set "SP100="
if "!CH!"=="1" set "SP100=50"
if "!CH!"=="2" set "SP100=75"
if "!CH!"=="3" set "SP100=125"
if "!CH!"=="4" set "SP100=150"
if "!CH!"=="5" set "SP100=200"
if "!CH!"=="6" set "SP100=300"
if "!CH!"=="7" set "SP100=400"
if not defined SP100 goto SPEED
goto SPEED_RUN

:SPEED_CUSTOM
set "AD_PROMPT=  Во сколько раз изменить скорость, от 0.25 до 4, например 1.75, b = назад:"
set "AD_MIN=25" & set "AD_MAX=400"
call :ASKDEC
if /i "!NUM100!"=="b" goto SPEED
set "SP100=!NUM100!"

:SPEED_RUN
set /a "SI=SP100/100, SF=SP100%%100+100"
set "SPTXT=!SI!.!SF:~1!"
rem atempo понимает только 0.5 - 2.0, поэтому вне диапазона делаем цепочку
set /a "T=SP100*10"
if !T! LSS 500 (
    set /a "T2=T*2"
    call :FMT3 !T2!
    set "AF=atempo=0.5,atempo=!FS!"
) else if !T! GTR 2000 (
    set /a "T2=T/2"
    call :FMT3 !T2!
    set "AF=atempo=2.0,atempo=!FS!"
) else (
    call :FMT3 !T!
    set "AF=atempo=!FS!"
)
set "OSUF=_x!SPTXT!"
set "MT_SPEED=!SPTXT!"
set "ACT=Меняю скорость..."
if "!IS_AUDIO!"=="1" goto SPEED_AUDIO
if "!IS_IMG!"=="1" goto SPEED_IMG
set "CRF=18" & set "FIXEXT=0"
call :SETVIDEO
set "OEXT=!VEXT!"
call :MAKEOUT
if "!HAS_AUDIO!"=="1" (
    set "FFARGS=-i "!INPUT!" -map 0:v:0 -map 0:a? -vf "setpts=PTS/!SPTXT!" -af "!AF!" !VENC! !VAENC! "!OUT!""
) else (
    set "FFARGS=-i "!INPUT!" -map 0:v:0 -vf "setpts=PTS/!SPTXT!" !VENC! "!OUT!""
)
call :RUN
goto MAIN

:SPEED_AUDIO
call :SETAUDIO
set "OEXT=!AEXT!"
call :MAKEOUT
set "FFARGS=-i "!INPUT!" -vn -af "!AF!" !AENC! "!OUT!""
call :RUN
goto MAIN


:SPEED_IMG
set "VFX=setpts=PTS/!SPTXT!"
call :SETANIM
call :MAKEOUT
set "FFARGS=-i "!INPUT!" !COPTS! "!OUT!""
call :RUN
goto MAIN


rem ============================================================================
rem  7. ПОВОРОТ / ОТЗЕРКАЛИВАНИЕ
rem ============================================================================
:ROTATE
call :HEADER
echo   ПОВОРОТ / ОТЗЕРКАЛИВАНИЕ
echo(
echo   1  Повернуть на 90 градусов по часовой
echo   2  Повернуть на 90 градусов против часовой
echo   3  Повернуть на 180 градусов
echo   4  Отзеркалить по горизонтали
echo   5  Отзеркалить по вертикали
echo(
echo   0  Назад
echo(
set "CH="
set /p "CH=  Выбор: "
call :TRIMVAR CH
if "!CH!"=="0" goto MAIN
set "VF="
if "!CH!"=="1" set "VF=transpose=1"    & set "OSUF=_rot90cw"
if "!CH!"=="2" set "VF=transpose=2"    & set "OSUF=_rot90ccw"
if "!CH!"=="3" set "VF=hflip,vflip"    & set "OSUF=_rot180"
if "!CH!"=="4" set "VF=hflip"          & set "OSUF=_mirrorH"
if "!CH!"=="5" set "VF=vflip"          & set "OSUF=_mirrorV"
if not defined VF goto ROTATE
if "!IS_IMG!"=="1" goto ROTATE_IMG
set "CRF=18" & set "FIXEXT=0"
call :SETVIDEO
set "OEXT=!VEXT!"
call :MAKEOUT
set "ACT=Применяю..."
set "FFARGS=-i "!INPUT!" -map 0:v:0 -map 0:a? -vf "!VF!" !VENC! !AKEEP! "!OUT!""
call :RUN
goto MAIN


:ROTATE_IMG
set "VFX=!VF!"
if "!IS_ANIM!"=="1" (call :SETANIM) else call :SETIMGOUT
call :MAKEOUT
set "ACT=Применяю..."
set "FFARGS=-i "!INPUT!" !COPTS! "!OUT!""
call :RUN
goto MAIN


rem ============================================================================
rem  8. ГРОМКОСТЬ
rem ============================================================================
:VOLUME
if "!HAS_AUDIO!"=="0" goto NOAUDIO
call :HEADER
echo   ГРОМКОСТЬ
echo(
echo   1  Авто - выровнять громкость автоматически
echo   2  Вручную - прибавить или убавить в дБ, например +3 или -5
echo(
echo   0  Назад
echo(
set "CH="
set /p "CH=  Выбор: "
call :TRIMVAR CH
if "!CH!"=="0" goto MAIN
if "!CH!"=="1" goto VOL_AUTO
if "!CH!"=="2" goto VOL_CUSTOM
goto VOLUME

:VOL_AUTO
set "AFV=loudnorm=I=-16:TP=-1.5:LRA=11"
set "AR=-ar 48000"
set "OSUF=_normalized"
goto VOL_RUN

:VOL_CUSTOM
set "VV="
set /p "VV=  На сколько дБ, например +3 или -5, b = назад: "
call :TRIMVAR VV
if /i "!VV!"=="b" goto VOLUME
set "VV=!VV:,=.!"
if "!VV!"=="" goto VOL_CUSTOM
for /f "delims=0123456789.+-" %%x in ("!VV!") do (
    echo   Неверное значение.
    goto VOL_CUSTOM
)
if "!VV:~0,1!"=="+" set "VV=!VV:~1!"
if "!VV!"=="" goto VOL_CUSTOM
set "AFV=volume=!VV!dB"
set "AR="
set "OSUF=_vol!VV!"

:VOL_RUN
set "ACT=Меняю громкость..."
if "!IS_AUDIO!"=="1" (
    call :SETAUDIO
    set "OEXT=!AEXT!"
    call :MAKEOUT
    set "FFARGS=-i "!INPUT!" -vn -af "!AFV!" !AR! !AENC! "!OUT!""
) else (
    set "FIXEXT=1" & set "CRF=18"
    call :SETVIDEO
    set "OEXT=!VEXT!"
    call :MAKEOUT
    set "FFARGS=-i "!INPUT!" -map 0:v:0 -map 0:a? -c:v copy -af "!AFV!" !AR! !VAENC! "!OUT!""
)
call :RUN
goto MAIN


rem ============================================================================
rem  СООБЩЕНИЯ И ВЫХОД
rem ============================================================================
:NOVIDEO
echo(
echo   Это действие или формат недоступны для такого файла.
call :WAIT
goto MAIN

:NOAUDIO
echo(
echo   В этом файле нет звуковой дорожки.
call :WAIT
goto MAIN

:NOSTATIC2VIDEO
echo(
echo   Из обычной (не анимированной) картинки видео не делаю.
call :WAIT
goto MAIN

:NOAUDIOIMG
echo(
echo   У картинки нет звука, в аудио формат ее не конвертировать.
call :WAIT
goto MAIN

:NOIMGFROMAUDIO
echo(
echo   Из аудиофайла картинку сделать нельзя.
call :WAIT
goto MAIN

:NODIMS
echo(
echo   Не удалось определить размер кадра этого файла.
call :WAIT
goto MAIN

:EXIT
exit /b 0

:NOARG
echo(
echo   Не передан файл. Запускай через ПКМ по файлу
echo   или перетащи файл на этот .bat
echo(
pause
exit /b 1

:NOFILE
echo(
echo   Файл не найден.
echo(
pause
exit /b 1

:NOFFMPEG
echo(
echo   Не найден ffmpeg или ffprobe.
echo   Скачай ffmpeg и добавь папку bin в переменную PATH.
echo(
pause
exit /b 1

:NOPS
echo(
echo   Не найден PowerShell, он нужен для шкалы прогресса.
echo   В Windows 10 и 11 он встроен.
echo(
pause
exit /b 1

:NOMEDIA
echo(
echo   Не удалось прочитать файл как видео, аудио или картинку.
echo(
pause
exit /b 1


rem ============================================================================
rem  ПОДПРОГРАММЫ
rem ============================================================================

rem --- Запуск ffmpeg со шкалой прогресса. Вход: ACT, FFARGS, OUT. Опционально MT_SS, MT_TO, MT_SPEED ---
:RUN
call :HEADER
echo   !ACT!
echo(
set "MT_ARGS=!FFARGS!"
set "MT_IN=!INPUT!"
set "MT_OUTF=!OUT!"
set "MT_DUR=!F_duration!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:MT_SELF,[Text.Encoding]::UTF8); Invoke-Expression $t.Substring($t.LastIndexOf('#'+'PSCODE'))"
set "RC=!ERRORLEVEL!"
set "MT_SS=" & set "MT_TO=" & set "MT_SPEED="
echo(
if "!RC!"=="0" (
    echo   Сохранено: !OUT!
) else (
    if exist "!OUT!" del "!OUT!"
)
call :WAIT
exit /b

:WAIT
echo(
echo   Нажми любую клавишу, чтобы вернуться в меню...
pause >nul
exit /b

rem --- Сбор информации о файле (один раз при запуске) ---
:INFO
set "IS_AUDIO=0" & set "HAS_AUDIO=0" & set "BADFILE=0"
set "IS_IMG=0" & set "IS_ANIM=0" & set "FRAMES=" & set "IMG1=-frames:v 1 -update 1"
set "V_codec_name=" & set "V_width=" & set "V_height=" & set "V_avg_frame_rate=" & set "V_r_frame_rate="
set "A_codec_name=" & set "A_channels=" & set "A_sample_rate="
set "F_duration=" & set "F_bit_rate="
set "AX=!IN_EXT:~1!"
for %%E in (mp3 wav flac aac m4a ogg opus wma aif aiff mka) do if /i "!AX!"=="%%E" set "IS_AUDIO=1"
for %%E in (jpg jpeg jpe jfif png apng gif bmp webp tif tiff ico avif heic heif jxl tga dds exr ppm pgm pbm pnm) do if /i "!AX!"=="%%E" set "IS_IMG=1"
for /f "usebackq tokens=1,* delims==" %%a in (`ffprobe -v error -select_streams v:0 -show_entries "stream=codec_name,width,height,avg_frame_rate,r_frame_rate" -of "default=nw=1" "!INPUT!" 2^>nul`) do set "V_%%a=%%b"
for /f "usebackq tokens=1,* delims==" %%a in (`ffprobe -v error -select_streams a:0 -show_entries "stream=codec_name,channels,sample_rate" -of "default=nw=1" "!INPUT!" 2^>nul`) do set "A_%%a=%%b"
for /f "usebackq tokens=1,* delims==" %%a in (`ffprobe -v error -show_entries "format=duration,bit_rate" -of "default=nw=1" "!INPUT!" 2^>nul`) do set "F_%%a=%%b"
if not defined V_codec_name if not defined A_codec_name set "BADFILE=1"
if not defined V_codec_name set "IS_AUDIO=1"
if defined A_codec_name set "HAS_AUDIO=1"
if "!IS_IMG!"=="1" set "IS_AUDIO=0"
if "!IS_IMG!"=="1" if "!BADFILE!"=="0" call :ANIMCHK
set "VW=!V_width!"
set "VH=!V_height!"
set "TYPE=Видео"
if "!IS_AUDIO!"=="1" set "TYPE=Аудио"
if "!IS_IMG!"=="1" set "TYPE=Картинка"
if "!IS_ANIM!"=="1" set "TYPE=Анимация, кадров: !FRAMES!"
rem что умеет этот тип файла (из этого строится главное меню)
set "CAN_TRIM=1" & set "CAN_MUTE=1" & set "CAN_RES=1" & set "CAN_SPEED=1" & set "CAN_ROT=1" & set "CAN_VOL=1"
if "!IS_AUDIO!"=="1" set "CAN_MUTE=0" & set "CAN_RES=0" & set "CAN_ROT=0"
if "!IS_IMG!"=="1" set "CAN_MUTE=0" & set "CAN_VOL=0"
if "!IS_IMG!"=="1" if "!IS_ANIM!"=="0" set "CAN_TRIM=0" & set "CAN_SPEED=0"

rem размер (примерно в МБ, без переполнения set /a)
set "SZT=!IN_SIZE!"
if "!SZT:~6!"=="" (
    set /a "SZK=IN_SIZE/1024"
    set "SZTXT=!SZK! КБ"
) else (
    set "SZTXT=!SZT:~0,-6! МБ"
)

rem длительность
set "DURTXT=?"
if defined F_duration if not "!F_duration!"=="N/A" (
    for /f "tokens=1 delims=." %%a in ("!F_duration!") do set "DUR_S=%%a"
    set /a "DUR_H=DUR_S/3600, DUR_M=(DUR_S%%3600)/60, DUR_X=DUR_S%%60"
    set "DUR_H=0!DUR_H!"
    set "DUR_M=0!DUR_M!"
    set "DUR_X=0!DUR_X!"
    set "DURTXT=!DUR_H:~-2!:!DUR_M:~-2!:!DUR_X:~-2!"
)

rem FPS: берем номинальный r_frame_rate. avg_frame_rate у записей экрана с переменным FPS сильно занижен
set "FPST=?"
call :FRAC100 "!V_r_frame_rate!"
set "RR100=!F100!"
call :FRAC100 "!V_avg_frame_rate!"
set "AR100=!F100!"
set "FB100=!RR100!"
if !FB100! EQU 0 set "FB100=!AR100!"
if !FB100! GTR 24000 set "FB100=!AR100!"
if !FB100! GTR 0 (
    set /a "FRI=FB100/100, FRF=FB100%%100+100"
    set "FPST=!FRI!.!FRF:~1! fps"
    if "!FRF:~1!"=="00" set "FPST=!FRI! fps"
    set /a "CHK=AR100*100/FB100"
    if !CHK! LSS 80 set "FPST=!FPST!, переменный"
)

rem аудио и битрейт
set "ATXT=нет"
if "!HAS_AUDIO!"=="1" set "ATXT=!A_codec_name!, !A_channels! кан., !A_sample_rate! Гц"
set "BRTXT=?"
if defined F_bit_rate if not "!F_bit_rate!"=="N/A" (
    set /a "BRK=F_bit_rate/1000"
    set "BRTXT=!BRK! кбит/с"
)
exit /b

rem --- Дробь вида 30000/1001 в сотые доли: 2997. Вход: %1. Выход: F100 ---
:FRAC100
set "F100=0" & set "FRN=" & set "FRD="
for /f "tokens=1,2 delims=/" %%a in ("%~1") do (
    set "FRN=%%a"
    set "FRD=%%b"
)
if defined FRN if defined FRD if not "!FRD!"=="0" set /a "F100=FRN*100/FRD"
exit /b

rem --- Шапка с информацией о файле ---
:HEADER
cls
echo ============================================================
echo   MEDIA TOOL
echo ============================================================
echo   Файл:      !IN_NAME!!IN_EXT!
if "!IS_IMG!"=="1" goto HEADER_IMG
echo   Тип:       !TYPE!      Размер: !SZTXT!      Длительность: !DURTXT!
if "!IS_AUDIO!"=="0" echo   Видео:     !VW!x!VH!      !FPST!      !V_codec_name!
echo   Аудио:     !ATXT!
echo   Битрейт:   !BRTXT!
goto HEADER_END
:HEADER_IMG
echo   Тип:       !TYPE!      Размер: !SZTXT!
echo   Картинка:  !VW!x!VH!      !V_codec_name!
if "!IS_ANIM!"=="1" echo   Длительность: !DURTXT!
:HEADER_END
echo ------------------------------------------------------------
echo(
exit /b

rem --- Убрать пробелы по краям у переменной с именем %1 ---
:TRIMVAR
for /f "tokens=* delims= " %%a in ("!%~1!") do set "%~1=%%a"
:TRIMVAR_T
if not defined %~1 exit /b
if not "!%~1:~-1!"==" " exit /b
set "%~1=!%~1:~0,-1!"
goto TRIMVAR_T

rem --- Подбор имени выходного файла: IN_DIR + IN_NAME + OSUF + . + OEXT, без перезаписи ---
:MAKEOUT
set "OUT=!IN_DIR!!IN_NAME!!OSUF!.!OEXT!"
if not exist "!OUT!" exit /b
set "N=1"
:MAKEOUT_LOOP
set /a "N+=1"
set "OUT=!IN_DIR!!IN_NAME!!OSUF!_!N!.!OEXT!"
if exist "!OUT!" goto MAKEOUT_LOOP
exit /b

rem --- Кодеки для видео. Вход: CRF, FIXEXT (1 = оставить контейнер исходника) ---
rem     Выход: VEXT, VENC, VAENC (перекодировать звук), AKEEP (копировать звук, если контейнер не изменился)
:SETVIDEO
set "AX=!IN_EXT:~1!"
set "VEXT=mp4"
for %%E in (mp4 mkv mov avi webm m4v) do if /i "!AX!"=="%%E" set "VEXT=%%E"
if "!FIXEXT!"=="1" set "VEXT=!AX!"
if /i "!VEXT!"=="webm" (
    set "VENC=-c:v libvpx-vp9 -crf !CRF! -b:v 0 -row-mt 1 -deadline good -cpu-used 4"
    set "VAENC=-c:a libopus -b:a 160k"
) else (
    set "VENC=-c:v libx264 -crf !CRF! -preset medium -pix_fmt yuv420p"
    set "VAENC=-c:a aac -b:a 192k"
)
if /i "!VEXT!"=="avi" set "VAENC=-c:a libmp3lame -q:a 2"
set "AKEEP=-c:a copy"
if /i not "!VEXT!"=="!AX!" set "AKEEP=!VAENC!"
exit /b

rem --- Кодеки для аудио. Вход: ABR (кбит/с, можно пусто), LOSSY (1 = только форматы с потерей) ---
rem     Выход: AEXT, AENC
:SETAUDIO
set "AX=!IN_EXT:~1!"
set "ALIST=mp3 m4a aac ogg opus flac wav"
if "!LOSSY!"=="1" set "ALIST=mp3 m4a aac ogg opus"
set "AEXT=mp3"
for %%E in (!ALIST!) do if /i "!AX!"=="%%E" set "AEXT=%%E"
set "AENC=-c:a libmp3lame -q:a 2"
if /i "!AEXT!"=="mp3"  set "AENC=-c:a libmp3lame -q:a 2" & if defined ABR set "AENC=-c:a libmp3lame -b:a !ABR!k"
if /i "!AEXT!"=="m4a"  set "AENC=-c:a aac -b:a 256k" & if defined ABR set "AENC=-c:a aac -b:a !ABR!k"
if /i "!AEXT!"=="aac"  set "AENC=-c:a aac -b:a 256k" & if defined ABR set "AENC=-c:a aac -b:a !ABR!k"
if /i "!AEXT!"=="ogg"  set "AENC=-c:a libvorbis -q:a 6" & if defined ABR set "AENC=-c:a libvorbis -b:a !ABR!k"
if /i "!AEXT!"=="opus" set "AENC=-c:a libopus -b:a 160k" & if defined ABR set "AENC=-c:a libopus -b:a !ABR!k"
if /i "!AEXT!"=="flac" set "AENC=-c:a flac -compression_level 8"
if /i "!AEXT!"=="wav"  set "AENC=-c:a pcm_s16le"
exit /b

rem --- Ввод целого числа. Вход: AI_PROMPT, AI_MIN, AI_MAX. Выход: NUM (или b = назад) ---
:ASKINT
set "NUM="
set /p "NUM=!AI_PROMPT! "
call :TRIMVAR NUM
if /i "!NUM!"=="b" exit /b
if "!NUM!"=="" goto ASKINT_BAD
for /f "delims=0123456789" %%x in ("!NUM!") do goto ASKINT_BAD
if not "!NUM:~6!"=="" goto ASKINT_BAD
:ASKINT_Z
if "!NUM:~0,1!"=="0" if not "!NUM!"=="0" set "NUM=!NUM:~1!" & goto ASKINT_Z
if !NUM! LSS !AI_MIN! goto ASKINT_BAD
if !NUM! GTR !AI_MAX! goto ASKINT_BAD
exit /b
:ASKINT_BAD
echo   Неверное значение, попробуй еще раз.
goto ASKINT

rem --- Ввод дробного числа. Вход: AD_PROMPT, AD_MIN, AD_MAX (в сотых долях).
rem     Выход: NUM100 (сотые доли, или b = назад) и DECTXT (например 1.75) ---
:ASKDEC
set "DT="
set /p "DT=!AD_PROMPT! "
call :TRIMVAR DT
if /i "!DT!"=="b" (
    set "NUM100=b"
    exit /b
)
set "DT=!DT:,=.!"
if "!DT!"=="" goto ASKDEC_BAD
for /f "delims=0123456789." %%x in ("!DT!") do goto ASKDEC_BAD
if "!DT:~0,1!"=="." set "DT=0!DT!"
set "DIP=" & set "DFR=" & set "DXX="
for /f "tokens=1,2,* delims=." %%a in ("!DT!") do (
    set "DIP=%%a"
    set "DFR=%%b"
    set "DXX=%%c"
)
if defined DXX goto ASKDEC_BAD
if not defined DIP goto ASKDEC_BAD
if not "!DIP:~3!"=="" goto ASKDEC_BAD
set "DIP=00!DIP!"
set "DIP=!DIP:~-3!"
set "DFR=!DFR!00"
set "DFR=!DFR:~0,2!"
set /a "NUM100=(1!DIP!-1000)*100+(1!DFR!-100)"
if !NUM100! LSS !AD_MIN! goto ASKDEC_BAD
if !NUM100! GTR !AD_MAX! goto ASKDEC_BAD
set /a "DI=NUM100/100, DF=NUM100%%100+100"
set "DECTXT=!DI!.!DF:~1!"
exit /b
:ASKDEC_BAD
echo   Неверное значение, попробуй еще раз.
goto ASKDEC

rem --- Число в тысячных долях в текст: 1250 -> 1.250 ---
:FMT3
set "FT=%~1"
set /a "FI=FT/1000, FF3=FT%%1000+1000"
set "FS=!FI!.!FF3:~1!"
exit /b

rem --- Проверка анимации у картинки (gif, png, webp, avif): считаем кадры ---
:ANIMCHK
set "FRAMES="
for %%E in (gif png apng webp avif) do if /i "!AX!"=="%%E" call :COUNTFRAMES
if defined FRAMES for /f "delims=0123456789" %%x in ("!FRAMES!") do set "FRAMES="
if defined FRAMES if !FRAMES! GTR 1 set "IS_ANIM=1"
exit /b
:COUNTFRAMES
for /f "usebackq tokens=1,* delims==" %%a in (`ffprobe -v error -count_frames -select_streams v:0 -show_entries "stream=nb_read_frames" -of "default=nw=1" "!INPUT!" 2^>nul`) do set "FRAMES=%%b"
exit /b

rem --- Добавить пункт в главное меню. Вход: %1 текст, %2 метка перехода ---
:ADDM
set /a "MN+=1"
set "ML!MN!=%~1"
set "MG!MN!=%~2"
exit /b

rem --- Вывод списка форматов по 4 в строке с продолжением нумерации. Вход: LIST, LCOUNT ---
:SHOWLIST
set "ROW=" & set "RC=0"
for %%E in (!LIST!) do (
    set /a "LCOUNT+=1, RC+=1"
    set "NN=   !LCOUNT!"
    set "NM=%%E         "
    set "ROW=!ROW!!NN:~-3!  !NM:~0,7!"
    if !RC! GEQ 4 (
        echo   !ROW!
        set "ROW=" & set "RC=0"
    )
)
if defined ROW echo   !ROW!
exit /b

rem --- Параметры ffmpeg для выбранного формата. Вход: EXTX. Выход: OEXT, COPTS, KIND (V видео, A аудио, I картинка, G gif из видео) ---
:SETFMT
set "OEXT=!EXTX!" & set "COPTS=" & set "KIND="
set "X264=-c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p"
set "GVF=split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse"
set "ICOVF=scale=w='min(256,iw)':h='min(256,ih)':force_original_aspect_ratio=decrease"
set "EVEN=scale=trunc(iw/2)*2:trunc(ih/2)*2"
rem ---- видео ----
if /i "!EXTX!"=="mp4"  set "KIND=V" & set "COPTS=!X264! -c:a aac -b:a 192k -movflags +faststart"
if /i "!EXTX!"=="m4v"  set "KIND=V" & set "COPTS=!X264! -c:a aac -b:a 192k -movflags +faststart"
if /i "!EXTX!"=="mov"  set "KIND=V" & set "COPTS=!X264! -c:a aac -b:a 192k -movflags +faststart"
if /i "!EXTX!"=="mkv"  set "KIND=V" & set "COPTS=!X264! -c:a aac -b:a 192k"
if /i "!EXTX!"=="ts"   set "KIND=V" & set "COPTS=!X264! -c:a aac -b:a 192k"
if /i "!EXTX!"=="3gp"  set "KIND=V" & set "COPTS=!X264! -c:a aac -b:a 128k"
if /i "!EXTX!"=="avi"  set "KIND=V" & set "COPTS=!X264! -c:a libmp3lame -q:a 2"
if /i "!EXTX!"=="webm" set "KIND=V" & set "COPTS=-c:v libvpx-vp9 -crf 28 -b:v 0 -row-mt 1 -deadline good -cpu-used 4 -c:a libopus -b:a 160k"
if /i "!EXTX!"=="wmv"  set "KIND=V" & set "COPTS=-c:v wmv2 -q:v 3 -c:a wmav2 -b:a 192k"
if /i "!EXTX!"=="flv"  set "KIND=V" & set "COPTS=-c:v flv -q:v 3 -c:a aac -b:a 192k"
if /i "!EXTX!"=="mpg"  set "KIND=V" & set "COPTS=-c:v mpeg2video -q:v 3 -c:a mp2 -b:a 192k"
if /i "!EXTX!"=="mpeg" set "KIND=V" & set "COPTS=-c:v mpeg2video -q:v 3 -c:a mp2 -b:a 192k"
if /i "!EXTX!"=="ogv"  set "KIND=V" & set "COPTS=-c:v libtheora -q:v 7 -c:a libvorbis -q:a 5"
rem ---- аудио ----
if /i "!EXTX!"=="mp3"  set "KIND=A" & set "COPTS=-vn -c:a libmp3lame -q:a 2"
if /i "!EXTX!"=="wav"  set "KIND=A" & set "COPTS=-vn -c:a pcm_s16le"
if /i "!EXTX!"=="flac" set "KIND=A" & set "COPTS=-vn -c:a flac -compression_level 8"
if /i "!EXTX!"=="m4a"  set "KIND=A" & set "COPTS=-vn -c:a aac -b:a 256k"
if /i "!EXTX!"=="aac"  set "KIND=A" & set "COPTS=-vn -c:a aac -b:a 256k"
if /i "!EXTX!"=="ogg"  set "KIND=A" & set "COPTS=-vn -c:a libvorbis -q:a 6"
if /i "!EXTX!"=="opus" set "KIND=A" & set "COPTS=-vn -c:a libopus -b:a 160k"
if /i "!EXTX!"=="wma"  set "KIND=A" & set "COPTS=-vn -c:a wmav2 -b:a 192k"
if /i "!EXTX!"=="aiff" set "KIND=A" & set "COPTS=-vn -c:a pcm_s16be"
if /i "!EXTX!"=="ac3"  set "KIND=A" & set "COPTS=-vn -c:a ac3 -b:a 192k"
if /i "!EXTX!"=="mka"  set "KIND=A" & set "COPTS=-vn -c:a libopus -b:a 160k"
if /i "!EXTX!"=="mp2"  set "KIND=A" & set "COPTS=-vn -c:a mp2 -b:a 192k"
if /i "!EXTX!"=="wv"   set "KIND=A" & set "COPTS=-vn -c:a wavpack"
for %%E in (oga amr au caf dts eac3 spx ra m4b m4r aif aifc 3ga weba tta) do if /i "!EXTX!"=="%%E" set "KIND=A" & set "COPTS=-vn"
rem ---- картинки ----
for %%E in (jpg jpeg jpe) do if /i "!EXTX!"=="%%E" set "KIND=I" & set "COPTS=-q:v 2 !IMG1!"
for %%E in (png bmp tif tiff tga ppm pgm pbm pnm jp2 pcx sgi xbm) do if /i "!EXTX!"=="%%E" set "KIND=I" & set "COPTS=!IMG1!"
if /i "!EXTX!"=="webp" set "KIND=I" & set "COPTS=-c:v libwebp -q:v 90 -frames:v 1"
if /i "!EXTX!"=="webp" if "!IS_ANIM!"=="1" set "COPTS=-c:v libwebp -q:v 80 -loop 0"
if /i "!EXTX!"=="apng" set "KIND=I" & set "COPTS=-f apng -plays 0"
if /i "!EXTX!"=="ico"  set "KIND=I" & set "COPTS=-vf "!ICOVF!" -frames:v 1"
if /i "!EXTX!"=="avif" set "KIND=I" & set "COPTS=-c:v libaom-av1 -crf 30 -b:v 0 -cpu-used 6 -frames:v 1"
rem ---- gif: из видео своя ветка с вопросами, из картинки обычная ----
if /i "!EXTX!"=="gif" set "KIND=G"
if /i "!EXTX!"=="gif" if "!IS_IMG!"=="1" set "KIND=I" & set "COPTS=-frames:v 1"
if /i "!EXTX!"=="gif" if "!IS_ANIM!"=="1" set "COPTS=-vf "!GVF!" -loop 0"
rem ---- неизвестное расширение: пусть ffmpeg сам выберет кодеки ----
if defined KIND goto SETFMT_SRC
if "!IS_AUDIO!"=="1" set "KIND=A" & set "COPTS=-vn"
if "!IS_IMG!"=="1" set "KIND=I" & set "COPTS=-frames:v 1"
if not defined KIND set "KIND=V" & set "COPTS="
:SETFMT_SRC
if "!KIND!"=="V" if "!IS_IMG!"=="0" set "COPTS=-map 0:v:0 -map 0:a? !COPTS!"
if "!KIND!"=="V" if "!IS_IMG!"=="1" set "COPTS=-map 0:v:0 -vf "!EVEN!" -an !COPTS!"
exit /b

rem --- Анимированная картинка: формат на выходе. Вход: VFX (фильтры, можно пусто). Выход: OEXT, COPTS ---
:SETANIM
set "AX=!IN_EXT:~1!"
set "OEXT=webp"
set "COPTS=-c:v libwebp -q:v 85 -loop 0"
if defined VFX set "COPTS=-vf "!VFX!" -c:v libwebp -q:v 85 -loop 0"
if /i "!AX!"=="gif" call :ANIM_GIF
if /i "!AX!"=="png" call :ANIM_APNG
if /i "!AX!"=="apng" call :ANIM_APNG
exit /b
:ANIM_GIF
set "OEXT=gif"
set "GVF=split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse"
if defined VFX set "GVF=!VFX!,!GVF!"
set "COPTS=-vf "!GVF!" -loop 0"
exit /b
:ANIM_APNG
set "OEXT=apng"
set "COPTS=-f apng -plays 0"
if defined VFX set "COPTS=-vf "!VFX!" -f apng -plays 0"
exit /b

rem --- Обычная картинка: тот же формат на выходе. Вход: VFX (можно пусто). Выход: OEXT, COPTS ---
:SETIMGOUT
set "AX=!IN_EXT:~1!"
set "OEXT=png" & set "IMENC=!IMG1!"
for %%E in (jpg jpeg jpe jfif) do if /i "!AX!"=="%%E" set "OEXT=jpg" & set "IMENC=-q:v 2 !IMG1!"
for %%E in (bmp tga ppm pgm pbm pnm) do if /i "!AX!"=="%%E" set "OEXT=%%E" & set "IMENC=!IMG1!"
for %%E in (tif tiff) do if /i "!AX!"=="%%E" set "OEXT=tiff" & set "IMENC=!IMG1!"
if /i "!AX!"=="webp" set "OEXT=webp" & set "IMENC=-c:v libwebp -q:v 90 -frames:v 1"
if /i "!AX!"=="gif"  set "OEXT=gif" & set "IMENC=-frames:v 1"
if /i "!AX!"=="avif" set "OEXT=avif" & set "IMENC=-c:v libaom-av1 -crf 25 -b:v 0 -cpu-used 6 -frames:v 1"
set "COPTS=!IMENC!"
if defined VFX set "COPTS=-vf "!VFX!" !IMENC!"
exit /b

rem --- Сжатие картинки. Вход: Q (1-100), LL (1 = без потерь). Выход: OEXT, COPTS ---
:CIMGENC
set "AX=!IN_EXT:~1!"
set /a "QV=(100-Q)*29/100+2, CR=(100-Q)*45/100+10"
set "KIND2=other"
for %%E in (jpg jpeg jpe jfif) do if /i "!AX!"=="%%E" set "KIND2=jpg"
if /i "!AX!"=="webp" set "KIND2=webp"
if /i "!AX!"=="avif" set "KIND2=avif"
if "!IS_ANIM!"=="1" goto CIMG_ANIM
if "!LL!"=="1" goto CIMG_LL
set "OEXT=webp" & set "COPTS=-c:v libwebp -q:v !Q! -frames:v 1"
if "!KIND2!"=="jpg"  set "OEXT=jpg" & set "COPTS=-q:v !QV! !IMG1!"
if "!KIND2!"=="avif" set "OEXT=avif" & set "COPTS=-c:v libaom-av1 -crf !CR! -b:v 0 -cpu-used 6 -frames:v 1"
exit /b
:CIMG_LL
set "OEXT=png" & set "COPTS=-compression_level 9 !IMG1!"
if "!KIND2!"=="webp" set "OEXT=webp" & set "COPTS=-c:v libwebp -lossless 1 -frames:v 1"
exit /b
:CIMG_ANIM
set "OEXT=webp"
set "COPTS=-c:v libwebp -q:v !Q! -loop 0"
if "!LL!"=="1" set "COPTS=-c:v libwebp -lossless 1 -loop 0"
exit /b

rem ============================================================================
rem  Дальше идет код PowerShell. Командный интерпретатор сюда никогда не доходит:
rem  выше в :FMT3 стоит exit /b. Код запускается из подпрограммы :RUN.
rem ============================================================================
exit /b

#PSCODE
$ErrorActionPreference = 'Stop'
$inv    = [Globalization.CultureInfo]::InvariantCulture
$prog   = Join-Path $env:TEMP ('mediatool_' + $PID + '.prg')
$proc   = $null
$reader = $null
$code   = 0

# "2:39" или "1:02:39" или "159.5" в секунды
function ToSec([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return 0.0 }
    $v = 0.0
    foreach ($x in $s.Trim().Split(':')) { $v = $v * 60 + [double]::Parse($x, $inv) }
    return $v
}

# секунды в 00:00:00
function Fmt([double]$sec) {
    if ([double]::IsNaN($sec) -or [double]::IsInfinity($sec) -or $sec -lt 0) { return '--:--:--' }
    $r = [long][math]::Round($sec)
    return ('{0:00}:{1:00}:{2:00}' -f [math]::Floor($r / 3600), [math]::Floor(($r % 3600) / 60), ($r % 60))
}

# байты в "79 МБ"
function SizeTxt([long]$b) {
    if ($b -ge 1GB)  { return ('{0:N1} ГБ' -f ($b / 1GB)) }
    if ($b -ge 10MB) { return ('{0:N0} МБ' -f ($b / 1MB)) }
    if ($b -ge 1MB)  { return ('{0:N1} МБ' -f ($b / 1MB)) }
    return ('{0:N0} КБ' -f ($b / 1KB))
}

# понятная причина ошибки по тексту ffmpeg
function Why([string]$e) {
    if ($e -match "Unknown encoder '([^']+)'")                 { return 'в этой сборке ffmpeg нет кодека ' + $Matches[1] }
    if ($e -match 'does not contain any stream')              { return 'в файле нет нужных дорожек' }
    if ($e -match 'smaller than -ss')                         { return 'конец обрезки раньше начала' }
    if ($e -match 'Permission denied')                        { return 'нет доступа на запись в эту папку' }
    if ($e -match 'No space left')                            { return 'на диске не хватает места' }
    if ($e -match 'already exists')                           { return 'выходной файл уже существует' }
    if ($e -match 'Invalid data found|moov atom not found|Error opening input') { return 'не удалось прочитать исходный файл, возможно он поврежден' }
    if ($e -match 'Invalid argument')                         { return 'ffmpeg не принял параметры для этого файла' }
    if ($e -match 'Unable to choose an output format|Unable to find a suitable output format') { return 'ffmpeg не знает такой формат, проверь расширение' }
    if ($e -match 'Could not find tag for codec|not currently supported in container') { return 'этот формат не поддерживает нужный кодек, выбери другой' }
    return ''
}

try {
    # сколько секунд должен получиться результат (для процентов)
    $total = 0.0
    try {
        if ($env:MT_DUR -and $env:MT_DUR -ne 'N/A') { $total = [double]::Parse($env:MT_DUR, $inv) }
        if ($env:MT_SS -or $env:MT_TO) {
            $a = ToSec $env:MT_SS
            $b = $total
            if ($env:MT_TO) { $b = ToSec $env:MT_TO }
            if ($total -gt 0 -and $b -gt $total) { $b = $total }
            $total = [math]::Max($b - $a, 0)
        }
        if ($env:MT_SPEED) {
            $sp = [double]::Parse($env:MT_SPEED, $inv)
            if ($sp -gt 0) { $total = $total / $sp }
        }
    } catch { $total = 0.0 }

    if (Test-Path -LiteralPath $prog) { Remove-Item -LiteralPath $prog -Force }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = 'ffmpeg'
    $psi.Arguments = '-hide_banner -loglevel error -nostdin -n -nostats -progress "' + $prog + '" ' + $env:MT_ARGS
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    $proc    = [System.Diagnostics.Process]::Start($psi)
    $errTask = $proc.StandardError.ReadToEndAsync()
    $sw      = [System.Diagnostics.Stopwatch]::StartNew()
    $cancel  = $false
    $done    = 0.0

    Write-Host '  Esc или Ctrl+C - отмена'
    Write-Host ''
    [Console]::TreatControlCAsInput = $true

    while (-not $proc.HasExited) {
        # клавиши: Esc или Ctrl+C = отмена
        try {
            while ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ($k.Key -eq 'Escape') { $cancel = $true }
                if ($k.Key -eq 'C' -and (($k.Modifiers -band [ConsoleModifiers]::Control) -ne 0)) { $cancel = $true }
            }
        } catch { }
        if ($cancel) { break }

        # сколько уже обработано (ffmpeg пишет out_time в файл прогресса)
        if ($reader -eq $null -and (Test-Path -LiteralPath $prog)) {
            $fs = New-Object System.IO.FileStream($prog, 'Open', 'Read', 'ReadWrite,Delete')
            $reader = New-Object System.IO.StreamReader($fs)
        }
        if ($reader -ne $null) {
            while (($line = $reader.ReadLine()) -ne $null) {
                if ($line.StartsWith('out_time=')) {
                    try { $done = ToSec ($line.Substring(9).Trim()) } catch { }
                }
            }
        }

        if ($total -gt 0) {
            $pct = [math]::Min([math]::Max($done / $total, 0.0), 1.0)
            $n   = [int][math]::Floor($pct * 24)
            $bar = ('#' * $n) + ('-' * (24 - $n))
            $el  = $sw.Elapsed.TotalSeconds
            if ($pct -ge 0.02 -and $el -ge 2) { $eta = Fmt ($el * (1 - $pct) / $pct) } else { $eta = 'считаю...' }
            $txt = ('  [{0}] {1,3}%   осталось ~{2}' -f $bar, [int][math]::Floor($pct * 100), $eta)
        } else {
            $txt = ('  Идет обработка...   прошло {0}' -f (Fmt $sw.Elapsed.TotalSeconds))
        }
        Write-Host -NoNewline ("`r" + $txt.PadRight(70))
        Start-Sleep -Milliseconds 400
    }

    if ($cancel) {
        try { $proc.Kill() } catch { }
        $proc.WaitForExit()
        Write-Host ''
        Write-Host ''
        Write-Host '  ОТМЕНЕНО. Незаконченный файл удален.'
        $code = 2
    } else {
        $proc.WaitForExit()
        $err = $errTask.Result
        if ($proc.ExitCode -eq 0) {
            Write-Host -NoNewline ("`r" + '  [########################] 100%   готово'.PadRight(70))
            Write-Host ''
            Write-Host ''
            $ins  = (Get-Item -LiteralPath $env:MT_IN).Length
            $outs = 0
            if (Test-Path -LiteralPath $env:MT_OUTF) { $outs = (Get-Item -LiteralPath $env:MT_OUTF).Length }
            Write-Host ('  ГОТОВО за {0}.   Размер: {1} -> {2}' -f (Fmt $sw.Elapsed.TotalSeconds), (SizeTxt $ins), (SizeTxt $outs))
        } else {
            Write-Host ''
            Write-Host ''
            Write-Host '  ОШИБКА. Файл не создан.'
            $lines = @($err -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
            $last  = ''
            if ($lines.Count -gt 0) { $last = $lines[$lines.Count - 1].Trim() }
            $why = Why $err
            if ($why -ne '') { Write-Host ('  Причина: ' + $why) }
            if ($last -ne '') {
                if ($last.Length -gt 110) { $last = $last.Substring(0, 110) + '...' }
                Write-Host ('  Ответ ffmpeg: ' + $last)
            }
            $code = 1
        }
    }
} catch {
    try { if ($proc -ne $null -and -not $proc.HasExited) { $proc.Kill() } } catch { }
    Write-Host ''
    Write-Host ('  ОШИБКА: ' + $_.Exception.Message)
    $code = 1
} finally {
    try { [Console]::TreatControlCAsInput = $false } catch { }
    if ($reader -ne $null) { try { $reader.Close() } catch { } }
    Remove-Item -LiteralPath $prog -Force -ErrorAction SilentlyContinue
}
exit $code

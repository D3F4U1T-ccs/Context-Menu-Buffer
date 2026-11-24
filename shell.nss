settings
{
    priority=1
    exclude.where = !process.is_explorer
    showdelay = 200
    modify.remove.duplicate=1
    tip.enabled=true
}

import 'imports/theme.nss'
import 'imports/images.nss'

// Всё остальное пока выключено: смотрим меню без переделок.
// import 'imports/modify.nss'
// import 'imports/terminal.nss'
// import 'imports/file-manage.nss'
// import 'imports/develop.nss'
// import 'imports/goto.nss'
// import 'imports/taskbar.nss'


// =====================================================
//  УБРАТЬ ИЗ МЕНЮ (для файлов, папок и дисков)
// =====================================================

// ---- По встроенным кодам (не зависят от языка) ----
modify(mode="multiple"
    where=this.id(
        id.add_to_favorites,
        id.give_access_to,
        id.share,
        id.restore_previous_versions,
        id.send_to,
        id.print,
        id.create_shortcut,
        id.include_in_library,
        id.cast_to_device)
    vis=vis.remove)

// ---- По названию ----
// Pin to taskbar (Pin to Start НЕ трогаем)
modify(mode="multiple" find="Pin to taskbar*|Unpin from taskbar*" vis=vis.remove)

// Defender
modify(mode="multiple" find="Scan with Microsoft Defender*" vis=vis.remove)

// Лишнее у exe
modify(mode="multiple" find="Troubleshoot compatibility" vis=vis.remove)

// Дубль File Locksmith (русский)
modify(mode="multiple" find="Разблокировать с помощью File Locksmith" vis=vis.remove)

// Rename (переименовываю клавишей F2)
modify(mode="multiple" find="*Rename*" vis=vis.remove)

// Найдено в папках
modify(mode="multiple" find="Git" vis=vis.remove)
modify(mode="multiple" find="Into" vis=vis.remove)
modify(mode="multiple" find="Media Player" vis=vis.remove)
modify(mode="multiple" find="ChatGPT" vis=vis.remove)
modify(mode="multiple" find="Quick access" vis=vis.remove)
modify(mode="multiple" find="плейлист" vis=vis.remove)


// ---------- МОИ УТИЛИТЫ ----------

// Кнопка только для видео и аудио
item(title="Media Tool"
    type="file"
    find=".mp4|.mkv|.avi|.mov|.webm|.wmv|.flv|.f4v|.m4v|.mpg|.mpeg|.mpe|.m2v|.ts|.mts|.m2ts|.m2t|.3gp|.3g2|.ogv|.vob|.divx|.asf|.rm|.rmvb|.mxf|.qt|.dv|.amv|.y4m|.wtv|.dvr-ms|.hevc|.h264|.h265|.264|.265|.mp3|.wav|.flac|.m4a|.aac|.ogg|.oga|.opus|.wma|.aiff|.aif|.aifc|.ape|.alac|.amr|.ac3|.eac3|.dts|.mka|.mp2|.m4b|.m4r|.wv|.tta|.au|.caf|.3ga|.ra|.spx|.weba|.mpc|.jpg|.jpeg|.jpe|.jfif|.png|.apng|.gif|.bmp|.webp|.tif|.tiff|.ico|.avif|.heic|.heif|.jxl|.tga|.dds|.exr|.ppm|.pgm|.pbm|.pnm"
    image='C:\Users\twiki\Desktop\Утилиты\Converterы\MediaTool.exe'
    cmd='"C:\Users\twiki\Desktop\Утилиты\Converterы\MediaTool.exe"'
    args='"@sel.path"'
    pos=1)

// Кнопка для папок
item(title="Folder Tool"
    type="dir"
    image='C:\Users\twiki\Desktop\Утилиты\Converterы\FolderTool.exe'
    cmd='"C:\Users\twiki\Desktop\Утилиты\Converterы\FolderTool.exe"'
    args='"@sel.path"'
    pos=1)
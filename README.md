# usb2can_automount
Repository with usb to can adapter automount utile

Как теперь использовать этот скрипт:
Скопируйте три файла в одной папке: install_slcan_scripts.sh, slcan_up.sh, slcan_down.sh и 99-slcan.rules.
Содержимое 99-slcan.rules также должно быть с плейсхолдерами , и <Serial_Number>. Сделайте install_slcan_scripts.sh исполняемым:

chmod +x install_slcan_scripts.sh

Запустите его с правами суперпользователя:

sudo ./install_slcan_scripts.sh

Скрипт проверит наличие всех трех вспомогательных файлов, скопирует их в нужные места, сделает скрипты исполняемыми и перезагрузит правила udev. После этого вам останется только отредактировать файл 99-slcan.rules, чтобы указать идентификаторы вашего устройства.

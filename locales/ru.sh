# shellcheck shell=bash

i18n_ru() {
  case "$1" in
    lang_saved) printf '%s' "Язык сохранён" ;;
    menu_title) printf '%s' "Proxy Stack" ;;
    menu_install) printf '%s' "Установка" ;;
    menu_status) printf '%s' "Статус" ;;
    menu_configure) printf '%s' "Настройка" ;;
    menu_tests) printf '%s' "Тесты" ;;
    menu_doctor) printf '%s' "Диагностика" ;;
    menu_credentials) printf '%s' "Учётные данные" ;;
    menu_firewall) printf '%s' "Файрвол" ;;
    menu_webhook) printf '%s' "Webhook Telegram" ;;
    menu_logs) printf '%s' "Журналы" ;;
    menu_backup) printf '%s' "Резервные копии" ;;
    menu_migration) printf '%s' "Миграция" ;;
    menu_update) printf '%s' "Обновление" ;;
    menu_uninstall) printf '%s' "Удаление" ;;
    menu_about) printf '%s' "О программе" ;;
    menu_exit) printf '%s' "Выход" ;;
    menu_select) printf '%s' "Выбор" ;;
    invalid_choice) printf '%s' "Неизвестный пункт" ;;
    press_enter) printf '%s' "Нажмите Enter" ;;
    cancelled) printf '%s' "Отменено" ;;
    root_required) printf '%s' "Нужны права root; запустите через sudo" ;;
    yes) printf '%s' "да" ;;
    no) printf '%s' "нет" ;;
    ask_components) printf '%s' "Компонент: 1 Dante  2 Squid  3 Caddy  4 Все" ;;
    ask_dante_user) printf '%s' "Имя пользователя Dante" ;;
    ask_dante_port) printf '%s' "Порт Dante" ;;
    ask_squid_user) printf '%s' "Имя пользователя Squid" ;;
    ask_squid_port) printf '%s' "Порт Squid" ;;
    ask_generate) printf '%s' "Сгенерировать надёжный пароль? 1 да, 2 свой" ;;
    ask_domain) printf '%s' "Публичный домен webhook" ;;
    ask_upstream) printf '%s' "URL upstream (scheme://host:port)" ;;
    ask_path) printf '%s' "Путь webhook" ;;
    ask_email) printf '%s' "Email ACME (необязательно)" ;;
    ask_save_secrets) printf '%s' "Сохранить пароли в файл только для root (doctor/rotate)?" ;;
    password_once) printf '%s' "Сохраните пароль сейчас. Он показывается один раз и не пишется в журнал." ;;
    password_mismatch) printf '%s' "Пароли не совпали" ;;
    pass_invalid) printf '%s' "Пароль: 8–128 символов, без пробелов и без ':'" ;;
    user_invalid) printf '%s' "Некорректное имя пользователя" ;;
    port_invalid) printf '%s' "Некорректный порт" ;;
    domain_invalid) printf '%s' "Некорректный домен" ;;
    upstream_invalid) printf '%s' "Некорректный URL upstream" ;;
    os_unsupported) printf '%s' "Установщик рассчитан на Ubuntu и Debian. Чтобы продолжить, укажите --force." ;;
    iface_missing) printf '%s' "Не удалось определить внешний интерфейс по маршруту по умолчанию." ;;
    validate_fail) printf '%s' "Проверка не пройдена; прежняя конфигурация сохранена" ;;
    health_fail) printf '%s' "Проверка работоспособности не пройдена" ;;
    rollback_ok) printf '%s' "Откат выполнен" ;;
    rollback_fail) printf '%s' "Откат не удался" ;;
    fw_profile) printf '%s' "Профиль: 1 Рекомендуемый (IP/CIDR)  2 Только VPN/LAN  3 Публичный с аутентификацией" ;;
    fw_cidr) printf '%s' "Разрешённый IP или CIDR источника" ;;
    fw_more_cidr) printf '%s' "Ещё один CIDR? Пустая строка — закончить" ;;
    fw_public_warn) printf '%s' "ВНИМАНИЕ: аутентификация не заменяет файрвол. Профиль 3 открывает порты прокси в Интернет." ;;
    fw_type_public) printf '%s' "Введите PUBLIC для подтверждения" ;;
    fw_plan) printf '%s' "План файрвола (SSH сохраняется; чужие правила не стираются)" ;;
    fw_confirm) printf '%s' "Применить этот план?" ;;
    fw_skip) printf '%s' "Обнаружена политика nftables или iptables. proxystack не будет её менять." ;;
    fw_applied) printf '%s' "Профиль файрвола применён" ;;
    fw_need_force) printf '%s' "Без --force в неинтерактивном режиме файрвол не меняется" ;;
    tg_token) printf '%s' "Токен бота Telegram (скрытый ввод, без сохранения, пока вы не согласитесь)" ;;
    tg_save) printf '%s' "Сохранить токен бота в файл только для root?" ;;
    tg_url) printf '%s' "URL webhook" ;;
    tg_via) printf '%s' "Доступ к API: 1 напрямую  2 локальный Squid  3 HTTP-прокси" ;;
    tg_set_ok) printf '%s' "Webhook обновлён" ;;
    tg_deleted) printf '%s' "Webhook удалён" ;;
    tg_missing) printf '%s' "Токен бота не задан" ;;
    wh_404) printf '%s' "Ответ 404 от Telegram обычно значит, что путь webhook не совпадает с приложением или Caddy не маршрутизирует /webhook/." ;;
    wh_502) printf '%s' "Ответ 502 от Telegram обычно значит, что upstream за Caddy ответил ошибкой. Запустите proxystack doctor." ;;
    wh_timeout) printf '%s' "Таймаут Telegram обычно значит, что пакеты не дошли до webhook или upstream не ответил." ;;
    bk_secrets_warn) printf '%s' "ВНИМАНИЕ: архив будет содержать секреты и будет зашифрован. Парольную фразу храните отдельно." ;;
    bk_passphrase) printf '%s' "Парольная фраза архива" ;;
    bk_created) printf '%s' "Резервная копия записана" ;;
    bk_restored) printf '%s' "Восстановление завершено" ;;
    bk_dns) printf '%s' "Обновите DNS: домен webhook должен указывать на текущий публичный IPv4, затем выполните proxystack doctor." ;;
    up_current) printf '%s' "Текущая версия" ;;
    up_latest) printf '%s' "Последняя версия" ;;
    up_notes) printf '%s' "Заметки о выпуске" ;;
    up_same) printf '%s' "Уже установлена последняя версия" ;;
    up_checksum_ok) printf '%s' "Контрольная сумма проверена" ;;
    up_checksum_fail) printf '%s' "Контрольная сумма не сошлась; обновление не установлено" ;;
    up_daemons) printf '%s' "Обновлены только файлы CLI. Dante, Squid и Caddy не перезапускались, их конфиги не менялись." ;;
    up_done) printf '%s' "Обновление CLI завершено" ;;
    up_download_fail) printf '%s' "Не удалось скачать проверенное обновление" ;;
    doc_passed) printf '%s' "Успешно" ;;
    doc_warnings) printf '%s' "Предупреждения" ;;
    doc_failed) printf '%s' "Ошибки" ;;
    doc_recs) printf '%s' "Рекомендации" ;;
    password_label_dante) printf '%s' "Пароль Dante (показан один раз)" ;;
    password_label_squid) printf '%s' "Пароль Squid (показан один раз)" ;;
    noninteractive_missing) printf '%s' "Не хватает значения. В неинтерактивном режиме передайте его флагом." ;;
    unknown_command) printf '%s' "Неизвестная команда. Запустите: proxystack help" ;;
    confirm_password) printf '%s' "Повторите пароль" ;;
    ask_custom_password) printf '%s' "Пароль" ;;
    *) printf '%s' "$1" ;;
  esac
}

i18n_ru_block() {
  case "$1" in
    help)
      cat <<'EOF'
proxystack — Установка и Диагностика: Dante SOCKS5, Squid HTTP CONNECT, Caddy и webhook Telegram

Использование:
  proxystack [глобальные флаги] <команда> [цель] [флаги]

Глобальные флаги:
  --non-interactive   Без вопросов
  --force             Применять изменения без второго подтверждения
  --json              Машиночитаемый вывод, где он поддерживается
  --verbose           Отладочный журнал со скрытыми секретами
  --quiet             Без информационных сообщений
  --lang en|ru        Язык
  --prefix PATH       Переносимый корень установки
  -h, --help          Справка

Команды:
  (без аргументов)          Интерактивное меню
  install [all|dante|squid|caddy]
  install-script            Установить только CLI
  uninstall-script          Удалить только CLI
  configure                 Перенастроить компонент
  status                    Сводка служб и портов
  doctor                    Последовательная диагностика
  test [all|dante|squid|caddy|webhook|upstream]
  logs [dante|squid|caddy]
  restart [dante|squid|caddy]
  credentials [rotate]
  firewall [status]
  webhook set|info|delete|test
  backup | restore | export | import
  update | update-script    Обновить только CLI
  uninstall [all|dante|squid|caddy]
  language [en|ru]
  version
EOF
      ;;
    about)
      cat <<'EOF'
proxystack управляет Dante, Squid и Caddy на Ubuntu/Debian.
Аутентификация прокси не заменяет файрвол.
Пароли и токены бота не попадают в диагностический журнал.
Лицензия: MIT
EOF
      ;;
    migration)
      cat <<'EOF'
Миграция
  1. На старом сервере: sudo proxystack export --output /root/proxystack-migrate.tar.gz
  2. Скопируйте архив на новый сервер.
  3. На новом сервере установите CLI и импортируйте архив:
       sudo proxystack install-script
       sudo proxystack import --file /root/proxystack-migrate.tar.gz
  4. Импорт определяет новый интерфейс и публичный IPv4, переписывает Dante и позволяет Caddy заново получить сертификат.
  5. Направьте DNS на новый IPv4 и выполните: sudo proxystack doctor
EOF
      ;;
    diag_not_caddy)
      cat <<'EOF'
DNS работает, маршрут есть, а TCP-соединение к upstream заканчивается timeout.
Проблема NOT Caddy. Вероятная причина: фильтрация source-IP, firewall, security group или сеть upstream.
EOF
      ;;
    *)
      return 1
      ;;
  esac
}

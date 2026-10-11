# proxystack

[![CI](https://github.com/driverm35/proxy-stack-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/driverm35/proxy-stack-cli/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/driverm35/proxy-stack-cli)](https://github.com/driverm35/proxy-stack-cli/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%7C%2024.04-E95420)](https://ubuntu.com/)
[![Debian](https://img.shields.io/badge/Debian-12%20%7C%2013-A81D33)](https://www.debian.org/)

**[English](README.md)** · **[Быстрый старт](#быстрый-старт)** · **[Команды](#команды)** · **[Диагностика](#диагностика)** · **[Миграция](#миграция)**

CLI для Ubuntu и Debian: SOCKS5 (Dante), HTTP CONNECT (Squid), обратный прокси Caddy и webhook Telegram. Язык интерфейса выбирается при первом запуске: `1` — русский, `2` — английский. Команда `proxystack language ru` переключает язык позже. Настройка хранится в `/etc/proxystack/config.env`.

Аутентификация на прокси не заменяет файрвол. Рекомендуемый профиль открывает порты прокси только с указанных адресов и не закрывает SSH.

```text
клиенты --SOCKS5--> Dante :51080 --+
клиенты --CONNECT--> Squid :51081 --+--> Интернет / API Telegram
                                    |
Telegram --> :443 Caddy /webhook/* -+--> ваш upstream
```

## Быстрый старт

```bash
bash <(curl -Ls https://raw.githubusercontent.com/driverm35/proxy-stack-cli/main/proxystack.sh) install-script
sudo proxystack
```

`install-script` ставит только команду. После установки откройте меню:

```bash
sudo proxystack
```

Если raw GitHub недоступен:

```bash
bash <(curl -Ls https://cdn.jsdelivr.net/gh/driverm35/proxy-stack-cli@main/proxystack.sh) install-script
```

## Установка

```bash
curl -fsSL https://raw.githubusercontent.com/driverm35/proxy-stack-cli/main/proxystack.sh | sudo bash -s -- install-script
sudo proxystack install dante
sudo proxystack install squid
sudo proxystack install caddy
sudo proxystack install all
```

Форма `bash <(curl ...)` оставляет stdin свободным для вопросов. Для автоматизации удобнее флаги:

```bash
sudo proxystack install all --non-interactive --force --lang ru \
  --dante-user socksuser --dante-password 'ExamplePassw0rd' \
  --squid-user httpproxy --squid-password 'ExamplePassw0rd' \
  --domain webhook.example.com \
  --upstream http://203.0.113.50:8080 \
  --webhook-path /webhook/ \
  --firewall-profile recommended \
  --allow-cidr 203.0.113.10/32
```

Пароль можно не указывать: он будет сгенерирован, показан один раз и не попадёт в журнал. Адреса в примерах — документационные (`example.com`, сеть `203.0.113.0/24`).

Повторная установка безопасна. Перед заменой конфига CLI делает копию с меткой времени, проверяет новый файл, перезапускает службу и откатывает её, если проверка не прошла.

## Интерактивное меню

```text
Proxy Stack 0.1.0
  1) Установка
  2) Статус
  3) Настройка
  4) Тесты
  5) Диагностика
  6) Учётные данные
  7) Файрвол
  8) Webhook Telegram
  9) Журналы
  10) Резервные копии
  11) Миграция
  12) Обновление
  13) Удаление
  14) О программе
  0) Выход
```

Цвет включается в терминале и не используется, если stdout не TTY.

## Команды

| Команда | Назначение |
| --- | --- |
| `proxystack` | Меню |
| `install [all\|dante\|squid\|caddy]` | Установка компонента или всего стека |
| `install-script` / `uninstall-script` | Только CLI |
| `configure` | Пересборка конфига с проверкой и откатом |
| `status` | Службы, порты, имена пользователей, домен |
| `doctor` | Последовательная диагностика |
| `test [all\|dante\|squid\|caddy\|webhook\|upstream]` | Живые пробы |
| `logs [dante\|squid\|caddy]` | Журналы |
| `restart [dante\|squid\|caddy]` | Перезапуск |
| `credentials [rotate]` | Имена пользователей и смена паролей |
| `firewall [status]` | Профиль доступа |
| `webhook set\|info\|delete\|test` | API webhook Telegram |
| `backup` / `restore` / `export` / `import` | Архивы и перенос |
| `update` / `update-script` | Обновление только CLI |
| `uninstall [all\|dante\|squid\|caddy]` | Удаление установленных компонентов |
| `language [en\|ru]` | Язык |
| `version` / `help` | Версия и справка |

Глобальные флаги: `--non-interactive`, `--force`, `--json`, `--verbose`, `--quiet`, `--lang`, `--prefix`.

## Dante

Порт по умолчанию `51080`, метод `username`, TCP и UDP (`udpassociate`). Внешний интерфейс берётся из маршрута по умолчанию, имя `eth0` не подставляется. Перед перезапуском выполняется `danted -V`. Затем идёт реальный запрос SOCKS5.

```bash
curl -sS --socks5-hostname 'socksuser:ExamplePassw0rd@203.0.113.10:51080' https://ifconfig.me/ip
```

## Squid

Порт по умолчанию `51081`. Ставятся `squid` и `apache2-utils`, пароль хранится хешем в `/etc/squid/passwords`. Перед применением конфиг проходит `squid -k parse`.

```bash
curl -sS -x 'http://httpproxy:ExamplePassw0rd@203.0.113.10:51081' https://ifconfig.me/ip
```

Успешный туннель выглядит как `HTTP/1.1 200 Connection established`. Doctor умеет сходить в API Telegram через локальный Squid, если пароль доступен.

## Caddy

Ставится официальная стабильная сборка. Вы указываете публичный домен webhook и URL upstream. В Caddyfile есть пути `/webhook/` и `/webhook/*`: запрос уходит на upstream с исходным путём, а заголовок `Host` равен хосту upstream. Сертификат Let's Encrypt запрашивается на 80/443. Каталог `/var/log/caddy` создаётся с владельцем `caddy:caddy`, чтобы не получить `permission denied`. Перед перезагрузкой выполняется `caddy validate`.

```bash
curl -sS -D - -o /dev/null -X POST \
  -H 'Content-Type: application/json' \
  --data '{"update_id":1,"message":{"message_id":1,"text":"proxystack-test"}}' \
  https://webhook.example.com/webhook/
```

## Webhook Telegram

Токен бота читается скрытым вводом, из `PROXSTACK_TELEGRAM_TOKEN` или из `--bot-token`. По умолчанию он не сохраняется. Файл `/etc/proxystack/secrets.env` (режим `600`, владелец root) создаётся только с `--save-token` или после явного согласия.

```bash
sudo proxystack webhook info
sudo proxystack webhook set --url https://webhook.example.com/webhook/ --via direct
sudo proxystack webhook test --url https://webhook.example.com/webhook/
sudo proxystack webhook delete
```

`webhook info` показывает URL, IP, `pending_update_count`, `last_error_date`, `last_error_message` и `max_connections`. Запрос к API идёт напрямую, через локальный Squid или через `--http-proxy`.

| Ответ Telegram | Что это обычно значит |
| --- | --- |
| 404 | Путь не совпадает с приложением или Caddy не ведёт `/webhook/` |
| 502 | Upstream за Caddy ответил ошибкой; запустите `proxystack doctor` |
| timeout | Пакеты не дошли или upstream не ответил |

Пример `getWebhookInfo` (токен подставьте сами, не сохраняйте его в истории оболочки):

```bash
curl -sS "https://api.telegram.org/bot${TOKEN}/getWebhookInfo"
```

## Безопасность

- Пароль по умолчанию — 24 символа без пробелов и без `:`.
- Журнал и `--verbose` редактируют `password` → `***`, токен бота → `REDACTED_TOKEN`, `Proxy-Authorization` → `REDACTED`.
- `curl -v` с секретом в URL не запускается.
- Секретный архив возможен только с `--with-secrets` и парольной фразой.

## Файрвол

| Профиль | Поведение |
| --- | --- |
| 1 Рекомендуемый | Порты прокси только с указанных CIDR. 80/443 могут быть открыты. |
| 2 VPN/LAN | То же, плюс `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, если список пуст. |
| 3 Публичный | Порты прокси открыты в Интернет. Нужно ввести `PUBLIC` или передать `--allow-public`. |

Порт SSH определяется по `SSH_CONNECTION`, затем по `sshd_config`, иначе это 22. План показывается до применения. `ufw reset`, `iptables -F` и `nft flush` не выполняются. Если уже есть правила nftables или iptables, CLI ничего не стирает. Неинтерактивное применение требует `--force`.

```bash
sudo proxystack firewall status
sudo proxystack firewall --firewall-profile recommended --allow-cidr 203.0.113.10/32 --force
```

## Диагностика

`sudo proxystack doctor` идёт по цепочке и печатает `[ OK ]`, `[ WARN ]` или `[ FAIL ]`. В конце — сводка Passed / Warnings / Failed и конкретные рекомендации.

Проверяются ОС, root, архитектура, RAM и диск, маршрут по умолчанию, внешний интерфейс, публичный IPv4, DNS, домен, маршрут и TCP до upstream, исходящие 80/443, Dante, Squid, Caddy (сертификат, редирект, POST webhook), файрвол и `getWebhookInfo`, если токен сохранён.

Особый случай: Caddy отвечает **502**, а прямой TCP до upstream заканчивается **timeout**. Doctor делает вывод: DNS работает, маршрут есть, TCP не установился, проблема **NOT Caddy**. Чаще всего это фильтрация source-IP, firewall, security group или сеть upstream. На стороне upstream:

```bash
sudo tcpdump -ni ens3 host 203.0.113.50 and tcp port 8080
```

Подставьте интерфейс, адрес и порт из отчёта. Если SYN не видно, пакет отброшен до сервера.

## Тесты

```bash
make check
```

Это ShellCheck, `shfmt` и модульные тесты Bats: разбор аргументов, язык, IP/CIDR/порты, редактирование секретов, выбор интерфейса, конфиги Dante/Squid/Caddy, план файрвола, диагноз 502, имена архивов, контрольные суммы. Интеграционные тесты ставят пакеты в GitHub Actions (Ubuntu 22.04 и 24.04): проверка конфигов, живой SOCKS5, живой CONNECT и POST webhook на локальный mock upstream.

## Миграция

```bash
# старый сервер
sudo proxystack export --output /root/proxystack-migrate.tar.gz
# новый сервер
sudo proxystack install-script
sudo proxystack import --file /root/proxystack-migrate.tar.gz
sudo proxystack doctor
```

Импорт заново определяет интерфейс и публичный IPv4, переписывает Dante и не оставляет старый адрес в конфиге. Caddy запрашивает сертификат уже на новом хосте. Если адрес изменился, отчёт прямо говорит, что нужно поправить DNS.

## Резервные копии

```bash
sudo proxystack backup --output /root/proxystack.tar.gz
sudo proxystack backup --output /root/proxystack.tar.gz.enc --with-secrets --secrets-passphrase 'choose-one'
sudo proxystack restore --file /root/proxystack.tar.gz
```

Обычный архив содержит настройки CLI, конфиг Dante, конфиг Squid, Caddyfile, заметки файрвола и metadata. Секреты не входят, пока вы не указали `--with-secrets`. Такой архив шифруется, и перед этим печатается предупреждение.

## Обновление

`proxystack update` и `proxystack update-script` показывают текущую версию, последнюю версию и текст релиза. Порядок загрузки: GitHub Release, raw GitHub, jsDelivr. Перед установкой сверяется `SHA256SUMS`. Dante, Squid и Caddy не перезапускаются.

```bash
sudo proxystack update-script
```

## Удаление

```bash
sudo proxystack uninstall dante
sudo proxystack uninstall all --force
sudo proxystack uninstall-script
```

`uninstall` останавливает выбранные службы и удаляет пакеты, которые поставил сам CLI. Чужие правила SSH не снимаются. `uninstall-script` удаляет бинарник и библиотеки, каталог `/etc/proxystack` остаётся.

## Структура файлов

```text
/usr/local/bin/proxystack
/usr/local/lib/proxystack/
/etc/proxystack/config.env
/etc/proxystack/secrets.env          # только с вашего согласия, режим 600
/var/lib/proxystack/
/var/log/proxystack/proxystack.log
/etc/danted.conf
/etc/squid/squid.conf
/etc/caddy/Caddyfile
/var/log/caddy/
```

В репозитории:

```text
proxystack.sh
lib/          common, i18n, ui, system, dante, squid, caddy,
              telegram, firewall, doctor, backup, update
locales/      en.sh, ru.sh
tests/unit
tests/integration
```

## Устранение неполадок

| Симптом | Что делать |
| --- | --- |
| Не найден внешний интерфейс | Проверьте `ip route show default`. Имя интерфейса не задаётся заранее. |
| Откат после установки Dante или Squid | Смотрите строку `rollback succeeded` и `journalctl -u danted` или `journalctl -u squid`. |
| `permission denied` на `/var/log/caddy` | `sudo proxystack restart caddy` заново создаёт каталог для пользователя `caddy`. |
| Webhook 502 и timeout до upstream | `sudo proxystack doctor`. Если в тексте есть `NOT Caddy`, ищите фильтр по IP, а не ошибку Caddyfile. |
| Сертификат не выпускается | A/AAAA должны указывать на этот сервер, порт 80 должен быть доступен снаружи. |
| UFW не изменился | Уже есть nftables или iptables. CLI их не очищает. |

## GitHub Releases

Тег публикует `proxystack.sh`, `proxy-stack-cli-vX.Y.Z.tar.gz` и `SHA256SUMS`. Актуальный выпуск: [0.1.0](https://github.com/driverm35/proxy-stack-cli/releases/latest). Перед установкой: `sha256sum -c SHA256SUMS`.

## Лицензия

MIT. Текст в [LICENSE](LICENSE).

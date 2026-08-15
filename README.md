# nix-vuh

Полноценная упаковка [vuh (version-update-helper)](https://github.com/Greewil/version-update-helper)
для Nix и NixOS: пакет, оверлей, модуль NixOS, модуль Home Manager и набор тестов.

`vuh` — это bash-утилита, которая достаёт версию проекта из того файла, где вы её
храните, сравнивает её с версией в основной ветке и подсказывает (или сразу
записывает) версию, которую должна нести текущая ветка. Конфигурация лежит в
файле `.vuh` в корне репозитория; моно-репозитории с отдельными версиями модулей
поддерживаются.

Апстрим ставится скриптом `installer.sh`, который копирует файлы в `/usr/bin`,
дописывает в скрипт путь до каталога с данными и разрешает `vuh` обновлять
самого себя. В Nix так нельзя — здесь всё то же самое сделано декларативно.

---

## Быстрый старт

```sh
# разовый запуск
nix run github:wprhvso/nix-vuh -- --help

# положить в профиль
nix profile install github:wprhvso/nix-vuh

# без flakes
nix-build && ./result/bin/vuh --version
```

## Установка

### Flake + NixOS

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-vuh.url = "github:wprhvso/nix-vuh";
    nix-vuh.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nix-vuh, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nix-vuh.nixosModules.default
        {
          programs.vuh.enable = true;
        }
      ];
    };
  };
}
```

### Flake + Home Manager

```nix
{
  imports = [ inputs.nix-vuh.homeManagerModules.default ];
  programs.vuh.enable = true;
}
```

Модуль доступен и как `homeModules.default` — это то же самое, просто под именем,
которое понимает `nix flake show`.

### Оверлей

Если удобнее обычный `pkgs.vuh`:

```nix
nixpkgs.overlays = [ inputs.nix-vuh.overlays.default ];
environment.systemPackages = [ pkgs.vuh ];
```

### Без flakes

```nix
let
  nix-vuh = fetchTarball {
    url = "https://github.com/wprhvso/nix-vuh/archive/main.tar.gz";
    sha256 = "";  # nix подскажет правильное значение
  };
in
{
  imports = [ "${nix-vuh}/modules/nixos.nix" ];
  programs.vuh.enable = true;
}
```

`default.nix` и `shell.nix` в корне работают со старым `nix-build` / `nix-shell`
и берут nixpkgs из `<nixpkgs>`.

## Опции модулей

Модули NixOS и Home Manager объявляют одинаковый набор опций (см.
[`modules/common.nix`](modules/common.nix)):

| Опция | Тип | По умолчанию | Что делает |
| --- | --- | --- | --- |
| `programs.vuh.enable` | `bool` | `false` | Ставит `vuh` и его автодополнения |
| `programs.vuh.package` | `package` | `pkgs.vuh`, либо пакет из этого репозитория | Какой пакет ставить |
| `programs.vuh.enableUpdateChecks` | `bool` | `false` | Разрешить ежедневную проверку новых релизов на github |
| `programs.vuh.stateDirectory` | `null` или `str` | `null` | Значение `VUH_STATE_DIR`; `null` — XDG-умолчание |

Автодополнения ставятся в `share/bash-completion/completions` и
`share/zsh/site-functions`, поэтому их подхватывают штатные
`programs.bash.completion.enable` и `programs.zsh.enableCompletion` — никаких
дописываний в `~/.bashrc` модуль не делает.

Одна деталь про NixOS: каталог `share/zsh` попадает в системный профиль только
при `programs.zsh.enable = true` (так устроен модуль zsh в nixpkgs, а не этот
пакет). Пользователям zsh это и так нужно; у Home Manager такого ограничения
нет, там в профиль линкуется весь вывод пакета.

## Что изменено по сравнению с апстримом

`installer.sh` при установке делает несколько подстановок и настроек. Все они
воспроизведены декларативно; кроме того, часть поведения, которое несовместимо с
неизменяемым префиксом, отключена или исправлена. Патчи лежат в
[`pkgs/vuh/patches/`](pkgs/vuh/patches/) и написаны так, чтобы их можно было
предложить апстриму.

### Подстановки (то, что делает `installer.sh`)

| Плейсхолдер | Значение в этом пакете |
| --- | --- |
| `<should_be_replace_after_installation:DATA_DIR>` | `$out/share/vuh` |
| `<should_be_replace_after_installation:UPDATE_CHECKS>` | `false` (или `true` с `enableUpdateChecks`) |
| `#!/usr/bin/env bash` | bash из стора (`patchShebangs`) |
| `INSTALLATION_DIR` / `COMPLETION_DIR` / `COMPLETION_SCRIPT_NAME` / `DAILY_UPDATE_CHECKS` | сгенерированный `$out/share/vuh/.installation_info`, который печатает `vuh --configuration` |

### Патчи

1. **`0001` — изменяемое состояние вне префикса установки.** `DATA_DIR` указывает
   в стор, а он только для чтения. Отметка о последней проверке обновлений
   переехала в `$VUH_STATE_DIR`, по умолчанию `$XDG_STATE_HOME/vuh`
   (то есть `~/.local/state/vuh`).
2. **`0002` — проверка обновлений стала переключателем времени сборки.** Добавлен
   плейсхолдер `UPDATE_CHECKS`, а код, который скачивал архив и перезаписывал сам
   себя, удалён: в сторе это невозможно. `vuh --update` честно говорит, что
   обновляться нужно тем же способом, каким пакет был установлен.
3. **`0003` — не подгружать конфиг из предсказуемого файла в `/tmp`.** `.vuh`
   исполняется через `source`. Файл `/tmp/vuh_projects_conf_file` с фиксированным
   именем — это и локальная дыра (симлинк туда даёт исполнение произвольного кода
   от имени того, кто запустил `vuh`), и гонка между параллельными запусками
   (`-pm=ALL` запускает `vuh` рекурсивно). Теперь используется `mktemp`.
4. **`0004` — текст справки берётся из самого скрипта.** `vuh --help` делает
   `grep '^#/' <"$0"`, а `$0` — это обёртка от `makeWrapper` (`exec -a "$0"`), в
   которой справки нет. `${BASH_SOURCE[0]}` указывает на настоящий файл всегда.
5. **`0005` — лишний обратный слэш в шаблоне `grep`.** GNU grep 3.8+ печатает
   `warning: stray \ before _` на каждой команде в моно-репозитории.
6. **`0006` — неудачная проверка обновлений не должна ронять команду.** С
   включёнными проверками первая за день команда завершалась с ошибкой, если
   github недоступен. Отсутствие сети — не ошибка.

### Что намеренно не установлено

`installer.sh`, `auto_update.sh` и сам `vuh.sh` в `bin/` не попадают: установкой
и обновлением занимается Nix.

## Проверка обновлений vuh

По умолчанию выключена. Это не только вопрос чистоты сборки: `vuh` физически не
может себя заменить в сторе, поэтому единственное, что даёт проверка, — сообщение
о версии, которую вам всё равно придётся собрать через Nix, ценой сетевого запроса
раз в сутки. Если она всё же нужна:

```nix
programs.vuh.enableUpdateChecks = true;
# или
environment.systemPackages = [ (pkgs.vuh.override { enableUpdateChecks = true; }) ];
```

В этом варианте в замыкание добавляется `curl`, а отметка о проверке пишется в
`$VUH_STATE_DIR/latest_update_check`.

## Использование

Скопируйте подходящий шаблон в корень проекта под именем `.vuh`:

```sh
templates=$(nix build --no-link --print-out-paths github:wprhvso/nix-vuh#vuh)/share/vuh/project-config-templates
cp "$templates/json-versions-template" .vuh
```

Доступны шаблоны `json-versions-template`, `shell-versions-template`,
`xml-versions-template` и `monorepo-template`. Дальше:

```sh
vuh lv          # версия в текущей ветке
vuh mv          # версия в origin/<главная ветка>
vuh sv          # какая версия нужна этой ветке
vuh uv          # записать её в файл версии
vuh pm          # список модулей моно-репозитория
vuh mrp -pm=API # корень модуля моно-репозитория
vuh sv -pm=ALL  # выполнить команду для всех модулей
```

Полное описание команд — `vuh --help` и
[README апстрима](https://github.com/Greewil/version-update-helper).

## Разработка

```sh
nix develop                    # vuh, git, nixfmt, nix-update, shellcheck
nix flake check                # собрать и прогнать все тесты
nix fmt                        # отформатировать *.nix
nix build .#checks.x86_64-linux.vuh-cli   # один тест
```

Тесты живут в [`tests/`](tests/) и доступны и как `passthru.tests`
(`nix-build -A tests.cli`), и как выходы флейка:

| Тест | Что проверяет |
| --- | --- |
| `version` | `vuh --version` совпадает с версией деривации |
| `cli` | Полный сценарий на настоящем git-репозитории: `lv`, `mv`, `sv`, `uv`, `--dont-use-git`, моно-репозиторий с `-pm=ALL` и `-cpm`, `--help`, `--configuration`, отказ `--update`, работа с пустым `PATH` |
| `purity` | Все плейсхолдеры подставлены, шебанг из стора, обёртка тянет все зависимости, `curl` появляется только вместе с проверкой обновлений, лишние файлы не установлены |
| `completion` | Автодополнение bash реально предлагает команды и опции; файл zsh разбирается и подхватывается `compinit` |
| `state` | Только для сборки с проверкой обновлений: состояние пишется в `$VUH_STATE_DIR`, стор не трогается, отсутствие сети не ломает команду |
| `nixos-module`, `home-manager-module` | Модули вычисляются на заглушках: выключены по умолчанию, ставят ровно то, что просили, `stateDirectory` даёт `VUH_STATE_DIR`, `enableUpdateChecks` действительно пересобирает пакет |
| `nixos` | Настоящая виртуалка NixOS с включённым модулем (только Linux, нужен KVM) |

### Поддерживаемые системы

`x86_64-linux`, `aarch64-linux`, `aarch64-darwin`. `x86_64-darwin` не указан
намеренно: nixpkgs убрал его поддержку в 26.11, а `nix flake show` вычисляет
все перечисленные системы, так что одно только упоминание ломает вычисление
флейка.

### Про `flake.lock`

Файл блокировки в репозитории не зафиксирован намеренно: единственный вход —
`nixpkgs`, и без него флейк каждый раз собирается против свежего
`nixos-unstable`, что и нужно еженедельной проверке в CI. Если вам нужна
воспроизводимость, зафиксируйте вход у себя:

```sh
nix flake lock          # создаст flake.lock
nix flake update        # обновит его
```

Либо, если этот флейк используется как вход, укажите `inputs.nixpkgs.follows`
на свой nixpkgs (как в примере выше) — тогда версия определяется вашим локом.

### Обновление версии vuh

```sh
nix-update vuh          # или: nix run nixpkgs#nix-update -- vuh
```

Патчи специально сделаны маленькими и контекстными — при обновлении апстрима они
либо применятся, либо упадут с понятным конфликтом.

## Лицензии

Упаковка — MIT (см. [LICENSE](LICENSE)). Сам `vuh` — MIT, авторства
Sergey Shishkin, копия лежит в `$out/share/doc/vuh/LICENSE`.

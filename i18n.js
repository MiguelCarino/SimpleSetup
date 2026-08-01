// i18n — Carino Setup landing page. English strings ARE the keys, so a
// missing entry falls back to English. Locale comes from the fleet resolver
// (carino-lang.js: ?lang > cookie > browser > en); this file only owns the
// dictionaries and reapplies them on the 'carino:langchange' event.
// Deliberately left in English: shell commands, package/app names, distro
// names, the refusal texts (verbatim setup.sh output) and the builder's
// generated explanation panels, which quote script behaviour.
// Japanese deliberately says "PC", not コンピューター.

const I18N = {
    es: {
        // Hero
        'Carino Systems · Universal OS Automation': 'Carino Systems · Automatización universal de SO',
        'One command turns a fresh install into a usable machine. Linux, Windows and macOS.': 'Un comando convierte una instalación recién hecha en una máquina lista para usar. Linux, Windows y macOS.',
        // Linux pane
        'One Command': 'Un comando',
        'Plan Builder': 'Generador de planes',
        'Copy': 'Copiar',
        'Copied': 'Copiado',
        'Press Ctrl+C': 'Pulsa Ctrl+C',
        'Every distribution it knows about': 'Todas las distribuciones que reconoce',
        // Plan builder
        'Choose what you want and this page writes the command. Nothing runs here and nothing leaves your browser.': 'Elige lo que quieres y esta página escribe el comando. Aquí no se ejecuta nada y nada sale de tu navegador.',
        'Your distribution': 'Tu distribución',
        'Purpose profile': 'Perfil de uso',
        'Desktop environment': 'Entorno de escritorio',
        'Technical Setup': 'Configuración técnica',
        'Graphic drivers': 'Controladores gráficos',
        'System update': 'Actualización del sistema',
        'Server setup': 'Configuración de servidor',
        'Reboot at the end': 'Reiniciar al final',
        'This distribution is refused by design': 'Esta distribución se rechaza por diseño',
        'Your command': 'Tu comando',
        'Rehearse it first': 'Ensáyalo primero',
        'Prints every privileged command instead of running it. Nothing is installed and nothing is changed.': 'Imprime cada comando privilegiado en lugar de ejecutarlo. No se instala ni se cambia nada.',
        'None': 'Ninguno',
        '— already run by the Technical Setup': '— la Configuración técnica ya lo ejecuta',
        'Runs instead of the menu, then exits. Nothing prompts you: every question takes its documented default and says so.': 'Se ejecuta en lugar del menú y luego termina. No te pregunta nada: cada pregunta toma su valor por defecto documentado y lo indica.',
        'Reboot needs a step to follow. Tick something else, or use the plain command below.': 'El reinicio necesita un paso al que seguir. Marca algo más o usa el comando simple de abajo.',
        'Nothing is selected, so this is the plain command and it opens the interactive menu.': 'No hay nada seleccionado, así que este es el comando simple y abre el menú interactivo.',
        'This page address encodes the selection by name. Copy it from the address bar to share this exact plan.': 'La dirección de esta página codifica la selección por nombre. Cópiala de la barra de direcciones para compartir este plan exacto.',
        // Windows / macOS panes
        'Run Terminal as Administrator': 'Ejecuta la Terminal como administrador',
        '— the script stops without it. It detects your build, applies the Windows 10 or 11 tweaks, then asks which profile to install and installs it with winget.': '— sin eso el script se detiene. Detecta tu compilación, aplica los ajustes de Windows 10 u 11, pregunta qué perfil instalar y lo instala con winget.',
        'Installs Homebrew if missing, then a Basic, Gaming, Corporate or FOSS profile. Apple Silicon and Intel.': 'Instala Homebrew si falta y luego un perfil Básico, Gaming, Corporativo o FOSS. Apple Silicon e Intel.',
        // Cards
        'Smart Detection': 'Detección inteligente',
        'Identifies your OS, distribution and hardware, then installs what matches.': 'Identifica tu SO, distribución y hardware, y luego instala lo que corresponde.',
        'Eight Languages': 'Ocho idiomas',
        'Installer menus in English, Japanese, Russian, Spanish, Finnish, Chinese, Korean and Hebrew.': 'Menús del instalador en inglés, japonés, ruso, español, finés, chino, coreano y hebreo.',
        'Purpose-Built': 'Para cada propósito',
        '15 profiles — Gaming, Corporate, Development, Design, Cybersecurity, Medical Imaging and more.': '15 perfiles: Gaming, Corporativo, Desarrollo, Diseño, Ciberseguridad, Imagen médica y más.',
        // Arguments table
        'Available Arguments': 'Argumentos disponibles',
        'Flag': 'Opción',
        'Action': 'Acción',
        'Technical Setup, then the basic user, system and support packages plus the basic and Google flatpaks.': 'Configuración técnica y luego los paquetes básicos de usuario, sistema y soporte, más los flatpaks básicos y de Google.',
        'Runs the Technical Setup only.': 'Ejecuta solo la Configuración técnica.',
        'Minimal server setup with essential dev tools. Skips the full Technical Setup.': 'Configuración mínima de servidor con herramientas de desarrollo esenciales. Omite la Configuración técnica completa.',
        'Forces specific graphic driver installation.': 'Fuerza la instalación de un controlador gráfico específico.',
        'Opens a menu to select a new Desktop Environment.': 'Abre un menú para elegir un nuevo entorno de escritorio.',
        'Installs Smooth Video Project for frame-interpolated playback.': 'Instala Smooth Video Project para reproducción con interpolación de fotogramas.',
        'Installs Distrobox containers for other distros.': 'Instala contenedores Distrobox para otras distribuciones.',
        'Installs the latest ProtonGE release.': 'Instala la última versión de ProtonGE.',
        'Adds the LibreWolf repository and installs it. Fedora and Debian families only.': 'Añade el repositorio de LibreWolf y lo instala. Solo familias Fedora y Debian.',
        'Enables Flathub and installs the AnyDesk and RustDesk flatpaks.': 'Activa Flathub e instala los flatpaks de AnyDesk y RustDesk.',
        'Adds the official AnyDesk repository and installs it natively.': 'Añade el repositorio oficial de AnyDesk y lo instala de forma nativa.',
        'Mounts a Windows/CIFS share at': 'Monta un recurso compartido Windows/CIFS en',
        'no argument': 'sin argumento',
        'Opens the interactive menu, where option 5 updates the system.': 'Abre el menú interactivo, donde la opción 5 actualiza el sistema.',
        // Footer
        'Carino Setup is open source.': 'Carino Setup es de código abierto.',
        'Improve this page on GitHub': 'Mejora esta página en GitHub',
    },
    'pt-BR': {
        'Carino Systems · Universal OS Automation': 'Carino Systems · Automação universal de SO',
        'One command turns a fresh install into a usable machine. Linux, Windows and macOS.': 'Um comando transforma uma instalação recém-feita em uma máquina pronta para usar. Linux, Windows e macOS.',
        'One Command': 'Um comando',
        'Plan Builder': 'Gerador de planos',
        'Copy': 'Copiar',
        'Copied': 'Copiado',
        'Press Ctrl+C': 'Pressione Ctrl+C',
        'Every distribution it knows about': 'Todas as distribuições que ele reconhece',
        'Choose what you want and this page writes the command. Nothing runs here and nothing leaves your browser.': 'Escolha o que você quer e esta página escreve o comando. Nada é executado aqui e nada sai do seu navegador.',
        'Your distribution': 'Sua distribuição',
        'Purpose profile': 'Perfil de uso',
        'Desktop environment': 'Ambiente de desktop',
        'Technical Setup': 'Configuração técnica',
        'Graphic drivers': 'Drivers gráficos',
        'System update': 'Atualização do sistema',
        'Server setup': 'Configuração de servidor',
        'Reboot at the end': 'Reiniciar no final',
        'This distribution is refused by design': 'Esta distribuição é recusada por design',
        'Your command': 'Seu comando',
        'Rehearse it first': 'Ensaie primeiro',
        'Prints every privileged command instead of running it. Nothing is installed and nothing is changed.': 'Imprime cada comando privilegiado em vez de executá-lo. Nada é instalado e nada é alterado.',
        'None': 'Nenhum',
        '— already run by the Technical Setup': '— a Configuração técnica já executa isso',
        'Runs instead of the menu, then exits. Nothing prompts you: every question takes its documented default and says so.': 'Executa no lugar do menu e depois encerra. Nada é perguntado: cada pergunta assume seu padrão documentado e avisa isso.',
        'Reboot needs a step to follow. Tick something else, or use the plain command below.': 'A reinicialização precisa de um passo antes. Marque algo mais ou use o comando simples abaixo.',
        'Nothing is selected, so this is the plain command and it opens the interactive menu.': 'Nada está selecionado, então este é o comando simples e ele abre o menu interativo.',
        'This page address encodes the selection by name. Copy it from the address bar to share this exact plan.': 'O endereço desta página codifica a seleção por nome. Copie-o da barra de endereço para compartilhar exatamente este plano.',
        'Run Terminal as Administrator': 'Execute o Terminal como administrador',
        '— the script stops without it. It detects your build, applies the Windows 10 or 11 tweaks, then asks which profile to install and installs it with winget.': '— sem isso o script para. Ele detecta sua build, aplica os ajustes do Windows 10 ou 11, pergunta qual perfil instalar e o instala com o winget.',
        'Installs Homebrew if missing, then a Basic, Gaming, Corporate or FOSS profile. Apple Silicon and Intel.': 'Instala o Homebrew se estiver faltando e depois um perfil Básico, Gaming, Corporativo ou FOSS. Apple Silicon e Intel.',
        'Smart Detection': 'Detecção inteligente',
        'Identifies your OS, distribution and hardware, then installs what matches.': 'Identifica seu SO, distribuição e hardware, e então instala o que corresponde.',
        'Eight Languages': 'Oito idiomas',
        'Installer menus in English, Japanese, Russian, Spanish, Finnish, Chinese, Korean and Hebrew.': 'Menus do instalador em inglês, japonês, russo, espanhol, finlandês, chinês, coreano e hebraico.',
        'Purpose-Built': 'Para cada propósito',
        '15 profiles — Gaming, Corporate, Development, Design, Cybersecurity, Medical Imaging and more.': '15 perfis: Gaming, Corporativo, Desenvolvimento, Design, Cibersegurança, Imagem médica e mais.',
        'Available Arguments': 'Argumentos disponíveis',
        'Flag': 'Opção',
        'Action': 'Ação',
        'Technical Setup, then the basic user, system and support packages plus the basic and Google flatpaks.': 'Configuração técnica e depois os pacotes básicos de usuário, sistema e suporte, mais os flatpaks básicos e do Google.',
        'Runs the Technical Setup only.': 'Executa apenas a Configuração técnica.',
        'Minimal server setup with essential dev tools. Skips the full Technical Setup.': 'Configuração mínima de servidor com ferramentas de desenvolvimento essenciais. Pula a Configuração técnica completa.',
        'Forces specific graphic driver installation.': 'Força a instalação de um driver gráfico específico.',
        'Opens a menu to select a new Desktop Environment.': 'Abre um menu para escolher um novo ambiente de desktop.',
        'Installs Smooth Video Project for frame-interpolated playback.': 'Instala o Smooth Video Project para reprodução com interpolação de quadros.',
        'Installs Distrobox containers for other distros.': 'Instala contêineres Distrobox para outras distribuições.',
        'Installs the latest ProtonGE release.': 'Instala a versão mais recente do ProtonGE.',
        'Adds the LibreWolf repository and installs it. Fedora and Debian families only.': 'Adiciona o repositório do LibreWolf e o instala. Apenas famílias Fedora e Debian.',
        'Enables Flathub and installs the AnyDesk and RustDesk flatpaks.': 'Ativa o Flathub e instala os flatpaks do AnyDesk e do RustDesk.',
        'Adds the official AnyDesk repository and installs it natively.': 'Adiciona o repositório oficial do AnyDesk e o instala nativamente.',
        'Mounts a Windows/CIFS share at': 'Monta um compartilhamento Windows/CIFS em',
        'no argument': 'sem argumento',
        'Opens the interactive menu, where option 5 updates the system.': 'Abre o menu interativo, onde a opção 5 atualiza o sistema.',
        'Carino Setup is open source.': 'O Carino Setup é de código aberto.',
        'Improve this page on GitHub': 'Melhore esta página no GitHub',
    },
    ja: {
        'Carino Systems · Universal OS Automation': 'Carino Systems · ユニバーサルOS自動化',
        'One command turns a fresh install into a usable machine. Linux, Windows and macOS.': '1つのコマンドで、インストールしたばかりのOSをすぐ使えるPCに。Linux、Windows、macOS対応。',
        'One Command': 'ワンコマンド',
        'Plan Builder': 'プランビルダー',
        'Copy': 'コピー',
        'Copied': 'コピーしました',
        'Press Ctrl+C': 'Ctrl+Cを押してください',
        'Every distribution it knows about': '対応しているディストリビューション一覧',
        'Choose what you want and this page writes the command. Nothing runs here and nothing leaves your browser.': '欲しいものを選ぶと、このページがコマンドを書き出します。ここでは何も実行されず、ブラウザの外に何も送信されません。',
        'Your distribution': 'ディストリビューション',
        'Purpose profile': '用途プロファイル',
        'Desktop environment': 'デスクトップ環境',
        'Technical Setup': 'テクニカルセットアップ',
        'Graphic drivers': 'グラフィックドライバー',
        'System update': 'システム更新',
        'Server setup': 'サーバーセットアップ',
        'Reboot at the end': '最後に再起動',
        'This distribution is refused by design': 'このディストリビューションは意図的に非対応です',
        'Your command': '生成されたコマンド',
        'Rehearse it first': 'まずはドライランで確認',
        'Prints every privileged command instead of running it. Nothing is installed and nothing is changed.': '特権コマンドを実行せずに表示だけします。何もインストールされず、何も変更されません。',
        'None': 'なし',
        '— already run by the Technical Setup': '— テクニカルセットアップで実行済み',
        'Runs instead of the menu, then exits. Nothing prompts you: every question takes its documented default and says so.': 'メニューの代わりに実行して終了します。何も質問されず、各質問は文書化された既定値を使い、その旨を表示します。',
        'Reboot needs a step to follow. Tick something else, or use the plain command below.': '再起動には先に実行するステップが必要です。他の項目を選ぶか、下の標準コマンドを使ってください。',
        'Nothing is selected, so this is the plain command and it opens the interactive menu.': '何も選択されていないため、これは標準コマンドで、対話メニューを開きます。',
        'This page address encodes the selection by name. Copy it from the address bar to share this exact plan.': 'このページのアドレスには選択内容が名前で記録されます。アドレスバーからコピーすれば、このプランをそのまま共有できます。',
        'Run Terminal as Administrator': 'ターミナルを管理者として実行',
        '— the script stops without it. It detects your build, applies the Windows 10 or 11 tweaks, then asks which profile to install and installs it with winget.': '— これがないとスクリプトは停止します。ビルドを検出してWindows 10/11向けの調整を適用した後、インストールするプロファイルを尋ね、wingetでインストールします。',
        'Installs Homebrew if missing, then a Basic, Gaming, Corporate or FOSS profile. Apple Silicon and Intel.': 'Homebrewが無ければインストールし、Basic・Gaming・Corporate・FOSSのいずれかのプロファイルを導入します。Apple SiliconとIntelに対応。',
        'Smart Detection': 'スマート検出',
        'Identifies your OS, distribution and hardware, then installs what matches.': 'OS・ディストリビューション・ハードウェアを識別し、環境に合ったものをインストールします。',
        'Eight Languages': '8言語対応',
        'Installer menus in English, Japanese, Russian, Spanish, Finnish, Chinese, Korean and Hebrew.': 'インストーラーのメニューは英語・日本語・ロシア語・スペイン語・フィンランド語・中国語・韓国語・ヘブライ語に対応。',
        'Purpose-Built': '用途別プロファイル',
        '15 profiles — Gaming, Corporate, Development, Design, Cybersecurity, Medical Imaging and more.': '15のプロファイル — ゲーミング、企業、開発、デザイン、サイバーセキュリティ、医用画像など。',
        'Available Arguments': '利用可能な引数',
        'Flag': 'フラグ',
        'Action': '動作',
        'Technical Setup, then the basic user, system and support packages plus the basic and Google flatpaks.': 'テクニカルセットアップの後、基本のユーザー・システム・サポートパッケージと、基本およびGoogleのflatpakを導入します。',
        'Runs the Technical Setup only.': 'テクニカルセットアップのみ実行します。',
        'Minimal server setup with essential dev tools. Skips the full Technical Setup.': '必須の開発ツールを含む最小限のサーバーセットアップ。完全なテクニカルセットアップは行いません。',
        'Forces specific graphic driver installation.': '指定したグラフィックドライバーを強制的にインストールします。',
        'Opens a menu to select a new Desktop Environment.': '新しいデスクトップ環境を選ぶメニューを開きます。',
        'Installs Smooth Video Project for frame-interpolated playback.': 'フレーム補間再生のためSmooth Video Projectをインストールします。',
        'Installs Distrobox containers for other distros.': '他のディストリビューション用のDistroboxコンテナをインストールします。',
        'Installs the latest ProtonGE release.': '最新のProtonGEリリースをインストールします。',
        'Adds the LibreWolf repository and installs it. Fedora and Debian families only.': 'LibreWolfのリポジトリを追加してインストールします。FedoraとDebian系のみ。',
        'Enables Flathub and installs the AnyDesk and RustDesk flatpaks.': 'Flathubを有効化してAnyDeskとRustDeskのflatpakをインストールします。',
        'Adds the official AnyDesk repository and installs it natively.': 'AnyDeskの公式リポジトリを追加してネイティブにインストールします。',
        'Mounts a Windows/CIFS share at': 'Windows/CIFS共有のマウント先:',
        'no argument': '引数なし',
        'Opens the interactive menu, where option 5 updates the system.': '対話メニューを開きます。オプション5でシステムを更新できます。',
        'Carino Setup is open source.': 'Carino Setupはオープンソースです。',
        'Improve this page on GitHub': 'GitHubでこのページを改善',
    },
    ru: {
        'Carino Systems · Universal OS Automation': 'Carino Systems · Универсальная автоматизация ОС',
        'One command turns a fresh install into a usable machine. Linux, Windows and macOS.': 'Одна команда превращает свежеустановленную систему в готовую к работе машину. Linux, Windows и macOS.',
        'One Command': 'Одна команда',
        'Plan Builder': 'Конструктор плана',
        'Copy': 'Копировать',
        'Copied': 'Скопировано',
        'Press Ctrl+C': 'Нажмите Ctrl+C',
        'Every distribution it knows about': 'Все дистрибутивы, которые он знает',
        'Choose what you want and this page writes the command. Nothing runs here and nothing leaves your browser.': 'Выберите нужное — страница сама составит команду. Здесь ничего не запускается, и ничего не покидает ваш браузер.',
        'Your distribution': 'Ваш дистрибутив',
        'Purpose profile': 'Профиль назначения',
        'Desktop environment': 'Окружение рабочего стола',
        'Technical Setup': 'Техническая настройка',
        'Graphic drivers': 'Графические драйверы',
        'System update': 'Обновление системы',
        'Server setup': 'Настройка сервера',
        'Reboot at the end': 'Перезагрузка в конце',
        'This distribution is refused by design': 'Этот дистрибутив не поддерживается намеренно',
        'Your command': 'Ваша команда',
        'Rehearse it first': 'Сначала — репетиция',
        'Prints every privileged command instead of running it. Nothing is installed and nothing is changed.': 'Печатает каждую привилегированную команду вместо её выполнения. Ничего не устанавливается и не меняется.',
        'None': 'Нет',
        '— already run by the Technical Setup': '— уже выполняется Технической настройкой',
        'Runs instead of the menu, then exits. Nothing prompts you: every question takes its documented default and says so.': 'Выполняется вместо меню и завершает работу. Ничего не спрашивает: каждый вопрос берёт документированное значение по умолчанию и сообщает об этом.',
        'Reboot needs a step to follow. Tick something else, or use the plain command below.': 'Перезагрузке нужен предшествующий шаг. Отметьте что-нибудь ещё или используйте обычную команду ниже.',
        'Nothing is selected, so this is the plain command and it opens the interactive menu.': 'Ничего не выбрано, поэтому это обычная команда — она открывает интерактивное меню.',
        'This page address encodes the selection by name. Copy it from the address bar to share this exact plan.': 'Адрес этой страницы кодирует выбор по именам. Скопируйте его из адресной строки, чтобы поделиться именно этим планом.',
        'Run Terminal as Administrator': 'Запустите терминал от имени администратора',
        '— the script stops without it. It detects your build, applies the Windows 10 or 11 tweaks, then asks which profile to install and installs it with winget.': '— без этого скрипт остановится. Он определяет вашу сборку, применяет твики для Windows 10 или 11, затем спрашивает, какой профиль установить, и ставит его через winget.',
        'Installs Homebrew if missing, then a Basic, Gaming, Corporate or FOSS profile. Apple Silicon and Intel.': 'Устанавливает Homebrew, если его нет, затем профиль Basic, Gaming, Corporate или FOSS. Apple Silicon и Intel.',
        'Smart Detection': 'Умное определение',
        'Identifies your OS, distribution and hardware, then installs what matches.': 'Определяет вашу ОС, дистрибутив и оборудование, затем устанавливает то, что подходит.',
        'Eight Languages': 'Восемь языков',
        'Installer menus in English, Japanese, Russian, Spanish, Finnish, Chinese, Korean and Hebrew.': 'Меню установщика на английском, японском, русском, испанском, финском, китайском, корейском и иврите.',
        'Purpose-Built': 'Под вашу задачу',
        '15 profiles — Gaming, Corporate, Development, Design, Cybersecurity, Medical Imaging and more.': '15 профилей: игры, корпоративный, разработка, дизайн, кибербезопасность, медицинская визуализация и другие.',
        'Available Arguments': 'Доступные аргументы',
        'Flag': 'Флаг',
        'Action': 'Действие',
        'Technical Setup, then the basic user, system and support packages plus the basic and Google flatpaks.': 'Техническая настройка, затем базовые пользовательские, системные и вспомогательные пакеты плюс базовые и Google flatpak.',
        'Runs the Technical Setup only.': 'Выполняет только Техническую настройку.',
        'Minimal server setup with essential dev tools. Skips the full Technical Setup.': 'Минимальная настройка сервера с основными инструментами разработки. Пропускает полную Техническую настройку.',
        'Forces specific graphic driver installation.': 'Принудительно устанавливает указанный графический драйвер.',
        'Opens a menu to select a new Desktop Environment.': 'Открывает меню выбора нового окружения рабочего стола.',
        'Installs Smooth Video Project for frame-interpolated playback.': 'Устанавливает Smooth Video Project для воспроизведения с интерполяцией кадров.',
        'Installs Distrobox containers for other distros.': 'Устанавливает контейнеры Distrobox для других дистрибутивов.',
        'Installs the latest ProtonGE release.': 'Устанавливает последний релиз ProtonGE.',
        'Adds the LibreWolf repository and installs it. Fedora and Debian families only.': 'Добавляет репозиторий LibreWolf и устанавливает его. Только семейства Fedora и Debian.',
        'Enables Flathub and installs the AnyDesk and RustDesk flatpaks.': 'Включает Flathub и устанавливает flatpak-пакеты AnyDesk и RustDesk.',
        'Adds the official AnyDesk repository and installs it natively.': 'Добавляет официальный репозиторий AnyDesk и устанавливает его нативно.',
        'Mounts a Windows/CIFS share at': 'Монтирует общий ресурс Windows/CIFS в',
        'no argument': 'без аргументов',
        'Opens the interactive menu, where option 5 updates the system.': 'Открывает интерактивное меню, где пункт 5 обновляет систему.',
        'Carino Setup is open source.': 'Carino Setup — проект с открытым исходным кодом.',
        'Improve this page on GitHub': 'Улучшить эту страницу на GitHub',
    },
};

function currentFleetLang() { return (window.CarinoLang && window.CarinoLang.current) || 'en'; }

function t(key) {
    const dict = I18N[currentFleetLang()];
    return (dict && dict[key]) || key;
}

// Static markup: elements carrying data-i18n use their original English text
// as the key (captured on first pass so locale switches stay reversible).
function applyStaticI18n() {
    document.querySelectorAll('[data-i18n]').forEach((el) => {
        if (!el.dataset.i18nKey) el.dataset.i18nKey = el.textContent.trim();
        el.textContent = t(el.dataset.i18nKey);
    });
}

function applyI18n() {
    document.documentElement.lang = currentFleetLang();
    applyStaticI18n();
    // The purpose select is filled once at parse time, before the
    // dictionaries exist; retranslate its 'None' option explicitly.
    const purposeNone = document.querySelector('#b-purpose option[value="none"]');
    if (purposeNone) purposeNone.textContent = t('None');
    // Re-render the plan builder so its T()-wrapped literals pick up the
    // locale; build() is idempotent and only re-reads the current controls.
    if (typeof window.build === 'function') window.build();
}

// carino-lang.js is deferred and runs before this (also deferred) script, so
// CarinoLang exists by DOMContentLoaded.
document.addEventListener('DOMContentLoaded', applyI18n);
window.addEventListener('carino:langchange', applyI18n);

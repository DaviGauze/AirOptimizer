# AirOptimizer

Gerenciador e monitor de processos nativo para macOS, feito em SwiftUI. Lista
processos em execução com uso de CPU/memória em tempo real, permite encerrar
processos com proteção contra processos críticos do sistema, e traz um modo
"Quick Boost" para liberar memória inativa do sistema sem encerrar apps.

## Requisitos

- macOS 13 (Ventura) ou superior
- Swift 5.9 / Xcode 15+ (para rodar os testes com XCTest; `swift build` funciona
  apenas com as Command Line Tools)

## Rodando

Para desenvolvimento rápido (janela + menu bar, mas sem AppleScript/notificações,
que exigem um bundle `.app` de verdade — ver abaixo):

```bash
swift build
swift run
```

Ou abra a pasta no Xcode (`File > Open...`) — o `Package.swift` é reconhecido
automaticamente como um projeto SwiftPM.

### Empacotando como `.app` (necessário para AppleScript e notificações)

```bash
./Scripts/build_app.sh          # debug
open AirOptimizer.app
```

O script compila, monta `AirOptimizer.app` com `Info.plist`/`AirOptimizer.sdef`
em `Resources/`, assina ad-hoc e registra no Launch Services. Use
`./Scripts/build_app.sh release` para uma build de release.

## Arquitetura

MVVM, sem dependências externas:

```
Sources/AirOptimizer/
├── App/                 # entrypoint (@main), AppDelegate, comandos AppleScript
├── Models/              # ProcessInfo, SystemStats, ActionLogEntry
├── Services/            # ProcessManager, SystemMonitor, ActionLogger, PerformanceOptimizer, CleanupScheduler
├── Utilities/           # CriticalProcessGuard, NotificationCenterHelper
├── ViewModels/          # ProcessListViewModel, SystemMonitorViewModel, PerformanceModeViewModel
└── Views/               # DashboardView, ProcessDetailView, MenuBarView, SettingsPanelView, ResourceChartView
Resources/
├── Info.plist           # copiado para o bundle pelo build_app.sh
└── AirOptimizer.sdef    # dicionário de terminologia AppleScript
Scripts/
└── build_app.sh         # empacota o executável em um .app de verdade
```

- **ProcessManager**: lista processos via `proc_listpids`/`proc_pidinfo`
  (libproc, acessível via `import Darwin`, sem bridging header) e calcula
  %CPU por delta entre polls. Encerramento usa `kill(2)` com SIGTERM/SIGKILL.
  Também expõe `setPriority`/`priority` (via `setpriority`/`getpriority`) para
  o Performance Mode.
- **SystemMonitor**: estatísticas agregadas do sistema via `host_statistics64`
  (memória) e `host_statistics`/`HOST_CPU_LOAD_INFO` (CPU), a mesma família de
  API usada internamente pelo Activity Monitor.
- **CriticalProcessGuard**: única fonte de verdade sobre quais processos
  (kernel_task, WindowServer, Finder, Dock, etc.) nunca podem ser encerrados.
- **PerformanceOptimizer**: aciona o Quick Boost (via `MemoryPurger`),
  compartilhado entre a UI, o `CleanupScheduler` e o comando AppleScript
  `quick boost`.
- **MemoryPurger**: roda `/usr/sbin/purge` (via `osascript ... with
  administrator privileges`, já que exige root) para descartar páginas de
  memória inativas/em cache sem encerrar nenhum processo.
- **SMCReader**: lê a temperatura da CPU via SMC (System Management
  Controller) do macOS — a Apple não expõe isso por API pública. Melhor
  esforço: tenta as chaves de núcleo "performance" do Apple Silicon
  (`Tp1a`…`Tp9a`, testado em M1) e cai para `TC0P`/`TC0D`/`TC0E`/`TC0F` em
  Intel. Chaves de temperatura da SMC não são documentadas e variam por
  geração de chip — pode não funcionar em todo Mac/versão do macOS, e nesse
  caso o ícone da menu bar mostra "--°" em vez de travar.

Só existe uma instância de cada ViewModel no app inteiro (criadas em
`AirOptimizerApp` e passadas por parâmetro para `DashboardView`/`MenuBarView`)
— evita dois pollers independentes chamando `ProcessManager.shared` ao mesmo
tempo e corrompendo o baseline de %CPU um do outro.

## Funcionalidades

- **Apresentação dos processos**: nome e ícone amigáveis (via
  `NSRunningApplication.localizedName`/`.icon`) em vez do nome cru do
  executável — "Safari" com o ícone do app, não `com.apple.WebKit.WebContent`.
  O nome técnico só aparece como legenda quando diverge do nome amigável
  (ex.: processos auxiliares/helpers).
- **Quick Boost**: ao clicar em "Quick Boost" (sidebar ou menu bar), o app
  libera memória inativa do sistema via `MemoryPurger` (equivalente ao
  utilitário `purge`). **Não encerra nenhum app** — fechar apps do usuário
  para "otimizar performance" quebraria a proposta do projeto, que é aliviar
  pressão de memória mantendo tudo aberto. Como `purge` exige privilégios de
  root, a ação dispara o diálogo de autenticação nativo do macOS. O
  agendador de limpeza automática e o comando AppleScript `quick boost`
  disparam exatamente a mesma ação.
- **Aba "Configurações"** na janela principal (ao lado de "Processos" e
  "Monitoramento"): intervalo de auto-refresh, limiar de alerta de memória,
  Performance Mode e agendador de limpeza — tudo ligado diretamente às
  ViewModels em uso (mudar um valor já tem efeito imediato).
- **Menu bar**: mostra CPU/memória por processo (top consumidores) e só três
  ações — Quick Boost, Configurações (abre a janela principal já na aba
  Configurações) e Sair.
- **Ícone da menu bar com CPU/RAM/Temperatura**: por padrão, o ícone da
  status bar mostra `🖥CPU% | 💾RAM% | 🌡Temp°` lado a lado, atualizado junto
  com o polling. Pode ser desligado na aba "Configurações" → "Menu bar" (o
  ícone volta a ser só o símbolo do app). Os ícones são emojis, não SF
  Symbols — `MenuBarExtra` corta silenciosamente qualquer label composto por
  múltiplos `Image`/`Text` (mesmo texto puro em várias linhas some após a
  primeira), então tudo é concatenado em um único `Text`. Pelo mesmo motivo
  de altura, não existe uma variante empilhada verticalmente — a altura do
  item da status bar é travada na altura padrão da menu bar.
- **Gráficos de série temporal** (aba "Monitoramento"): CPU e memória do
  sistema ao longo do tempo, usando Swift Charts sobre o histórico já
  coletado por `SystemMonitorViewModel`.
- **Performance Mode**: tenta priorizar (`setpriority`, nice mais baixo) o app
  em primeiro plano e reduz a prioridade de apps ociosos em background a cada
  10s. Restaura as prioridades originais ao desligar. Aumentar a prioridade do
  app em primeiro plano normalmente exige privilégios de administrador — se
  falhar, o app avisa em vez de travar (a redução de prioridade em background
  não exige privilégios e continua funcionando).
- **Detecção de zumbis**: processos em estado `Zombie` aparecem destacados na
  sidebar (com contagem) e podem ser filtrados na tabela; cada novo zumbi
  detectado é registrado no log de ações.
- **AppleScript**: dois comandos expostos via `AirOptimizer.sdef`:
  - `tell application "AirOptimizer" to quick boost` → libera memória
    inativa do sistema (sem retorno, sem encerrar processos).
  - `tell application "AirOptimizer" to system stats` → retorna um resumo em
    texto (`"CPU: 12% | Memória: 45% | Processos: 400"`).
- **Agendador de limpeza automática** (aba "Configurações"): roda o Quick
  Boost sozinho em um intervalo configurável (padrão 2h).

## Segurança

- Processos críticos do sistema são bloqueados no nível do serviço, não
  apenas na UI — `ProcessManager.terminate` lança um erro mesmo se chamado
  diretamente.
- Toda ação destrutiva exige confirmação explícita na UI, mostrando PID e
  caminho completo do processo antes do encerramento.
- O app não requer privilégios elevados; ações em processos de outros
  usuários falham com uma mensagem de erro clara em vez de travar.

## Status / limitações conhecidas

- `swift test` requer Xcode completo instalado (XCTest não está disponível
  apenas com as Command Line Tools).
- AppleScript e notificações só funcionam quando o app roda como um bundle
  `.app` de verdade (`./Scripts/build_app.sh`) — `swift run` sozinho não tem
  `Info.plist`/bundle identifier, e as notificações ficam silenciosamente
  desabilitadas nesse modo (ver `NotificationCenterHelper`).
- Tema customizável e Scripting Bridge/AppleScript com propriedades de
  leitura direta (via KVC em `NSApp.delegate`) não foram implementados: o
  `@NSApplicationDelegateAdaptor` do SwiftUI encapsula o delegate em um proxy
  interno, o que quebra a técnica clássica de `class-extension` no `.sdef`;
  por isso as estatísticas são expostas como o comando `system stats` em vez
  de propriedades diretas.

## Como testar cada funcionalidade

```bash
./Scripts/build_app.sh
open AirOptimizer.app
```

1. **Dashboard / gerenciamento de processos**: na aba "Processos", busque um
   app, clique em SIGTERM/SIGKILL num processo não-crítico e confirme no
   diálogo. Tente encerrar `WindowServer` ou `Finder` — deve ser bloqueado
   com uma mensagem explicativa. Note o ícone + nome amigável na coluna
   "Nome" (o nome técnico só aparece como legenda quando diverge).
2. **Quick Boost**: abra alguns apps quaisquer (ex. TextEdit, Calculadora)
   sem trazê-los para frente:
   ```bash
   open -a "TextEdit" -g && open -a "Calculator" -g
   ```
   Clique em "Quick Boost" na sidebar (ou no menu bar) — deve pedir
   autenticação de administrador (diálogo nativo do macOS) e depois liberar
   memória inativa. **Nenhum app deve fechar** — TextEdit e Calculadora
   continuam abertos. O mesmo vale via `osascript -e 'tell application
   "AirOptimizer" to quick boost'` ou pelo agendador de limpeza.
3. **Aba "Configurações"**: clique na aba no topo da janela principal. Mexa
   no intervalo de auto-refresh ou no limiar de memória e veja o efeito
   imediato (o timer de polling reinicia sozinho).
4. **Menu bar**: o ícone na barra de status deve mostrar `🖥CPU% | 💾RAM% |
   🌡Temp°` (se a SMC não expuser temperatura neste Mac, aparece "--°" em vez
   de travar). Clique nele — deve abrir o painel com CPU/memória dos
   processos que mais consomem, e só três botões: Quick Boost, Configurações
   (abre a janela já na aba certa) e Sair. Em Configurações → "Menu bar",
   desligue o toggle e confirme que o ícone volta a ser só o símbolo do app.
5. **Gráficos**: aba "Monitoramento". Espere ~10-15s (algumas amostras) para
   as linhas de CPU/memória aparecerem.
6. **Performance Mode**: ative o toggle na aba Configurações. Abra o Activity
   Monitor e compare o "nice" de um app em background antes/depois (coluna
   configurável em Activity Monitor > View > Columns). Desative e confirme
   que os valores voltam ao normal.
7. **Zumbis**: difícil de gerar sob demanda; se a seção "Processos zumbi"
   aparecer na sidebar, o toggle "Mostrar apenas zumbis" filtra a tabela para
   eles, e cada novo zumbi gera uma entrada no log de ações.
8. **AppleScript**:
   ```bash
   osascript -e 'tell application "AirOptimizer" to system stats'
   osascript -e 'tell application "AirOptimizer" to quick boost'
   ```
9. **Agendador de limpeza**: ative na aba Configurações, ajuste o intervalo
   para o mínimo (0.5h = 30min) só para testar mais rápido, e aguarde —
   "Última execução" aparece logo abaixo do Stepper após rodar.
10. **Notificação de memória alta**: na aba Configurações, arraste o slider
    "Alerta de memória" para um valor abaixo do uso atual e observe o banner
    de notificação do macOS.

## Licença

MIT — veja [LICENSE](LICENSE).

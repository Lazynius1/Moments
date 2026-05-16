# Roadmap de Expansão de Localização

## Objetivo
Expandir a localização do Moments de forma controlada, começando pelos idiomas com melhor equilíbrio entre impacto e manutenção:

- `fr`
- `de`
- `it`
- `pt-BR`
- `pt-PT`

A ideia não é apenas “traduzir strings”, mas criar uma base sustentável para continuar a expandir idiomas sem comprometer a UI, as notificações ou a consistência do produto.

## Estado atual
- Idiomas ativos no projeto:
  - `en`
  - `es`
  - `ca`
- Superfícies localizadas identificadas:
  - app principal: `Glowsy/*.lproj`
  - widget: `GlowsyWidgetExtension/*.lproj`
  - `InfoPlist.strings` da app principal
- Ainda não existem `stringsdict` nem metadados da App Store no repositório.

## Fase 1
Idiomas alvo:

- [x] `fr` — estrutura criada
- [x] `de` — estrutura criada
- [x] `it` — estrutura criada
- [x] `pt-BR` — estrutura criada
- [x] `pt-PT` — estrutura criada

### Progresso atual
- `fr`
  - [x] `InfoPlist.strings` traduzido
  - [x] Widget / Live Activity traduzidos
  - [x] `WhatsNew 2.11` traduzido
  - [x] Textos de `gentle reminders` e definições recentes traduzidos
  - [ ] Tradução completa de `Localizable.strings`
- `de`
  - [x] `InfoPlist.strings` traduzido
  - [x] Widget / Live Activity traduzidos
  - [x] `WhatsNew 2.11` traduzido
  - [x] Textos de `gentle reminders` e definições recentes traduzidos
  - [~] `Localizable.strings` ampliado nas superfícies visíveis e blocos principais
- `it`
  - [x] `InfoPlist.strings` traduzido
  - [x] Widget / Live Activity traduzidos
  - [x] `WhatsNew 2.11` traduzido
  - [x] Textos de `gentle reminders` e definições recentes traduzidos
  - [x] Superfícies visíveis iniciais de `Localizable.strings` traduzidas (`story/reveal`, `story chains`, `audience/common`, `profile`, `settings`, `creator`, `feed`, `explore`, `stories`)
  - [x] Blocos de engagement e suporte traduzidos (`polls`, `questions`, `notifications`, `report`, `appeal`, `time`, `Nova`)
  - [x] Tradução completa de `Localizable.strings`
- `pt-BR`
  - [x] `InfoPlist.strings` traduzido
  - [x] Widget / Live Activity traduzidos
  - [x] `WhatsNew 2.11` traduzido
  - [x] Textos de `gentle reminders` e definições recentes traduzidos
  - [x] Blocos visíveis iniciais de `Localizable.strings` traduzidos (`story/reveal`, `story chains`, profile, creator, feed, explore, stories, notificações)
  - [x] Tradução completa de `Localizable.strings`
- `pt-PT`
  - [x] `InfoPlist.strings` traduzido
  - [x] Widget / Live Activity traduzidos
  - [x] `WhatsNew 2.11` traduzido
  - [x] Textos de `gentle reminders` e definições recentes traduzidos
  - [ ] Tradução completa de `Localizable.strings`
  - [x] Superfícies visíveis iniciais traduzidas (`story/reveal`, `story chains`, `profile`, `creator`, `feed`, `explore`, `stories`, notificações)
  - [x] Bloco de stickers `Reveal` / `Quiz` / `Polaroid` traduzido
  - [x] Bloco de `Hidden Layers` traduzido

## Checklist técnico por idioma
### Projeto
- [x] Adicionar idioma a `knownRegions` em [Glowsy.xcodeproj/project.pbxproj](/Users/lazynius/Desktop/MacMini/Nueva/Glowsy/Glowsy.xcodeproj/project.pbxproj)
- [ ] Verificar se o Xcode reconhece corretamente o locale
- [ ] Confirmar fallback para `en` se faltar alguma key

### App principal
- [x] Criar pasta `Glowsy/<locale>.lproj`
- [x] Duplicar base de `Localizable.strings`
- [x] Duplicar base de `InfoPlist.strings`
- [ ] Traduzir `Localizable.strings`
- [ ] Traduzir `InfoPlist.strings`
- [ ] Rever chaves novas introduzidas em releases recentes antes de fechar o idioma

### Widget
- [x] Criar pasta `GlowsyWidgetExtension/<locale>.lproj`
- [x] Duplicar base de `Localizable.strings`
- [ ] Traduzir `Localizable.strings`
- [ ] Verificar textos de Live Activity e widget

### Notificações
- [ ] Rever títulos e corpos localizados usados por Functions
- [ ] Confirmar se as novas keys de push existem também nesse idioma
- [ ] Validar textos longos em notificações e lembretes

### QA visual
- [ ] Rever layouts com textos longos
- [ ] Rever settings, sheets, botões e pills
- [ ] Rever `WhatsNew`
- [ ] Rever notificações e banners, se aplicável
- [ ] Rever widget em dispositivo ou simulador

## Anglicismos permitidos
Nem toda ocorrência em inglês precisa de ser eliminada. Alguns termos podem ficar como naming de produto, convenção de plataforma ou label curta reconhecível:

- produto / features:
  - `Moments`
  - `Stories`
  - `Posts`
  - `Echo`
  - `Nova`
  - `Reveal`
  - `Polaroid`
- plataforma / sistema:
  - `Passkey`
  - `PLUS`
  - `OK`
- termos curtos aceitáveis dependendo do contexto:
  - `Photo`
  - `Video`
  - `Tags`
  - `Question`

Regra prática:
- se o termo soar a nome da funcionalidade, componente visual ou convenção do ecossistema Apple/social, pode ficar
- se for frase inteira, empty state, CTA, erro, descrição, ajuda ou copy emocional, deve ser traduzido

## QA linguística
Antes de fechar um idioma, não basta contar linhas “diferentes de `en`”. Rever também:

- frases inteiras ainda em inglês
- CTAs e botões em inglês
- erros, estados vazios e placeholders
- labels longos em settings e sheets
- mistura estranha entre tradução local e inglês técnico
- consistência de tom nas funções sensíveis do produto:
  - `gentle reminders`
  - `WhatsNew`
  - hidden layers
  - moderação
  - Nova

## Riscos a vigiar
- `de` pode romper layouts por causa da extensão dos textos.
- `fr` e `pt-BR` tendem a crescer em botões e textos descritivos.
- `pt-BR` e `pt-PT` têm de permanecer separados desde o início.
- Não misturar tradução “rápida” com copy emocional sem revisão; o Moments depende bastante do tom.

## Ordem recomendada
### Lote 1
- [ ] `fr`
- [ ] `de`
- [ ] `it`
- [x] `pt-BR`
- [ ] `pt-PT`

### Lote 2
- [ ] `nl`
- [ ] `pl`
- [ ] `ro`
- [ ] `el`
- [ ] `hu`

### Lote 3
- [ ] `cs`
- [ ] `sk`
- [ ] `sl`
- [ ] `hr`
- [ ] `bg`
- [ ] `et`
- [ ] `lv`
- [ ] `lt`

## Critérios de encerramento de um idioma
- [ ] App principal traduzido
- [ ] Widget traduzido
- [ ] `InfoPlist.strings` traduzido
- [ ] Pushes/lembranças cobertos
- [ ] Revisão visual feita
- [ ] Sem textos truncados evidentes
- [ ] Sem keys em falta detectadas em uso normal

## Nota de produto
A prioridade inicial não é cobrir metade da Europa de uma vez, mas abrir primeiro os idiomas maiores que mais podem ajudar distribuição, App Store e percepção de produto internacional. A expansão completa será feita por lotes para não degradar manutenção nem a qualidade do copy.

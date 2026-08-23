# Fatura da Casa

App de rateio das despesas de uma casa entre duas pessoas. Corte configurável — aqui, dia 20.

Roda no navegador, instala na tela inicial do Android e funciona sem internet.
Não precisa de servidor: são arquivos estáticos.

---

## Publicar no GitHub Pages

São cinco passos, uma vez só. Depois disso, atualizar é só trocar um arquivo.

> **Antes de tudo:** o Pages em conta gratuita só funciona com repositório **público**.
> E mesmo repositório privado não esconderia o código: como o site é estático, qualquer
> pessoa lê o conteúdo pelo "exibir código-fonte" da página. Por isso **este código não
> contém nenhum dado de vocês** — nem nomes, nem valores. Tudo isso é colado no app,
> uma vez, em cada aparelho, e fica só ali.

### 0. Use o Chrome, não o app do GitHub

O aplicativo do GitHub para Android não envia arquivos. Abra `github.com` no **Chrome**,
menu ⋮ → marque **Site para computador**, e faça login.

### 1. Criar o repositório

Botão **+** no canto superior direito → **New repository**.

- **Repository name:** `fatura-da-casa`
- Marque **Public** *(obrigatório para o Pages gratuito)*
- **Não** marque "Add a README file"
- **Create repository**

Se você já criou como privado: **Settings** → role até o fim → **Change visibility**
→ **Change to public**.

### 2. Enviar os arquivos

Baixe o `.zip` e descompacte no app **Meus Arquivos** do Android: toque no arquivo →
**Extrair** → escolha a pasta Download.

Na página do repositório, no quadro azul, toque em **enviando um arquivo existente**
(*uploading an existing file*, se estiver em inglês). Depois em **escolher seus arquivos**,
selecione os **oito arquivos** de uma vez — todos estão soltos, sem subpasta.

Arraste para lá **o conteúdo** desta pasta — não a pasta em si:

```
index.html            manifest.webmanifest      sw.js
README.md             favicon.png               icon-192.png
icon-512.png          icon-maskable-512.png
```

Desça a página e clique em **Commit changes**.

### 3. Ligar o Pages

No repositório: **Settings** (engrenagem no topo) → no menu da esquerda, **Pages**.

- **Source:** Deploy from a branch
- **Branch:** `main` · pasta `/ (root)`
- **Save**

### 4. Pegar o endereço

Espere de um a dois minutos e recarregue a página do Pages. Vai aparecer:

```
https://SEU-USUARIO.github.io/fatura-da-casa/
```

Esse é o endereço do app. Mande para a outra pessoa da casa também.

### 5. Instalar no celular e carregar os dados

Abra o endereço no **Chrome do Android**. Vai aparecer uma faixa escura no topo
com o botão **Instalar** — ou use o menu ⋮ → **Adicionar à tela inicial**.

Pronto: ícone na tela inicial, abre em tela cheia, funciona sem internet.

Na primeira abertura o app pede os **dados de partida**. Cole o bloco de texto que veio
junto com este pacote — ele traz os nomes, o dia de corte, as oito despesas fixas e as
quatorze parcelas em aberto. Esse bloco **não vai para o GitHub**: fica só no aparelho.

Faça o mesmo no outro aparelho, com o mesmo bloco.

---

## Atualizar depois

**Settings** não, dessa vez. No repositório, clique em `index.html` → ícone de
lápis (**Edit**) → cole a versão nova → **Commit changes**.

Em um minuto o app novo está no ar. Como o service worker busca a rede antes do
cache, o aparelho pega a versão nova sozinho assim que tiver conexão — não fica
preso numa cópia velha.

---

## Sobre os dados

Ficam **só no aparelho**, no armazenamento do navegador. O código publicado não tem
nome nem valor nenhum de vocês — só o motor de cálculo e as telas. Consequências:

- Um aparelho não vê o que o outro lança. Ainda não há sincronização.
- Limpar os dados do site no Chrome apaga os lançamentos.
- Desinstalar o app da tela inicial **não** apaga.
- Em **Copiar meus dados**, no rodapé do app, você gera um texto com tudo. Serve de cópia
  de segurança e é como levar a configuração para outro aparelho.

A sincronização é o próximo passo. Vai usar o Render: um banco PostgreSQL e um
serviço pequeno para conversar com ele. Quando chegar lá, o formato dos dados já
está pronto — cada lançamento tem identificador próprio, marca de tempo de criação
e alteração, e exclusão lógica em vez de sumir do registro. É o que a sincronização
precisa para resolver conflito sem perder nada.

---

## O que já vem preenchido

Depois de carregar os dados de partida:

**Oito despesas fixas**, geradas a cada ciclo novo com valor estimado, esperando
confirmação. A base de cada estimativa aparece na própria linha — mediana do
histórico, valor constante, ou último valor quando houve mudança de patamar.

**As parcelas em aberto**, com o número da parcela calculado pelo ciclo. Uma compra
em 5/12 neste mês vira 6/12 no mês que vem sozinha, e some ao chegar na última.

Quando o dia 20 passar, o ciclo seguinte nasce já com tudo isso dentro.

---

## Arquivos

| Arquivo | O que faz |
|---|---|
| `index.html` | O app inteiro: motor de cálculo, telas e armazenamento |
| `manifest.webmanifest` | Nome, cores e ícones para a instalação |
| `sw.js` | Faz funcionar sem internet |
| `icon-*.png`, `favicon.png` | Ícones do app |

O bloco marcado `MOTOR` dentro do `index.html` é o mesmo da bancada de aferição,
sem uma linha alterada. São as funções que decidem quem deve quanto a quem, e elas
passam nos 27 casos de teste da Fase 1.

# Registro de mudanças

Todas as mudanças relevantes estão aqui. O formato segue o [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e o projeto usa [Versionamento Semântico](https://semver.org/lang/pt-BR/). Os nomes de botões e menus ficam em inglês, como no app. A versão em inglês, [CHANGELOG.md](CHANGELOG.md), é a de referência.

## [Unreleased]

## [0.3.0] - 2026-10-28

### Adicionado
- Notas: cada projeto tem post-its, texto livre em quadrados coloridos para coisas que vale lembrar e que não são tarefas. Crie uma com Note no cabeçalho do quadro; elas ficam numa coluna Notes antes das listas (numa faixa acima das faixas de importância com Group by importance). As bolinhas sob a nota mudam a cor, o menu Aa alterna o texto entre pequeno e médio, e uma nota excluída volta por Recently deleted. As notas aparecem na busca (⌘K), e Duplicate project as copia.
- Links na descrição de um cartão ou numa nota são clicáveis: um clique num link o abre, e um clique em qualquer outro lugar edita. Os links aparecem quando você sai do campo depois de digitar ou colar um endereço. O Boto reconhece endereços web, endereços `www.`, endereços com caminho e e-mails, e lê links em Markdown como `[título](https://...)`. Nomes de arquivo como `README.md` continuam texto, só links web e de e-mail abrem, e clicar no texto volta a editá-lo.
- Colar numa descrição ou numa nota mantém os links copiados de um e-mail ou de uma página web, em que o endereço fica escondido atrás de um título: eles são colados como `[título](endereço)`. As páginas web só são lidas à procura de links e nunca são carregadas.
- Os anexos mostram o ícone do tipo de arquivo, o nome do tipo ("PDF document", "Folder", "Obsidian note") e a pasta em que estão. Um arquivo ausente mantém o ícone, com um aviso. Dê um duplo clique num anexo para abri-lo, ou clique com o botão direito para Open, Reveal in Finder, Copy path e Remove.
- MCP: `list_notes` e `create_note`, e `search` também encontra notas.

### Alterado
- O quadro se adapta ao espaço que tem, e não só ao tamanho da janela: todos os botões com texto quando largo, só ícones quando mais estreito, e uma coluna de listas com Group by importance, Flow e Hours no menu ... quando muito estreito. As janelas Hours, Flow e Help podem ser redimensionadas.
- O menu ... do cabeçalho do quadro tem só opções do quadro (mostrar arquivados, adicionar cartões com data ao Apple Calendar). As opções do projeto ficam no menu do projeto, na barra lateral, então nada é oferecido duas vezes.
- O `boto-mcp` informa a versão do app em que vem.

### Segurança
- O Boto e o `boto-mcp` se recusam a abrir um banco de dados que tem dados de uma versão mais nova, em vez de migrá-lo e perder esses dados. Um banco ocupado é esperado e depois recusado, nunca liberado sem verificação.

## [0.2.0] - 2026-10-27

### Adicionado
- Duplicate project, no menu do projeto: uma cópia com os mesmos quadros, listas, etiquetas, checklists e cartões, ou Duplicate without cards para um modelo vazio. Horas, atividade e vínculos com o Apple Calendar ficam com o original.
- `boto-mcp`, um servidor MCP dentro do app para assistentes de IA: ler quadros, cartões e horas, e criar, editar, mover e arquivar cartões, duplicar projetos, marcar itens de checklist e lançar tempo. Ele só lê, a menos que seja iniciado com `--allow-writes`, e não tem ferramenta de exclusão.
- Ícones de projeto: escolha um do conjunto Lucide (cerca de 1.900, licença ISC) com busca por nome ou tema, ou deixe com o Boto. Na barra lateral, clique com o botão direito num projeto e escolha Change icon.
- Recently deleted: uma entrada na barra lateral que lista projetos, listas e cartões excluídos e restaura cada um. Uma lista volta com seus cartões.

### Alterado
- Relatório de horas: atalhos de período com o intervalo escolhido marcado, uma barra para cada dia e cartão, lançamentos agrupados por dia com subtotal, e exclusão ao passar o mouse.
- O formulário "Add time" abre sob demanda no relatório e aceita um tempo digitado ("1:30", "1.5", "90m", "2h30") em vez de botões de incremento. Return adiciona o lançamento.
- Os assuntos dos commits seguem o Conventional Commits, verificados por um hook e pelo CI em pull requests.
- README agrupado por tema, com capturas novas da janela Hours inteira e do relatório.
- As cores de status (concluído, em andamento, aviso, perigo) ficam no tema, e o progresso e um cronômetro em andamento usam um só azul.
- O título do cartão ficou menor (20 pt, semibold), em proporção com o texto ao redor.
- A Ajuda tem um tópico AI assistants com o comando que conecta o servidor MCP e um botão que o copia. O texto da Ajuda agora pode ser selecionado e copiado.
- Excluir uma lista ou um cartão pergunta antes, e o aviso da lista diz quantos cartões vão junto.

### Corrigido
- Não era possível definir a cor de um cartão novo. Agora é um botão próprio ao lado de Labels e Dates.
- Uma exportação de CSV que falha agora avisa, em vez de ficar em silêncio.
- Os botões só com ícone têm nomes falados, e cartões, resultados de busca e linhas de projeto são anunciados como botões.
- O botão de excluir no relatório de horas também aparece com o foco do teclado.

### Segurança
- Os releases esperam aprovação pelo ambiente `release`, que só aceita tags `v*`.

## [0.1.0] - 2026-10-27

### Adicionado
- Projetos, quadros, listas e cartões com etiquetas, cores, checklists, datas de vencimento e referências a arquivos, notas do Obsidian, itens do GitHub e mensagens do Mail.
- Importação do Trello e do GitHub, backups diários, busca, filtros e uma paleta de comandos.
- Métricas de fluxo, limites de WIP, cartões bloqueados e um registro Kaizen.
- Controle de tempo com cronômetro no cartão, folha de horas semanal, relatório e exportação em CSV.
- Sincronização de datas de vencimento com o Apple Calendar, com horário e alerta opcionais.
- Plus Jakarta Sans como fonte da interface.

### Segurança
- As exportações em CSV neutralizam campos que começam com `=`, `+`, `-`, `@`, tabulação ou retorno de carro.

[Unreleased]: https://github.com/paulo-amaral/boto/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/paulo-amaral/boto/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/paulo-amaral/boto/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/paulo-amaral/boto/releases/tag/v0.1.0

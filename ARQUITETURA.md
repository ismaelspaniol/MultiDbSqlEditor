# Arquitetura do Código Fonte — MultiDbSqlEditor

Este documento descreve a organização, as camadas, os módulos e os principais fluxos do **MultiDbSqlEditor** (Free Pascal / Lazarus, compatível com Firebird e PostgreSQL).

---

## 1. Visão Geral (Clean Architecture)

O projeto segue uma separação em **4 camadas**, com dependências apontando sempre para o núcleo (`Domain`):

```mermaid
flowchart TD
    P["Presentation (src/Presentation)<br/>Forms, Frames, SynEdit, Grids"]
    A["Application (src/Application)<br/>Casos de Uso, Workers Async, Comparador"]
    D["Domain (src/Domain)<br/>Entidades, Interfaces, Tipos, PSQL Debugger"]
    I["Infrastructure (src/Infrastructure)<br/>Firebird (SQLdb), PostgreSQL (mORMot2), JSON"]

    P --> A
    P --> D
    A --> D
    I --> D
```

- **Regra de dependência:**
  - `Domain` não depende de nenhuma camada de UI ou banco.
  - `Application` orquestra regras de negócio usando apenas interfaces de `Domain`.
  - `Infrastructure` implementa as interfaces de `Domain` (`IDatabaseProvider`, `IDatabaseSession`, `IConnectionRepository`).
  - `Presentation` cuida apenas da interface gráfica (LCL / `SynEdit` / `TStringGrid`).

---

## 2. Estrutura de Diretórios e Units

### 2.1 Domain (`src/Domain/`)

| Unit | Responsabilidade |
| :--- | :--- |
| `Domain.DatabaseTypes.pas` | Enums e tipos básicos (`TDatabaseType`, `TFirebirdVersion`, `TSchemaObjectKind`, `QuoteDbIdent`, etc.). |
| `Domain.ConnectionProfile.pas` | Classe `TConnectionProfile` (dados de conexão, `Clone`, `Validate`, parser de connection string Firebird). |
| `Domain.Interfaces.pas` | Contratos principais: `IDatabaseSession`, `IDatabaseProvider`, `IDatabaseProviderFactory`, `IConnectionRepository`. |
| `Domain.QueryResult.pas` | `TQueryResult`, `IResultSetCursor` (paginação sob demanda), proteção de memória RAM do SO (`GetSystemMemoryInfo`) e estatísticas de performance. |
| `Domain.PsqlDebugger.pas` | **Interpretador / Debugger PSQL Firebird** (tokenizer, AST, pilha de frames, avaliador de expressões, breakpoints, captura de campos e `SUSPEND`). |
| `Domain.DatabaseCompareTypes.pas` | Modelos de comparação de schemas (`TCompareOptions`, `TCompareDiffItem`, `TCompareResult`, categorias e status). |
| `Domain.TableStructureTypes.pas` | Estruturas de tabela (`TTableStructure`, `TTableColumnInfo` com `Description`, `TTableIndexInfo`, `TTableForeignKeyInfo`, `UniqueConstraints`, `CheckConstraints`). |
| `Domain.SqlAliasResolver.pas` | Extração de aliases SQL para autocompletar inteligente. |
| `Domain.ScriptExecutionTypes.pas` | Tipos de execução em lote para o Script Executive. |
| `Domain.MonitoringTypes.pas` | Tipos do monitor de conexões e transações ativas. |
| `Domain.MaintenanceTypes.pas` | Tipos de Backup / Restore / Repair (Firebird Services). |

---

### 2.2 Application (`src/Application/`)

| Unit | Responsabilidade |
| :--- | :--- |
| `Application.ManageConnectionsUseCase.pas` | CRUD e reordenação de perfis de conexão (`Save`, `Delete`, `Reorder`, `ListAll`). |
| `Application.TestConnectionUseCase.pas` | Teste de conectividade antes de salvar uma conexão. |
| `Application.ExecuteQueryUseCase.pas` | Execução de consultas SQL em sessão ativa. |
| `Application.AsyncQueryRunner.pas` | Thread em background para execução assíncrona de queries no editor SQL. |
| `Application.BrowseSchemaUseCase.pas` | Leitura de objetos do banco (tabelas, views, procedures, triggers, generators) para o TreeView. |
| `Application.ManageTableStructureUseCase.pas` | Leitura/alteração de estrutura de tabelas e helpers de DDL (`BuildAddColumnDDL`, `BuildEditColumnDDL`, `StripLeadingDefaultKeyword`). |
| `Application.ManageDatabaseObjectsUseCase.pas` | Extração de DDL, compilação/alteração, exclusão, metadados de procedures (`LoadProcedureMetadata`), execução (`ExecuteProcedure`) e fábrica de sessão (`CreateSession`). |
| `Application.DatabaseComparerUseCase.pas` | **Database Comparer:** captura snapshot em lote (tabelas, colunas, comentários `RDB$DESCRIPTION`, `COMPUTED BY`, `PK`, `UNIQUE`, `CHECK`, `FK`, índices, generators, views, procedures com `DEFAULT` de parâmetros e triggers), ordena Views/Procedures por dependência (`SortCodeItemsByDependency`), gera o script de migração e aplica em transação única via `TApplyCompareScriptWorker`. |
| `Application.ScriptExecutorUseCase.pas` | Execução de scripts multi-comando (com suporte a `SET TERM` no Firebird). |
| `Application.DatabaseMonitoringUseCase.pas` | Consulta e encerramento de sessões/transações ativas no banco. |
| `Application.DatabaseMaintenanceUseCase.pas` | Orquestração de Backup, Restore e validação/correção. |

---

### 2.3 Infrastructure (`src/Infrastructure/`)

| Unit | Responsabilidade |
| :--- | :--- |
| `Infrastructure.ProviderFactory.pas` | Seleciona o `IDatabaseProvider` adequado (`dtFirebird` ou `dtPostgreSQL`). |
| `Infrastructure.FirebirdSqlDbProvider.pas` | Provedor Firebird via `SQLdb` (`TIBConnection` / `TSQLQuery`), carregamento dinâmico de `fbclient.dll` (2.5 a 5.0, win32/win64), cursor paginado, plano de execução (`isc_dsql_sql_info`) e contadores de I/O. |
| `Infrastructure.MormotPostgresProvider.pas` | Provedor PostgreSQL via **mORMot2** (`libpq.dll`). |
| `Infrastructure.FirebirdServicesRunner.pas` | Integração com serviços de manutenção Firebird (Backup/Restore/Repair). |
| `Infrastructure.JsonConnectionRepository.pas` | Persistência das conexões em JSON. |
| `Infrastructure.JsonWorkspaceRepository.pas` | Persistência das abas abertas e layout em `workspace.json`. |

---

### 2.4 Presentation (`src/Presentation/`)

| Unit | Responsabilidade |
| :--- | :--- |
| `Presentation.MainForm.pas` / `.lfm` | Janela principal, árvore de conexões (com menu de contexto incluindo **Duplicar Conexão**), gerenciamento de abas (`pgEditors`) com fechamento via `×` no Windows e botão do meio do mouse. |
| `Presentation.TabHelpers.pas` | Helpers multiplataforma para exibir o sufixo `×` nas abas no Windows (`LCLwin32`, onde `nboShowCloseButtons` não é nativo) sem poluir os títulos internos. |
| `Presentation.SqlEditorFrame.pas` / `.lfm` | Editor SQL com `TSynEdit`, autocompletar (`Ctrl+Espaço`), execução assíncrona (`F9`), controle transacional (`Commit`/`Rollback`/`Auto Commit`), barra divisória (`Splitter1`) ajustável entre editor e resultados. |
| `Presentation.QueryResultGridFrame.pas` / `.lfm` | Grid paginado de resultados, ordenação, exportação CSV e redimensionamento de colunas e linhas. |
| `Presentation.ObjectEditorFrame.pas` / `.lfm` | Editor de Views, Procedures, Triggers, Generators e visualização DDL de Tabelas. Inclui indicador visual de alteração pendente no botão `* Compilar / Salvar (F9)`, execução de procedures com **Commit / Rollback / Auto Commit** e botão **Debug (F7)** para Firebird. |
| `Presentation.ProcedureParamsForm.pas` / `.lfm` | Diálogo de preenchimento de parâmetros de entrada ao executar ou debugar uma procedure. |
| `Presentation.ProcedureDebugForm.pas` / `.lfm` | **Janela de Debug PSQL estilo IBExpert** (Step Into `F7`, Step Over `F8`, Continuar `F9`, Até Cursor `F4`, Breakpoints `F5` ou clique na margem, inspetor de Variáveis/Parâmetros, Campos do Cursor atual, Resultados de `SUSPEND` e Log SQL). |
| `Presentation.DatabaseComparerFrame.pas` / `.lfm` | Interface do Database Comparer com persistência dos últimos parâmetros e altura do grid em `comparer_settings.json`. |
| `Presentation.TableEditorFrame.pas` / `Form` | Editor visual de estrutura de tabelas (colunas, PK, índices, FKs, triggers e dados). |
| `Presentation.ScriptExecutorFrame.pas` / `.lfm` | Executor de scripts SQL em lote. |
| `Presentation.DatabaseMonitorFrame.pas` / `.lfm` | Monitor de conexões/transações ativas. |
| `Presentation.DatabaseMaintenanceForm.pas` / `.lfm` | Tela de Backup/Restore/Repair. |
| `Presentation.ConnectionForm.pas` / `.lfm` | Cadastro e edição de perfis de conexão. |
| `Presentation.GeneratorForm.pas` / `.lfm` | Visualização e ajuste de Generators/Sequences. |
| `Presentation.SqlCompletionController.pas` | Controlador de autocompletar SQL sensível ao contexto e aliases. |

---

## 3. Fluxos Principais

### 3.1 Debug de Procedures Firebird (Estilo IBExpert)
Como o Firebird não possui protocolo nativo de debug no servidor, o debug funciona por **interpretação controlada no cliente**:

1. `TObjectEditorFrame.btnDebugClick` carrega os metadados (`LoadProcedureMetadata`) e, se houver parâmetros de entrada, abre `TProcedureParamsForm`.
2. `TProcedureDebugForm.Execute` abre a janela de debug e carrega o DDL em `TPsqlDebugger.LoadProcedure`:
   - `Tokenize` quebra o código PSQL em tokens preservando o número exato de cada linha.
   - `ParseHeaderAndDecls` registra parâmetros `IN`/`OUT`, variáveis locais (`DECLARE VARIABLE`) e variáveis de sistema (`ROW_COUNT`, `SQLCODE`).
   - `ParseStatement` monta a árvore de comandos (`BEGIN..END`, `IF/ELSE`, `WHILE`, `FOR SELECT ... INTO`, `SELECT ... INTO`, `SUSPEND`, DML, etc.).
3. Durante o passo a passo (`F7`/`F8`/`F9`/`F4`):
   - Expressões e atribuições são avaliadas no cliente (com fallback automático para `SELECT <expr> FROM RDB$DATABASE` para funções nativas do Firebird).
   - Comandos SQL internos (`SELECT`, `FOR SELECT`, `INSERT`, `UPDATE`, `DELETE`, `EXECUTE PROCEDURE`) têm suas `:variaveis` substituídas por literais SQL e são executados na sessão controlada do debugger (`AutoCommit = False`).
   - Ao final ou ao reiniciar, se **Rollback automático** estiver marcado, todas as alterações no banco são desfeitas.

### 3.2 Database Comparer (Comparação e Sincronização)
1. **Captura em lote (`CaptureSnapshot`):** executa poucas queries nas tabelas de sistema (`RDB$*` no Firebird ou `pg_*` no PostgreSQL) para carregar o schema inteiro rapidamente.
2. **Comparação (`CompareSnapshots`):**
   - Compara Generators, Tabelas, Colunas (tipo, `NOT NULL`, `DEFAULT`, `COMPUTED BY` e comentários `COMMENT ON COLUMN`), PKs, Índices, FKs, `UNIQUE` e `CHECK` (tratando nomes automáticos `INTEG_*` do Firebird sem duplicar constraints equivalentes).
   - Ordena **Views** e **Procedures** topologicamente por dependência (`SortCodeItemsByDependency`) para evitar erros de compilação quando uma procedure referencia outra.
3. **Aplicação (`TApplyCompareScriptWorker`):** divide o script (`SplitSqlScriptStatements`) removendo comentários iniciais e executa todos os comandos selecionados dentro de **uma única transação** (fazendo `ROLLBACK` automático em caso de erro).

---

## 4. Como Compilar

O projeto é compilado para Windows x64 (`x86_64-win64`) via Lazarus / `lazbuild`:

```powershell
& "C:\Lazarus\lazarus\lazbuild.exe" MultiDbSqlEditor.lpi
```

- **Saída:** `bin\MultiDbSqlEditor.exe`
- **Arquivos de configuração em runtime (na pasta `bin\`):**
  - `connections.json` — perfis de conexão salvos
  - `workspace.json` — abas SQL e estado da janela
  - `comparer_settings.json` — últimos parâmetros e altura do grid do Database Comparer

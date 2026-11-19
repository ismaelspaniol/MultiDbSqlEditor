# Multi-DB SQL Editor

Editor de consultas SQL multi-banco inspirado no IBExpert, desenvolvido em **Free Pascal + Lazarus + mORMot2**, com suporte inicial a **Firebird** e **PostgreSQL**.

## Arquitetura (Clean Architecture)

O código-fonte em `src/` é dividido em 4 camadas com dependências unidirecionais (`Presentation -> Application -> Domain <- Infrastructure`):

- `src/Domain/` — Entidades e interfaces puras (sem dependência de LCL ou mORMot2).
- `src/Application/` — Casos de uso (`TestConnection`, `ManageConnections`, `ExecuteQuery`).
- `src/Infrastructure/` — Implementações usando `mORMot2` (`mormot.db.sql.firebird`, `mormot.db.sql.postgres`) e persistência local.
- `src/Presentation/` — Formulários Lazarus (LCL), `SynEdit` e grid virtual de resultados.
- `tests/` — Testes unitários (`FPCUnit`).

## Requisitos de Desenvolvimento

1. **Lazarus / Free Pascal** (FPC 3.2.2+ recomendado).
2. **mORMot2** — Baixe o repositório oficial do `mORMot2` e adicione os diretórios `src/` do mORMot2 ao *Unit Search Path* do projeto no Lazarus.
3. **Bibliotecas Clientes (em tempo de execução):**
   - Firebird: `fbclient.dll`
   - PostgreSQL: `libpq.dll` (e dependências OpenSSL, se aplicável)

# Validação dos SQLs do PlugBot — SigeDash BR

**Data:** 2026-06-14
**Banco de teste:** `5ESTRELAS.FDB` (Firebird 2.5.9, ODS 11.2, 308 tabelas, 1,7 GB)
**Engine:** Firebird 2.5.9 embedded (x86-64), conexão única, sem concorrência.
**Período de dados:** 2022-10-04 → 2026-06-03 (CAIXA.DATAHORALANCAMENTO).

## Veredito: os 6 arquivos servem

As 37 queries dos 6 módulos **executam com sucesso** no banco real e usam **apenas sintaxe compatível com Firebird 2.5** (FIRST/SKIP, UNION, CASE, COALESCE, EXTRACT, CURRENT_DATE, LIST). Servem como spec de paridade da Fase 1 e como base de SQL do agente.

## Performance (33 de 37 abaixo de 0,5s)

| Query | Módulo | Tempo | Observação |
|---|---|---|---|
| Relação de custo e venda | vendas | **~3,0s** | pesada (3 períodos) |
| Saldo bancário | saldodiario | ~1,5s | 3 UNIONs |
| Ranking 5 categorias mais vendidas | vendas | ~1,5s | pesada (3 períodos) |
| Saldo dos caixas | saldodiario | ~0,7s | |
| Pico de vendas por horário | vendas | ~0,45s | 4 períodos |
| Demais 28 queries | todos | 0,03–0,38s | OK |

> Tempos medidos em SSD, conexão única, sem carga concorrente. **Em produção, com o SIGECOM batendo no mesmo Firebird, trate esses números como piso** — as pesadas podem subir.

## Diagnóstico das 4 queries pesadas

- Os **fatos grandes** (PEDIDO, PEDIDO_PRODUTO, CAIXA) são acessados **por índice** (PK e FKs) — não há scan em tabela grande.
- Os poucos `NATURAL` (full scan) caem em **tabelas-dimensão pequenas** (CONTA_BANCO, CAIXA_CONFIG, CLIENTE, PO/PD) — custo baixo, aceitável.
- O gargalo da "Relação de custo e venda" é **estrutural**: ~20 subqueries escalares (`SELECT ... FROM rdb$database`) refazendo a mesma agregação por faixa/período. Não é falta de índice.

## Riscos e ajustes para o agente (Fase 1)

1. **Cadência x custo.** O config roda essas pesadas a cada 5–10 min. São agregados **mensais** — não precisam de 5 min de frescor. Sugiro `sincronizacaoMinutos` de 30–60 min para custo×venda e categorias. Reduz carga no Firebird do cliente sem perda real de valor.
2. **`CODIGOEMPRESA = 1` hardcoded** em quase todas. Parametrizar no agente (multi-empresa).
3. **`cast(CX.DATAHORALANCAMENTO as date) = current_date`** anula range de índice por data. Onde a data não vier de PK/FK, trocar por `>= :data AND < :data+1`. Impacto baixo aqui (joins por PK), mas vale na futura expansão de indicadores.
4. **Senha do app em SHA-1** (módulo usuario). É a paridade atual; como vamos reescrever o backend, planejar hash mais forte (bcrypt/argon2) no nosso lado desde o início.
5. **Charset Latin1.** O banco devolve ISO-8859-1. O agente .NET deve abrir conexão com `Charset=ISO8859_1` (ou WIN1252) e converter para UTF-8 ao serializar o JSON — senão acentos quebram no PWA.

## Catálogo de indicadores (paridade Fase 1)

- **vendas:** pico por horário, total mês/semana/hoje, ranking meios de pagamento, top 5 clientes, top 5 produtos, top 5 categorias, top 5 vendedores, relação custo × venda.
- **financeiro:** contas a receber e a pagar (mês/semana/hoje).
- **estoque:** top 10 mais estoque (donut), abaixo do mínimo (barra).
- **produtos:** lista dos 100 com mais estoque.
- **saldodiario:** saldo dos caixas, saldo bancário.
- **usuario:** autenticação do app (login, senha, grupo, e-mail).

## Conclusão

Pode seguir com esses SQLs como base do agente. Antes de codar: (a) parametrizar empresa, (b) baixar a cadência das 2 pesadas, (c) fixar charset Latin1 na conexão. Nada bloqueia o início do esqueleto.

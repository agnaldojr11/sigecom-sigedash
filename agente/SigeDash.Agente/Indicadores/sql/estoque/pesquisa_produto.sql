/* Pesquisa de produtos: por VARIANTE (produto), com estoque, custo e precos por TABELA DE PRECO.
   @EMPRESA parametrizado.

   - GRADE: usa PRODUTO.NOME_COMPLETO (ja concatena cor/tamanho); cai p/ PRODUTO_BASE.NOME.
   - O PWA agrupa por "codProduto" (NAO pelo nome): existem produtos DISTINTOS com o mesmo
     NOME_COMPLETO (ex.: dois "BIQUINI ... AMARELO GG" de referencias diferentes). Agrupar por
     nome fundia os dois e mostrava chips de preco duplicados.
   - Tabelas de preco sao POR EMPRESA (PRODUTO_TABELA_PRECO.CODIGO_EMPRESA); a padrao e global
     (CODIGO_EMPRESA NULL). Filtramos pela empresa (ou global) para nao trazer tabela de outra loja.
   - Preco: usa o valor GRAVADO em PRODUTO_ESTOQUE_TABELA_PRECO. Se a tabela vale para todos os
     produtos e NAO ha valor gravado, DERIVA pela regra de desconto (REGRA=2 => padrao*(1-MARKUP/100)),
     replicando o que o SIGECOM calcula na tela (ex.: A vista 8% => 162,00 -> 149,04).
   - Markup e calculado no PWA a partir de custo x venda de cada tabela. */
SELECT
    P.CODIGOPRODUTO                                       AS "codProduto",
    COALESCE(NULLIF(TRIM(P.NOME_COMPLETO), ''), PB.NOME)  AS "label",
    TRIM(P.CODIGOINTERNO)                                 AS "codigo",
    TRIM(PG.NOMEGRUPO)                                    AS "categoria",
    PE.ESTOQUE                                            AS "estoque",
    PE.PRECOCUSTO                                         AS "custo",
    TP.CODIGO_TABELA_PRECO                                AS "codTabela",
    TRIM(TP.NOME_TABELA_PRECO)                            AS "tabela",
    COALESCE(
        PETP.PRECO_VENDA,
        CASE WHEN TP.REGRA = 2
             THEN CAST(PAD.PRECO_VENDA * (1 - TP.MARKUP / 100.0) AS NUMERIC(15,2)) END
    )                                                     AS "venda"
FROM PRODUTO_BASE PB
JOIN PRODUTO P          ON P.CODIGOBASEPRODUTO  = PB.CODIGOBASEPRODUTO
JOIN PRODUTO_ESTOQUE PE ON PE.CODIGOPRODUTO     = P.CODIGOPRODUTO
                       AND PE.CODIGOEMPRESA     = @EMPRESA
LEFT JOIN PRODUTO_GRUPO PG
                        ON PG.CODIGOGRUPO         = PB.CODIGOGRUPO
/* uma linha por tabela de preco ativa da empresa (ou global) */
CROSS JOIN PRODUTO_TABELA_PRECO TP
/* preco gravado desta mercadoria nesta tabela (se houver) */
LEFT JOIN PRODUTO_ESTOQUE_TABELA_PRECO PETP
                        ON PETP.CODIGO_MERCADORIA   = PE.CODIGOMERCADORIA
                       AND PETP.CODIGO_TABELA_PRECO = TP.CODIGO_TABELA_PRECO
/* preco padrao da mercadoria — base para derivar regras de desconto */
LEFT JOIN PRODUTO_ESTOQUE_TABELA_PRECO PAD
                        ON PAD.CODIGO_MERCADORIA   = PE.CODIGOMERCADORIA
                       AND PAD.CODIGO_TABELA_PRECO = (SELECT MIN(T2.CODIGO_TABELA_PRECO)
                                                        FROM PRODUTO_TABELA_PRECO T2
                                                       WHERE T2.PADRAO = 'S')
WHERE P.DESATIVADO = 'N'
  AND TP.ATIVADO = 'S'
  AND (TP.CODIGO_EMPRESA = @EMPRESA OR TP.CODIGO_EMPRESA IS NULL)
  /* inclui a tabela se: tem preco gravado (mesmo 0,00) OU e derivavel (todos os produtos + regra desconto) */
  AND (PETP.CODIGO_TABELA_PRECO IS NOT NULL
       OR (TP.TODOS_PRODUTOS = 'S' AND TP.REGRA = 2 AND PAD.PRECO_VENDA IS NOT NULL))
ORDER BY 2, 1, 7

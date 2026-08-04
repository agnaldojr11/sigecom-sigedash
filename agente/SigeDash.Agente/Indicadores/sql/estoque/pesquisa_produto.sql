/* Pesquisa de produtos: por VARIANTE (produto), com estoque, custo e precos por TABELA DE PRECO.
   @EMPRESA parametrizado. Uma linha por produto x tabela de preco ativa; o PWA agrupa por produto.

   GRADE: usa PRODUTO.NOME_COMPLETO, que ja vem com as caracteristicas concatenadas
   (ex.: "VESTIDO ... M PRETO"); cai para PRODUTO_BASE.NOME se NOME_COMPLETO estiver vazio.
   Agrupa por PRODUTO (variante), nao por PRODUTO_BASE, para listar cada cor/tamanho.

   Campos extras: codigo (CODIGOINTERNO) e categoria (PRODUTO_GRUPO.NOMEGRUPO).
   O markup e calculado no PWA a partir de custo x venda de cada tabela. */
SELECT
    COALESCE(NULLIF(TRIM(P.NOME_COMPLETO), ''), PB.NOME)  AS "label",
    TRIM(P.CODIGOINTERNO)                                 AS "codigo",
    TRIM(PG.NOMEGRUPO)                                    AS "categoria",
    MAX(PE.ESTOQUE)                                       AS "estoque",
    MAX(PE.PRECOCUSTO)                                    AS "custo",
    TP.CODIGO_TABELA_PRECO                                AS "codTabela",
    TRIM(TP.NOME_TABELA_PRECO)                            AS "tabela",
    MAX(PETP.PRECO_VENDA)                                 AS "venda"
FROM PRODUTO_BASE PB
JOIN PRODUTO P          ON P.CODIGOBASEPRODUTO  = PB.CODIGOBASEPRODUTO
JOIN PRODUTO_ESTOQUE PE ON PE.CODIGOPRODUTO     = P.CODIGOPRODUTO
                       AND PE.CODIGOEMPRESA     = @EMPRESA
LEFT JOIN PRODUTO_GRUPO PG
                        ON PG.CODIGOGRUPO         = PB.CODIGOGRUPO
LEFT JOIN PRODUTO_ESTOQUE_TABELA_PRECO PETP
                        ON PETP.CODIGO_MERCADORIA = PE.CODIGOMERCADORIA
LEFT JOIN PRODUTO_TABELA_PRECO TP
                        ON TP.CODIGO_TABELA_PRECO = PETP.CODIGO_TABELA_PRECO
                       AND TP.ATIVADO = 'S'
WHERE P.DESATIVADO = 'N'
GROUP BY P.CODIGOPRODUTO, P.NOME_COMPLETO, PB.NOME, P.CODIGOINTERNO,
         PG.NOMEGRUPO, TP.CODIGO_TABELA_PRECO, TP.NOME_TABELA_PRECO
ORDER BY 1, 6

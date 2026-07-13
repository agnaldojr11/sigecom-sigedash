/* Pesquisa de produtos: nome, estoque, custo e precos por TABELA DE PRECO. @EMPRESA parametrizado.
   Uma linha por produto x tabela de preco ativa; o PWA agrupa por produto e lista os precos.
   A maioria dos produtos tem so a tabela padrao; alguns tem varias (ex.: Avista/Usina/Aprazo).
   Sem FIRST: traz TODOS os produtos ativos (a busca por nome e feita no cliente). */
SELECT
    PB.NOME                         AS "label",
    MAX(PE.ESTOQUE)                 AS "estoque",
    MAX(PE.PRECOCUSTO)              AS "custo",
    TP.CODIGO_TABELA_PRECO          AS "codTabela",
    TRIM(TP.NOME_TABELA_PRECO)      AS "tabela",
    MAX(PETP.PRECO_VENDA)           AS "venda"
FROM PRODUTO_BASE PB
JOIN PRODUTO P          ON P.CODIGOBASEPRODUTO  = PB.CODIGOBASEPRODUTO
JOIN PRODUTO_ESTOQUE PE ON PE.CODIGOPRODUTO     = P.CODIGOPRODUTO
                       AND PE.CODIGOEMPRESA     = @EMPRESA
LEFT JOIN PRODUTO_ESTOQUE_TABELA_PRECO PETP
                        ON PETP.CODIGO_MERCADORIA = PE.CODIGOMERCADORIA
LEFT JOIN PRODUTO_TABELA_PRECO TP
                        ON TP.CODIGO_TABELA_PRECO = PETP.CODIGO_TABELA_PRECO
                       AND TP.ATIVADO = 'S'
WHERE P.DESATIVADO = 'N'
GROUP BY PB.CODIGOBASEPRODUTO, PB.NOME, TP.CODIGO_TABELA_PRECO, TP.NOME_TABELA_PRECO
ORDER BY PB.NOME, TP.CODIGO_TABELA_PRECO

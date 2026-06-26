/* Pesquisa de produtos: nome, estoque, custo e preco de venda. @EMPRESA parametrizado.
   Sem FIRST: traz TODOS os produtos ativos para que a busca no PWA encontre qualquer item
   (o filtro por nome e feito no cliente sobre o snapshot completo). */
SELECT
    PB.NOME                         AS "label",
    MAX(PE.ESTOQUE)                 AS "estoque",
    MAX(PE.PRECOCUSTO)              AS "custo",
    MAX(PETP.PRECO_VENDA)           AS "venda"
FROM PRODUTO_BASE PB
JOIN PRODUTO P          ON P.CODIGOBASEPRODUTO  = PB.CODIGOBASEPRODUTO
JOIN PRODUTO_ESTOQUE PE ON PE.CODIGOPRODUTO     = P.CODIGOPRODUTO
                       AND PE.CODIGOEMPRESA     = @EMPRESA
LEFT JOIN PRODUTO_ESTOQUE_TABELA_PRECO PETP
                        ON PETP.CODIGO_MERCADORIA = PE.CODIGOMERCADORIA
WHERE P.DESATIVADO = 'N'
GROUP BY PB.CODIGOBASEPRODUTO, PB.NOME
ORDER BY PB.NOME

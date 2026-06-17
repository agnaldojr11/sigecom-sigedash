/* Quantidade de produtos ativos com estoque zerado ou negativo. formato = qtd. */
SELECT
    COUNT(*) AS "value",
    'qtd'    AS "formato"
FROM PRODUTO_BASE PB
JOIN PRODUTO P          ON P.CODIGOBASEPRODUTO  = PB.CODIGOBASEPRODUTO
JOIN PRODUTO_ESTOQUE PE ON PE.CODIGOPRODUTO     = P.CODIGOPRODUTO
WHERE PE.CODIGOEMPRESA = @EMPRESA
  AND PE.ESTOQUE <= 0
  AND P.DESATIVADO = 'N'

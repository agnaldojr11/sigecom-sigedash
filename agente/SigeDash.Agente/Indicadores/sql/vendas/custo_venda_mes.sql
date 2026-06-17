/* Relacao custo x venda do mes: venda bruta, custo dos produtos e margem bruta.
   CTE calcula os totais uma vez; UNION ALL projeta como lista label/valor. */
WITH TOTAIS AS (
    SELECT
        SUM(PP.VALORTOTAL)               AS venda,
        SUM(COALESCE(PP.CUSTO_TOTAL, 0)) AS custo
    FROM PEDIDO P
    JOIN CAIXA CX          ON CX.CODIGOLANCAMENTO  = P.CODIGOLANCAMENTO
    JOIN PEDIDO_PRODUTO PP ON PP.CODIGOPEDIDO       = P.CODIGOPEDIDO
    JOIN PESSOA PESS       ON PESS.CODIGOPESSOA     = P.CODIGOPESSOA
    WHERE P.CODIGOEMPRESA = @EMPRESA
      AND (P.CODIGO_PEDIDO_TIPO NOT IN (4, 8) OR P.CODIGO_PEDIDO_TIPO IS NULL)
      AND P.CODIGO_PEDIDO_SITUACAO = 2
      AND P.CODIGOLANCAMENTO IS NOT NULL
      AND PESS.CODIGOTIPO = 1
      AND CX.DATAHORALANCAMENTO >= @INI_MES
      AND CX.DATAHORALANCAMENTO <  @FIM_MES
)
SELECT CAST('Venda total'    AS VARCHAR(20)) AS "nome", venda        AS "valor" FROM TOTAIS
UNION ALL
SELECT CAST('Custo produtos' AS VARCHAR(20)),             custo                  FROM TOTAIS
UNION ALL
SELECT CAST('Margem bruta'   AS VARCHAR(20)),             venda - custo          FROM TOTAIS

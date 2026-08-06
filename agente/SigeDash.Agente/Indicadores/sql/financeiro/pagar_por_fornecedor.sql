/* Contas a pagar abertas agrupadas por fornecedor — base para pesquisa no app.
   Retorna todos os titulos PENDENTE independente de data, para busca em tempo real no PWA.
   Tipos 3 (fornecedor) e 4 (outros) sao os credores tipicos no SIGECOM. */
SELECT FIRST 500
    P.NOME                 AS "label",
    SUM(CP.TOTAL)          AS "value",
    COUNT(*)               AS "parcelas",
    MIN(CP.DATAVENCIMENTO) AS "venc_mais_antigo"
FROM CONTA_PARCELA CP
JOIN CONTA C        ON C.CODIGOCONTA       = CP.CODIGOCONTA
JOIN PESSOA P       ON P.CODIGOPESSOA      = C.CODIGOPESSOA
JOIN PESSOA_TIPO PT ON PT.CODIGOTIPO       = P.CODIGOTIPO
JOIN CAIXA CX       ON CX.CODIGOLANCAMENTO = C.CODIGOLANCAMENTO
JOIN USUARIO U      ON U.CODIGOUSUARIO     = CX.CODIGOUSUARIO
WHERE CP.TOTAL > 0
  AND UPPER(CP.SITUACAO) = 'PENDENTE'
  AND CP.CODIGO_CONTA_CHEQUE IS NULL
  AND U.CODIGOEMPRESA = @EMPRESA
  AND (PT.CODIGOTIPO = 3 OR PT.CODIGOTIPO = 4)
GROUP BY P.CODIGOPESSOA, P.NOME
ORDER BY P.NOME

Usuário:

Select CodigoUsuario, Login, Senha_App, UG.Nome As Grupo, PC.Contato As Email From Usuario U Left Join Usuario_Grupo As UG On U.CodigoUsuarioGrupo = UG.CodigoUsuarioGrupo Left Join Pessoa As P On U.CodigoFuncionario = P.CodigoPessoa Left Join Pessoa_Contato As PC On P.CodigoPessoa = PC.CodigoPessoa And PC.CodigoTipo = 4 Where U.CodigoEmpresa = 1 And U.desativado='N'

Vendas:

Total de vendas do mês:
Select sum(P.VALORTOTAL) as "value", 'ion-calculator' As "icon"
    from PEDIDO P
    inner join PESSOA PESS on PESS.CODIGOPESSOA = P.CODIGOPESSOA
    inner join CAIXA as CX on P.CODIGOLANCAMENTO = CX.CODIGOLANCAMENTO
    where P.CODIGOEMPRESA = 1 and
        (P.CODIGO_PEDIDO_TIPO <> 8 or (P.CODIGO_PEDIDO_TIPO is null)) and
        (P.CODIGO_PEDIDO_TIPO <> 4 or (P.CODIGO_PEDIDO_TIPO is null)) and
        P.CODIGO_PEDIDO_SITUACAO <> 4 and
        P.CODIGOLANCAMENTO is not null and
        PESS.CODIGOTIPO = 1 and
        extract(day from CX.DATAHORALANCAMENTO) <= extract(day from current_date) and
        extract(month from CX.DATAHORALANCAMENTO) = extract(month from current_date) and
        extract(year from CX.DATAHORALANCAMENTO) = extract(year from current_date)

Total de vendas na semana:
Select Sum(P.VALORTOTAL) as "value", 'ion-calculator' As "icon"
    from PEDIDO P
    inner join PESSOA PESS on PESS.CODIGOPESSOA = P.CODIGOPESSOA
    inner join CAIXA as CX on P.CODIGOLANCAMENTO = CX.CODIGOLANCAMENTO
    where P.CODIGOEMPRESA = 1 and
        (P.CODIGO_PEDIDO_TIPO <> 8 or (P.CODIGO_PEDIDO_TIPO is null)) and
        (P.CODIGO_PEDIDO_TIPO <> 4 or (P.CODIGO_PEDIDO_TIPO is null)) and
        P.CODIGO_PEDIDO_SITUACAO <> 4 and
        P.CODIGOLANCAMENTO is not null and
        PESS.CODIGOTIPO = 1
        and CX.DataHoraLancamento >= (Select cast(current_date - extract(weekday from current_date) as timestamp) From RDB$DATABASE)
        and CX.DataHoraLancamento <= (Select dateadd(59 second to dateadd(59 minute to dateadd(23 hour to cast(current_date - extract(weekday from current_date) + 6 as timestamp)))) From RDB$DATABASE)

Análise de pico de vendas por horário:
Select 'Qtde' as "label",
    lpad (extract (hour FROM P.datacadastro),2,'0') || 'h' as "bar",
    count (*) AS "value"
    from PEDIDO P
    left join PESSOA PESS on PESS.CODIGOPESSOA = P.CODIGOPESSOA
    left join PESSOA VENDEDOR on VENDEDOR.CODIGOPESSOA = P.CODIGOFUNCIONARIO
    left join CAIXA as CX on P.CODIGOLANCAMENTO = CX.CODIGOLANCAMENTO
    where P.CODIGOEMPRESA = 1 and
        (P.CODIGO_PEDIDO_TIPO <> 8 or (P.CODIGO_PEDIDO_TIPO is null)) and
        (P.CODIGO_PEDIDO_TIPO <> 4 or (P.CODIGO_PEDIDO_TIPO is null)) and
        P.CODIGO_PEDIDO_SITUACAO <> 4 and
        P.CODIGOLANCAMENTO is not null and
        PESS.CODIGOTIPO = 1 and
        cast(CX.DATAHORALANCAMENTO as date) = cast(current_date as date)
    group by 2
    order by 2

Total de vendas hoje:
Select Sum(P.VALORTOTAL) as "value", 'ion-calculator' As "icon"
    from PEDIDO P
    left join PESSOA PESS on PESS.CODIGOPESSOA = P.CODIGOPESSOA
    left join PESSOA VENDEDOR on VENDEDOR.CODIGOPESSOA = P.CODIGOFUNCIONARIO
    left join CAIXA as CX on P.CODIGOLANCAMENTO = CX.CODIGOLANCAMENTO
    where P.CODIGOEMPRESA = 1 and
        (P.CODIGO_PEDIDO_TIPO <> 8 or (P.CODIGO_PEDIDO_TIPO is null)) and
        (P.CODIGO_PEDIDO_TIPO <> 4 or (P.CODIGO_PEDIDO_TIPO is null)) and
        P.CODIGO_PEDIDO_SITUACAO <> 4 and
        P.CODIGOLANCAMENTO is not null and
        PESS.CODIGOTIPO = 1 and
        cast(CX.DATAHORALANCAMENTO as date) = cast(current_date as date)

Ranking dos 5 clientes que mais compram:
Select First 5
Cliente.Nome As "label",
Sum(P.ValorTotal) As "value"
FROM PEDIDO P
INNER JOIN Caixa CX ON CX.codigolancamento =  P.CodigoLancamento
INNER JOIN Pessoa Cliente ON P.CodigoPessoa = Cliente.CodigoPessoa
INNER JOIN Pessoa_Funcionario Funcionario ON Funcionario.CodigoPessoa = P.CodigoFuncionario
INNER JOIN Pessoa Vendedor ON Vendedor.CodigoPessoa = Funcionario.CodigoPessoa
Where P.Codigo_Pedido_Situacao = 2 And P.codigoempresa = 1
And CX.DataHoraLancamento >= (Select cast(current_date - extract(day from current_date) + 1 As timestamp) From RDB$DATABASE)
And CX.DataHoraLancamento <= (Select dateadd(59 second to dateadd(59 minute to dateadd(23 hour to Cast(current_date - extract(day from current_date) + 32 - extract(day from current_date - extract(day from current_date) + 32) as timestamp)))) From RDB$DATABASE)
Group By Cliente.CodigoPessoa, Cliente.Nome Order By "value" Desc

Ranking dos 5 produtos mais vendidos:
SELECT First 5
case
when(PRO.nome_completo is null) then
    PB.Nome
when(PRO.nome_completo is not null) then
    PRO.nome_completo
end As "label",
Sum(PP.ValorTotal) As "value"
FROM PEDIDO P
INNER JOIN Pedido_Produto PP ON PP.CodigoPedido = P.CodigoPedido
INNER JOIN Caixa CX ON CX.codigolancamento =  P.CodigoLancamento
INNER JOIN Produto PRO ON PRO.CodigoProduto = PP.CodigoProduto
INNER JOIN Produto_Base PB ON PRO.CodigoBaseProduto = PB.CodigoBaseProduto
WHERE P.Codigo_Pedido_Situacao = 2 And P.codigoempresa = 1
And CX.DataHoraLancamento >= (Select cast(current_date - extract(day from current_date) + 1 As timestamp) From RDB$DATABASE)
And CX.DataHoraLancamento <= (Select dateadd(59 second to dateadd(59 minute to dateadd(23 hour to Cast(current_date - extract(day from current_date) + 32 - extract(day from current_date - extract(day from current_date) + 32) as timestamp)))) From RDB$DATABASE)
Group By PP.CodigoProduto, PB.nome, PRO.Nome_Completo Order By "value" Desc

Ranking dos 5 vendedores que mais venderam
Select First 5
Vendedor.Nome As "label",
Sum(P.ValorTotal) As "value"
FROM PEDIDO P
INNER JOIN Caixa CX ON CX.codigolancamento =  P.CodigoLancamento
INNER JOIN Pessoa Cliente ON P.CodigoPessoa = Cliente.CodigoPessoa
INNER JOIN Pessoa_Funcionario Funcionario ON Funcionario.CodigoPessoa = P.CodigoFuncionario
INNER JOIN Pessoa Vendedor ON Vendedor.CodigoPessoa = Funcionario.CodigoPessoa
Where P.Codigo_Pedido_Situacao = 2 And P.CodigoEmpresa = 1
And CX.DataHoraLancamento >= (Select cast(current_date - extract(day from current_date) + 1 As timestamp) From RDB$DATABASE)
And CX.DataHoraLancamento <= (Select dateadd(59 second to dateadd(59 minute to dateadd(23 hour to Cast(current_date - extract(day from current_date) + 32 - extract(day from current_date - extract(day from current_date) + 32) as timestamp)))) From RDB$DATABASE)
Group By Vendedor.CodigoPessoa, Vendedor.Nome Order By "value" Desc

Financeiro:

Contas a receber este mês:
SELECT DISTINCT Sum(cP.Total) As "value", 'ion-cash' As "icon"
FROM Conta_Parcela cP                             
INNER JOIN Conta AS c ON c.CodigoConta = cP.CodigoConta
INNER JOIN Pessoa AS p ON P.CodigoPessoa = c.CodigoPessoa
Inner Join Pessoa_Tipo As PT On P.CodigoTipo = PT.CodigoTipo
Inner Join Caixa As CX On c.CodigoLancamento = CX.CodigoLancamento
INNER JOIN Usuario AS u ON u.CodigoUsuario = CX.CodigoUsuario
INNER JOIN Empresa AS e ON u.CodigoEmpresa = e.CodigoEmpresa
INNER JOIN Caixa_Conta_Plano AS cxCP ON cxCP.CodigoPlanoConta = c.CodigoPlanoConta                             
Inner Join Caixa_Abertura As CA On CX.CodigoAbertura = CA.CodigoAbertura
LEFT JOIN (SELECT List(DISTINCT Nfe.NumeroNota, ', ') as NumeroNota, ped.CodigoLancamento
           FROM Pedido AS ped
           INNER JOIN Pedido_Nfe AS pedNfe ON ped.CodigoPedido = pedNfe.CodigoPedido
           INNER JOIN Nfe ON pedNfe.CodigoNfe = Nfe.CodigoNfe
           GROUP BY ped.codigoLancamento) AS NumNfe ON CX.CodigoLancamento = NumNfe.CodigoLancamento
LEFT JOIN (SELECT List(DISTINCT Sat.NumeroCupom, ', ') as NumeroCupom, ped.CodigoLancamento
           FROM Pedido AS ped
           INNER JOIN Sat_Pedido AS pedSat ON ped.CodigoPedido = pedSat.CodigoPedido
           INNER JOIN Sat ON pedSat.CodigoSat = Sat.CodigoSat
           GROUP BY ped.codigoLancamento) AS NumSat ON CX.CodigoLancamento = NumSat.CodigoLancamento
LEFT JOIN (SELECT List(DISTINCT nfce.numero_nota, ', ') as NumeroCupomNFCE, ped.CodigoLancamento
           FROM Pedido AS ped
           INNER JOIN nfce_pedido AS p_nfce ON ped.CodigoPedido = p_nfce.codigo_pedido
           INNER JOIN nfce ON p_nfce.codigo_nfce = nfce.codigo_nfce
           GROUP BY ped.codigoLancamento) AS NumNfce ON CX.CodigoLancamento = NumNfce.CodigoLancamento
Left join(Select cbsub.Codigo_Parcela, cbsub.Codigo_Boleto, cbsub.Titulo_Nosso_Numero, cbsub.Situacao
          From CONTA_BOLETO cbsub)
          As cb On cb.Codigo_Parcela = cp.CodigoParcela
Where cP.Total > 0
And Upper(cP.Situacao) = 'PENDENTE' AND cP.CODIGO_CONTA_CHEQUE IS NULL
AND cP.DataVencimento >= (Select cast(current_date - extract(day from current_date) + 1 As timestamp) From RDB$DATABASE)
AND cP.DataVencimento <= (Select dateadd(59 second to dateadd(59 minute to dateadd(23 hour to Cast(current_date - extract(day from current_date) + 32 - extract(day from current_date - extract(day from current_date) + 32) as timestamp)))) From RDB$DATABASE)
AND e.CodigoEmpresa = 1 And PT.CodigoTipo = 1

Contas a receber esta semana:
SELECT DISTINCT Sum(cP.Total) As "value", 'ion-cash' As "icon"
FROM Conta_Parcela cP                             
INNER JOIN Conta AS c ON c.CodigoConta = cP.CodigoConta
INNER JOIN Pessoa AS p ON P.CodigoPessoa = c.CodigoPessoa
Inner Join Pessoa_Tipo As PT On P.CodigoTipo = PT.CodigoTipo
Inner Join Caixa As CX On c.CodigoLancamento = CX.CodigoLancamento
INNER JOIN Usuario AS u ON u.CodigoUsuario = CX.CodigoUsuario
INNER JOIN Empresa AS e ON u.CodigoEmpresa = e.CodigoEmpresa
INNER JOIN Caixa_Conta_Plano AS cxCP ON cxCP.CodigoPlanoConta = c.CodigoPlanoConta                             
Inner Join Caixa_Abertura As CA On CX.CodigoAbertura = CA.CodigoAbertura
LEFT JOIN (SELECT List(DISTINCT Nfe.NumeroNota, ', ') as NumeroNota, ped.CodigoLancamento
           FROM Pedido AS ped
           INNER JOIN Pedido_Nfe AS pedNfe ON ped.CodigoPedido = pedNfe.CodigoPedido
           INNER JOIN Nfe ON pedNfe.CodigoNfe = Nfe.CodigoNfe
           GROUP BY ped.codigoLancamento) AS NumNfe ON CX.CodigoLancamento = NumNfe.CodigoLancamento
LEFT JOIN (SELECT List(DISTINCT Sat.NumeroCupom, ', ') as NumeroCupom, ped.CodigoLancamento
           FROM Pedido AS ped
           INNER JOIN Sat_Pedido AS pedSat ON ped.CodigoPedido = pedSat.CodigoPedido
           INNER JOIN Sat ON pedSat.CodigoSat = Sat.CodigoSat
           GROUP BY ped.codigoLancamento) AS NumSat ON CX.CodigoLancamento = NumSat.CodigoLancamento
LEFT JOIN (SELECT List(DISTINCT nfce.numero_nota, ', ') as NumeroCupomNFCE, ped.CodigoLancamento
           FROM Pedido AS ped
           INNER JOIN nfce_pedido AS p_nfce ON ped.CodigoPedido = p_nfce.codigo_pedido
           INNER JOIN nfce ON p_nfce.codigo_nfce = nfce.codigo_nfce
           GROUP BY ped.codigoLancamento) AS NumNfce ON CX.CodigoLancamento = NumNfce.CodigoLancamento
Left join(Select cbsub.Codigo_Parcela, cbsub.Codigo_Boleto, cbsub.Titulo_Nosso_Numero, cbsub.Situacao
          From CONTA_BOLETO cbsub)
          As cb On cb.Codigo_Parcela = cp.CodigoParcela
Where cP.Total > 0
And Upper(cP.Situacao) = 'PENDENTE' AND cP.CODIGO_CONTA_CHEQUE IS NULL
AND cP.DataVencimento >= (Select cast(current_date - extract(weekday from current_date) As timestamp) From RDB$DATABASE)
AND cP.DataVencimento <= (Select dateadd(59 second to dateadd(59 minute to dateadd(23 hour to Cast(current_date - extract(weekday from current_date) + 6 As timestamp)))) From RDB$DATABASE)
AND e.CodigoEmpresa = 1 And PT.CodigoTipo = 1

Contas a receber hoje:
SELECT DISTINCT Sum(cP.Total) As "value", 'ion-cash' As "icon"
FROM Conta_Parcela cP                             
INNER JOIN Conta AS c ON c.CodigoConta = cP.CodigoConta
INNER JOIN Pessoa AS p ON P.CodigoPessoa = c.CodigoPessoa
Inner Join Pessoa_Tipo As PT On P.CodigoTipo = PT.CodigoTipo
Inner Join Caixa As CX On c.CodigoLancamento = CX.CodigoLancamento
INNER JOIN Usuario AS u ON u.CodigoUsuario = CX.CodigoUsuario
INNER JOIN Empresa AS e ON u.CodigoEmpresa = e.CodigoEmpresa
INNER JOIN Caixa_Conta_Plano AS cxCP ON cxCP.CodigoPlanoConta = c.CodigoPlanoConta                             
Inner Join Caixa_Abertura As CA On CX.CodigoAbertura = CA.CodigoAbertura
LEFT JOIN (SELECT List(DISTINCT Nfe.NumeroNota, ', ') as NumeroNota, ped.CodigoLancamento
           FROM Pedido AS ped
           INNER JOIN Pedido_Nfe AS pedNfe ON ped.CodigoPedido = pedNfe.CodigoPedido
           INNER JOIN Nfe ON pedNfe.CodigoNfe = Nfe.CodigoNfe
           GROUP BY ped.codigoLancamento) AS NumNfe ON CX.CodigoLancamento = NumNfe.CodigoLancamento
LEFT JOIN (SELECT List(DISTINCT Sat.NumeroCupom, ', ') as NumeroCupom, ped.CodigoLancamento
           FROM Pedido AS ped
           INNER JOIN Sat_Pedido AS pedSat ON ped.CodigoPedido = pedSat.CodigoPedido
           INNER JOIN Sat ON pedSat.CodigoSat = Sat.CodigoSat
           GROUP BY ped.codigoLancamento) AS NumSat ON CX.CodigoLancamento = NumSat.CodigoLancamento
LEFT JOIN (SELECT List(DISTINCT nfce.numero_nota, ', ') as NumeroCupomNFCE, ped.CodigoLancamento
           FROM Pedido AS ped
           INNER JOIN nfce_pedido AS p_nfce ON ped.CodigoPedido = p_nfce.codigo_pedido
           INNER JOIN nfce ON p_nfce.codigo_nfce = nfce.codigo_nfce
           GROUP BY ped.codigoLancamento) AS NumNfce ON CX.CodigoLancamento = NumNfce.CodigoLancamento
Left join(Select cbsub.Codigo_Parcela, cbsub.Codigo_Boleto, cbsub.Titulo_Nosso_Numero, cbsub.Situacao
          From CONTA_BOLETO cbsub)
          As cb On cb.Codigo_Parcela = cp.CodigoParcela
Where cP.Total > 0
And Upper(cP.Situacao) = 'PENDENTE' AND cP.CODIGO_CONTA_CHEQUE IS NULL
AND cP.DataVencimento >= (Select cast(current_date as timestamp) From RDB$DATABASE)
AND cP.DataVencimento <= (Select dateadd(59 second to dateadd(59 minute to dateadd(23 hour to cast(current_date as timestamp)))) From RDB$DATABASE)
AND e.CodigoEmpresa = 1 And PT.CodigoTipo = 1

Contas a pagar este mês:
SELECT DISTINCT Sum(cP.Total) As "value", 'ion-cash' As "icon"
FROM Conta_Parcela cP                             
INNER JOIN Conta AS c ON c.CodigoConta = cP.CodigoConta
INNER JOIN Pessoa AS p ON P.CodigoPessoa = c.CodigoPessoa
Inner Join Pessoa_Tipo As PT On P.CodigoTipo = PT.CodigoTipo
Inner Join Caixa As CX On c.CodigoLancamento = CX.CodigoLancamento
INNER JOIN Usuario AS u ON u.CodigoUsuario = CX.CodigoUsuario
INNER JOIN Empresa AS e ON u.CodigoEmpresa = e.CodigoEmpresa
INNER JOIN Caixa_Conta_Plano AS cxCP ON cxCP.CodigoPlanoConta = c.CodigoPlanoConta                             
Inner Join Caixa_Abertura As CA On CX.CodigoAbertura = CA.CodigoAbertura
LEFT JOIN (SELECT List(DISTINCT Nfe.NumeroNota, ', ') as NumeroNota, ped.CodigoLancamento
           FROM Pedido AS ped
           INNER JOIN Pedido_Nfe AS pedNfe ON ped.CodigoPedido = pedNfe.CodigoPedido
           INNER JOIN Nfe ON pedNfe.CodigoNfe = Nfe.CodigoNfe
           GROUP BY ped.codigoLancamento) AS NumNfe ON CX.CodigoLancamento = NumNfe.CodigoLancamento
LEFT JOIN (SELECT List(DISTINCT Sat.NumeroCupom, ', ') as NumeroCupom, ped.CodigoLancamento
           FROM Pedido AS ped
           INNER JOIN Sat_Pedido AS pedSat ON ped.CodigoPedido = pedSat.CodigoPedido
           INNER JOIN Sat ON pedSat.CodigoSat = Sat.CodigoSat
           GROUP BY ped.codigoLancamento) AS NumSat ON CX.CodigoLancamento = NumSat.CodigoLancamento
LEFT JOIN (SELECT List(DISTINCT nfce.numero_nota, ', ') as NumeroCupomNFCE, ped.CodigoLancamento
           FROM Pedido AS ped
           INNER JOIN nfce_pedido AS p_nfce ON ped.CodigoPedido = p_nfce.codigo_pedido
           INNER JOIN nfce ON p_nfce.codigo_nfce = nfce.codigo_nfce
           GROUP BY ped.codigoLancamento) AS NumNfce ON CX.CodigoLancamento = NumNfce.CodigoLancamento
Left join(Select cbsub.Codigo_Parcela, cbsub.Codigo_Boleto, cbsub.Titulo_Nosso_Numero, cbsub.Situacao
          From CONTA_BOLETO cbsub)
          As cb On cb.Codigo_Parcela = cp.CodigoParcela
Where cP.Total > 0
And Upper(cP.Situacao) = 'PENDENTE' AND cP.CODIGO_CONTA_CHEQUE IS NULL
AND cP.DataVencimento >= (Select cast(current_date - extract(day from current_date) + 1 As timestamp) From RDB$DATABASE)
AND cP.DataVencimento <= (Select dateadd(59 second to dateadd(59 minute to dateadd(23 hour to Cast(current_date - extract(day from current_date) + 32 - extract(day from current_date - extract(day from current_date) + 32) as timestamp)))) From RDB$DATABASE)
AND e.CodigoEmpresa = 1 And (PT.CodigoTipo = 3 Or PT.CodigoTipo = 4)

Contas a pagar esta semana:
SELECT DISTINCT Sum(cP.Total) As "value", 'ion-cash' As "icon"
FROM Conta_Parcela cP                             
INNER JOIN Conta AS c ON c.CodigoConta = cP.CodigoConta
INNER JOIN Pessoa AS p ON P.CodigoPessoa = c.CodigoPessoa
Inner Join Pessoa_Tipo As PT On P.CodigoTipo = PT.CodigoTipo
Inner Join Caixa As CX On c.CodigoLancamento = CX.CodigoLancamento
INNER JOIN Usuario AS u ON u.CodigoUsuario = CX.CodigoUsuario
INNER JOIN Empresa AS e ON u.CodigoEmpresa = e.CodigoEmpresa
INNER JOIN Caixa_Conta_Plano AS cxCP ON cxCP.CodigoPlanoConta = c.CodigoPlanoConta                             
Inner Join Caixa_Abertura As CA On CX.CodigoAbertura = CA.CodigoAbertura
LEFT JOIN (SELECT List(DISTINCT Nfe.NumeroNota, ', ') as NumeroNota, ped.CodigoLancamento
           FROM Pedido AS ped
           INNER JOIN Pedido_Nfe AS pedNfe ON ped.CodigoPedido = pedNfe.CodigoPedido
           INNER JOIN Nfe ON pedNfe.CodigoNfe = Nfe.CodigoNfe
           GROUP BY ped.codigoLancamento) AS NumNfe ON CX.CodigoLancamento = NumNfe.CodigoLancamento
LEFT JOIN (SELECT List(DISTINCT Sat.NumeroCupom, ', ') as NumeroCupom, ped.CodigoLancamento
           FROM Pedido AS ped
           INNER JOIN Sat_Pedido AS pedSat ON ped.CodigoPedido = pedSat.CodigoPedido
           INNER JOIN Sat ON pedSat.CodigoSat = Sat.CodigoSat
           GROUP BY ped.codigoLancamento) AS NumSat ON CX.CodigoLancamento = NumSat.CodigoLancamento
LEFT JOIN (SELECT List(DISTINCT nfce.numero_nota, ', ') as NumeroCupomNFCE, ped.CodigoLancamento
           FROM Pedido AS ped
           INNER JOIN nfce_pedido AS p_nfce ON ped.CodigoPedido = p_nfce.codigo_pedido
           INNER JOIN nfce ON p_nfce.codigo_nfce = nfce.codigo_nfce
           GROUP BY ped.codigoLancamento) AS NumNfce ON CX.CodigoLancamento = NumNfce.CodigoLancamento
Left join(Select cbsub.Codigo_Parcela, cbsub.Codigo_Boleto, cbsub.Titulo_Nosso_Numero, cbsub.Situacao
          From CONTA_BOLETO cbsub)
          As cb On cb.Codigo_Parcela = cp.CodigoParcela
Where cP.Total > 0
And Upper(cP.Situacao) = 'PENDENTE' AND cP.CODIGO_CONTA_CHEQUE IS NULL
AND cP.DataVencimento >= (Select cast(current_date - extract(weekday from current_date) As timestamp) From RDB$DATABASE)
AND cP.DataVencimento <= (Select dateadd(59 second to dateadd(59 minute to dateadd(23 hour to Cast(current_date - extract(weekday from current_date) + 6 As timestamp)))) From RDB$DATABASE)
AND e.CodigoEmpresa = 1 And (PT.CodigoTipo = 3 Or PT.CodigoTipo = 4)

Contas a pagar hoje
SELECT DISTINCT Sum(cP.Total) As "value", 'ion-cash' As "icon"
FROM Conta_Parcela cP                             
INNER JOIN Conta AS c ON c.CodigoConta = cP.CodigoConta
INNER JOIN Pessoa AS p ON P.CodigoPessoa = c.CodigoPessoa
Inner Join Pessoa_Tipo As PT On P.CodigoTipo = PT.CodigoTipo
Inner Join Caixa As CX On c.CodigoLancamento = CX.CodigoLancamento
INNER JOIN Usuario AS u ON u.CodigoUsuario = CX.CodigoUsuario
INNER JOIN Empresa AS e ON u.CodigoEmpresa = e.CodigoEmpresa
INNER JOIN Caixa_Conta_Plano AS cxCP ON cxCP.CodigoPlanoConta = c.CodigoPlanoConta                             
Inner Join Caixa_Abertura As CA On CX.CodigoAbertura = CA.CodigoAbertura
LEFT JOIN (SELECT List(DISTINCT Nfe.NumeroNota, ', ') as NumeroNota, ped.CodigoLancamento
           FROM Pedido AS ped
           INNER JOIN Pedido_Nfe AS pedNfe ON ped.CodigoPedido = pedNfe.CodigoPedido
           INNER JOIN Nfe ON pedNfe.CodigoNfe = Nfe.CodigoNfe
           GROUP BY ped.codigoLancamento) AS NumNfe ON CX.CodigoLancamento = NumNfe.CodigoLancamento
LEFT JOIN (SELECT List(DISTINCT Sat.NumeroCupom, ', ') as NumeroCupom, ped.CodigoLancamento
           FROM Pedido AS ped
           INNER JOIN Sat_Pedido AS pedSat ON ped.CodigoPedido = pedSat.CodigoPedido
           INNER JOIN Sat ON pedSat.CodigoSat = Sat.CodigoSat
           GROUP BY ped.codigoLancamento) AS NumSat ON CX.CodigoLancamento = NumSat.CodigoLancamento
LEFT JOIN (SELECT List(DISTINCT nfce.numero_nota, ', ') as NumeroCupomNFCE, ped.CodigoLancamento
           FROM Pedido AS ped
           INNER JOIN nfce_pedido AS p_nfce ON ped.CodigoPedido = p_nfce.codigo_pedido
           INNER JOIN nfce ON p_nfce.codigo_nfce = nfce.codigo_nfce
           GROUP BY ped.codigoLancamento) AS NumNfce ON CX.CodigoLancamento = NumNfce.CodigoLancamento
Left join(Select cbsub.Codigo_Parcela, cbsub.Codigo_Boleto, cbsub.Titulo_Nosso_Numero, cbsub.Situacao
          From CONTA_BOLETO cbsub)
          As cb On cb.Codigo_Parcela = cp.CodigoParcela
Where cP.Total > 0
And Upper(cP.Situacao) = 'PENDENTE' AND cP.CODIGO_CONTA_CHEQUE IS NULL
AND cP.DataVencimento >= (Select cast(current_date as timestamp) From RDB$DATABASE)
AND cP.DataVencimento <= (Select dateadd(59 second to dateadd(59 minute to dateadd(23 hour to cast(current_date as timestamp)))) From RDB$DATABASE)
AND e.CodigoEmpresa = 1 And (PT.CodigoTipo = 3 Or PT.CodigoTipo = 4)


Estoque:

Os 10 produtos com mais estoque:
Select First 5 PB.Nome As "label", Cast(PE.Estoque As Numeric(12, 2)) As "value" From Produto As P
Inner Join Produto_Base As PB
Inner Join Produto_Estoque As PE
On P.CodigoBaseProduto = PB.CodigoBaseProduto
On P.CodigoProduto = PE.CodigoProduto
Where PE.CodigoEmpresa = 1 And P.Desativado = 'N'
Order By PE.Estoque Desc

Produtos com estoque abaixo do mínimo:
Select * From
(Select First 5 PB.Nome As "bar", 'Estoque atual' As "label", PE.Estoque As "value", PE.Estoque
From Produto_Base As PB
Inner Join Produto As P On PB.CodigoBaseProduto = P.CodigoBaseProduto
Inner Join Produto_Estoque PE On P.CodigoProduto = PE.CodigoProduto
Where PE.CodigoEmpresa = 1 And PE.Estoque < PB.EstoqueMinimo
And P.Desativado = 'N' Order By PE.Estoque Asc)
UNIOn all
Select * From
(Select First 5 PB.Nome As "bar", 'Estoque mínimo' As "label", PB.EstoqueMinimo As "value", PE.Estoque
From Produto_Base As PB
Inner Join Produto As P On PB.CodigoBaseProduto = P.CodigoBaseProduto
Inner Join Produto_Estoque PE On P.CodigoProduto = PE.CodigoProduto
Where PE.CodigoEmpresa = 1 And PE.Estoque < PB.EstoqueMinimo
And P.Desativado = 'N' Order By PE.Estoque Asc)

Saldo diário:
Saldo dos caixas:
select
    CXC.NOME AS "nome",
    'Caixa (Dinheiro)' AS "descricao",
    'Saldo disponível' AS "info",
    sum(
       case
         when CC.OPERACAO_PLANO_CONTA = 'C' then CP.TOTAL
         else 0
       end) - sum(
       case
         when CC.OPERACAO_PLANO_CONTA = 'D' then CP.TOTAL
         else 0
       end) as "valor",
       'ion-cash' As "icon"
from CAIXA CX
inner join CAIXA_ABERTURA as CA on CX.CODIGOABERTURA = CA.CODIGOABERTURA
inner join CAIXA_CONFIG as CXC on CA.CODIGOCAIXA = CXC.CODIGOCAIXA
inner join CONTA_BAIXA CB on CX.CODIGOLANCAMENTO = CB.CODIGOLANCAMENTO
inner join CONTA_BAIXA_CONTA_PARCELA CBCP on CB.CODIGOBAIXA = CBCP.CODIGOBAIXA
inner join CONTA_PARCELA CP on CBCP.CODIGOPARCELA = CP.CODIGOPARCELA
inner join CAIXA_CONTA_PLANO CC on CP.CODIGO_PLANO_CONTA = CC.CODIGOPLANOCONTA
inner join CONTA C on CP.CODIGOCONTA = C.CODIGOCONTA
inner join PESSOA P on C.CODIGOPESSOA = P.CODIGOPESSOA
left join FORMA_PAGAMENTO_CONDICAO FPC on CP.CODIGO_FORMA_PAGAMENTO_CONDICAO = FPC.CODIGO_FORMA_PAGAMENTO_CONDICAO
left join CONDICAO_PAGAMENTO as CPA on FPC.CODIGO_CONDICAO_PAGAMENTO = CPA.CODIGO_CONDICAO_PAGAMENTO
left join FORMA_PAGAMENTO as FP on FPC.CODIGO_FORMA_PAGAMENTO = FP.CODIGO_FORMA_PAGAMENTO
left join CAIXA_FECHAMENTO as CF on CA.CODIGOABERTURA = CF.CODIGOABERTURA
left join PEDIDO as PED on CX.CODIGOLANCAMENTO = PED.CODIGOLANCAMENTO
where upper(CP.SITUACAO) = 'LIQUIDADA' and
      (FP.CODIGO_MEIO_PAGAMENTO_FISCAL <> 15 and
      FP.CODIGO_MEIO_PAGAMENTO_FISCAL <> 18 or FP.CODIGO_MEIO_PAGAMENTO_FISCAL is null) and
      (FP.DESCRICAO is null or FP.CHEQUE_PROPRIO = 'N') and
      (CPA.MOVIMENTA_CAIXA = 'S' or CPA.MOVIMENTA_CAIXA is null) and
      (CC.PLANOCONTA <> 'Saque bancário' or CC.OPERACAO_PLANO_CONTA = 'C') and
      (CC.PLANOCONTA <> 'Depósito bancário' or CC.OPERACAO_PLANO_CONTA = 'D') and
      CF.CODIGOABERTURA is null and cc.planoconta <> 'Haver'
group by CXC.NOME

Saldo bancário:
SELECT teste.nomebanco as "nome",'Conta Bancária' as "descricao", 'Saldo disponível' as "info", sum(TESTE."valor") as "valor" FROM (select BANCO.CODIGOCONTABANCO, BANCO.NOMEBANCO, 'Conta Bancária' as "descricao", 'Saldo disponível' as "info", sum(
       case
         when BANCO.OPERACAO = 'C' then BANCO.VALOR
         else 0
       end) - sum(
       case
         when OPERACAO = 'D' then VALOR
         else 0
       end) as "valor"
from (select distinct CB.CODIGOBAIXA, P.NOME, P.CODIGOPESSOA, PT.CODIGOTIPO, CCP.OPERACAO_PLANO_CONTA as OPERACAO,
                      CNTB.NOME as NOMEBANCO, CBCB.VALOR, CNTB.CODIGOCONTABANCO
      from CONTA_BAIXA as CB
      inner join CONTA_BAIXA_CONTA_PARCELA as CBCP on CB.CODIGOBAIXA = CBCP.CODIGOBAIXA
      inner join CONTA_PARCELA as CPAR on CPAR.CODIGOPARCELA = CBCP.CODIGOPARCELA
      inner join CONTA as C on C.CODIGOCONTA = CPAR.CODIGOCONTA
      inner join PESSOA as P on P.CODIGOPESSOA = C.CODIGOPESSOA
      inner join PESSOA_TIPO as PT on P.CODIGOTIPO = PT.CODIGOTIPO
      inner join CAIXA_CONTA_PLANO as CCP on C.CODIGOPLANOCONTA = CCP.CODIGOPLANOCONTA
      inner join CAIXA as CX on C.CODIGOLANCAMENTO = CX.CODIGOLANCAMENTO
      inner join CAIXA_ABERTURA as CA on CX.CODIGOABERTURA = CA.CODIGOABERTURA
      inner join CAIXA_CONFIG as CXC on CA.CODIGOCAIXA = CXC.CODIGOCAIXA
      inner join CONTA_BAIXA_CONTA_BANCO as CBCB on CB.CODIGOBAIXA = CBCB.CODIGOBAIXA
      inner join CONTA_BANCO CNTB on CBCB.CODIGOCONTABANCO = CNTB.CODIGOCONTABANCO
      where CXC.CODIGOEMPRESA = 1 and
            CBCB.DATACOMPENSACAO is not null and
            CNTB.DESATIVADO = 'N') as BANCO
group by BANCO.NOMEBANCO, BANCO.CODIGOCONTABANCO

union all

select BANCOCARTAO.CODIGOCONTABANCOSUB, BANCOCARTAO.NOMEBANCO, 'Conta Bancária' as "descricao",
       'Saldo disponível' as "info", sum(
       case
         when BANCOCARTAO.OPERACAO = 'C' then BANCOCARTAO.VALOR
         else 0
       end) - sum(
       case
         when OPERACAO = 'D' then VALOR
         else 0
       end) as "valor"
from (select distinct CB.CODIGOBAIXA, P.NOME, P.CODIGOPESSOA, PT.CODIGOTIPO, CCP.OPERACAO_PLANO_CONTA as OPERACAO,
                      CCA.TITULAR, CCA.NSU, CCAP.*, CCAP.CODIGOCONTABANCO as CODIGOCONTABANCOSUB,
                      CNTB.NOME as NOMEBANCO
      from CONTA_BAIXA as CB
      inner join CONTA_BAIXA_CONTA_PARCELA as CBCP on CB.CODIGOBAIXA = CBCP.CODIGOBAIXA
      inner join CONTA_PARCELA as CPAR on CPAR.CODIGOPARCELA = CBCP.CODIGOPARCELA
      inner join CONTA as C on C.CODIGOCONTA = CPAR.CODIGOCONTA
      inner join PESSOA as P on P.CODIGOPESSOA = C.CODIGOPESSOA
      inner join PESSOA_TIPO as PT on P.CODIGOTIPO = PT.CODIGOTIPO
      inner join CAIXA_CONTA_PLANO as CCP on CPAR.CODIGO_PLANO_CONTA = CCP.CODIGOPLANOCONTA
      inner join CAIXA as CX on C.CODIGOLANCAMENTO = CX.CODIGOLANCAMENTO
      inner join CAIXA_ABERTURA as CA on CX.CODIGOABERTURA = CA.CODIGOABERTURA
      inner join CAIXA_CONFIG as CXC on CA.CODIGOCAIXA = CXC.CODIGOCAIXA
      inner join CONTA_BAIXA_CONTA_CARTAO as CBCCA on CB.CODIGOBAIXA = CBCCA.CODIGOBAIXA
      inner join CONTA_CARTAO as CCA on CBCCA.CODIGOCARTAO = CCA.CODIGOCARTAO
      inner join CONTA_CARTAO_PARCELA CCAP on CCA.CODIGOCARTAO = CCAP.CODIGOCARTAO
      inner join CONTA_BANCO CNTB on CCAP.CODIGOCONTABANCO = CNTB.CODIGOCONTABANCO
      where CCAP.DATACOMPENSACAO is not null and
            CNTB.DESATIVADO = 'N') as BANCOCARTAO
group by BANCOCARTAO.NOMEBANCO, BANCOCARTAO.CODIGOCONTABANCOSUB

union all
select BANCOCHEQUE.CODIGOCONTABANCOSUB, BANCOCHEQUE.NOMEBANCO, 'Conta Bancária' as "descricao",
       'Saldo disponível' as "info", sum(
       case
         when BANCOCHEQUE.OPERACAO = 'C' then BANCOCHEQUE.VALOR
         else 0
       end) - sum(
       case
         when OPERACAO = 'D' then VALOR
         else 0
       end) as "valor"
from (select distinct CB.CODIGOBAIXA, P.NOME, P.CODIGOPESSOA, PT.CODIGOTIPO, CCP.OPERACAO_PLANO_CONTA as OPERACAO,
                      CCH.*, CCH.CODIGOCONTABANCODEPOSITO as CODIGOCONTABANCOSUB, CNTB.NOME as NOMEBANCO
      from CONTA_BAIXA as CB
      inner join CONTA_BAIXA_CONTA_PARCELA as CBCP on CB.CODIGOBAIXA = CBCP.CODIGOBAIXA
      inner join CONTA_PARCELA as CPAR on CPAR.CODIGOPARCELA = CBCP.CODIGOPARCELA
      inner join CONTA as C on C.CODIGOCONTA = CPAR.CODIGOCONTA
      inner join PESSOA as P on P.CODIGOPESSOA = C.CODIGOPESSOA
      inner join PESSOA_TIPO as PT on P.CODIGOTIPO = PT.CODIGOTIPO
      inner join CAIXA_CONTA_PLANO as CCP on C.CODIGOPLANOCONTA = CCP.CODIGOPLANOCONTA
      inner join CAIXA as CX on C.CODIGOLANCAMENTO = CX.CODIGOLANCAMENTO
      inner join CAIXA_ABERTURA as CA on CX.CODIGOABERTURA = CA.CODIGOABERTURA
      inner join CAIXA_CONFIG as CXC on CA.CODIGOCAIXA = CXC.CODIGOCAIXA
      left join CONTA_BAIXA_CONTA_CHEQUE as CBCCH on CB.CODIGOBAIXA = CBCCH.CODIGOBAIXA
      left join CONTA_CHEQUE CCH on CBCCH.CODIGOCHEQUE = CCH.CODIGOCHEQUE
      inner join CONTA_BANCO CNTB on CCH.CODIGOCONTABANCODEPOSITO = CNTB.CODIGOCONTABANCO
      where PT.CODIGOTIPO <> 2 and
            CCH.DATACOMPENSACAO is not null and
            CNTB.DESATIVADO = 'N') as BANCOCHEQUE
group by BANCOCHEQUE.NOMEBANCO, BANCOCHEQUE.CODIGOCONTABANCOSUB) AS TESTE
GROUP BY teste.nomebanco, TESTE.CODIGOCONTABANCO

# Modelo dimensional (secção do relatório)

## Metodologia

O data mart foi desenhado segundo a metodologia de Kimball, que organiza a modelação em quatro passos: escolher o processo de negócio, definir a granularidade, identificar as dimensões e identificar os factos. A gestão da More Rhythm quer analisar historicamente as vendas a clientes, pelo que o processo de negócio é a faturação. O resultado é um esquema em estrela, com uma tabela de factos e seis dimensões, que respeita as exigências do enunciado: consultas ao nível de detalhe mais elementar, histórico das alterações e o euro como moeda de uniformização.

## Requisitos analíticos

As dez análises do enunciado foram decompostas em medidas, filtros, atributos de agrupamento e operações de *drill down* e *roll up* (matriz no Anexo A). Destas resultaram os requisitos do modelo:

- calendário completo (semestre, trimestre, quadrimestre, mês, semana ISO, estação do ano) e indicadores de fim de semana e último dia do mês;
- duas hierarquias de produto (família e categoria) e geografia do cliente e do fornecedor;
- tipo de cliente como nível de *roll up* distinto da geografia;
- vendas com e sem IVA e custos de expedição ao nível de família e de produto.

As análises são **indicativas**, por isso o modelo inclui também outros atributos (segmento, grupo e chefia do funcionário, nacionalidade do fornecedor, prazo de pagamento) que permitem muitas outras consultas.

## Granularidade

A tabela de factos tem a granularidade de uma linha de fatura, isto é, um produto numa fatura. É o nível mais baixo de detalhe disponível na origem (`invoices_lines`) e o único onde coexistem produto, quantidade e valor. A escolha tem uma consequência simples: qualquer agregação superior (por fatura, cliente, mês ou família) obtém-se somando linhas, mas o detalhe de uma linha não se recupera a partir de totais. Uma tabela de factos ao nível da fatura perderia o produto e tornaria impossíveis as análises por família, categoria e produto, que o enunciado pede em vários dos seus exemplos. Não se guarda a hora da transação: nenhuma análise pedida a usa e uma dimensão de hora só se justificaria para agregar por períodos do dia.

## Dimensões e factos

O esquema é uma estrela sem *snowflaking*: os níveis das hierarquias ficam desnormalizados dentro de cada dimensão, o que simplifica as consultas e evita junções desnecessárias. O diagrama seguinte apresenta o modelo.

| Tabela | Conteúdo principal | Porquê |
|---|---|---|
| `Fact_Vendas` | Quantidade, valor líquido, IVA e frete alocado (em moeda original e em euros), taxa de câmbio, número da fatura (dimensão degenerada) | Uma linha por linha de fatura, o nível mais fino; só guarda as medidas, e as chaves das dimensões dão-lhes contexto |
| `Dim_Data` | Data da fatura e data de pagamento (dois papéis), com semestre, trimestre, quadrimestre, mês, semana ISO, estação do ano, fim de semana, último dia do mês e feriados | Responde a «quando». Os dois papéis permitem o prazo de pagamento. Constrói-se antecipadamente (2020 a 2035) e a chave `yyyymmdd` é ordenada, como se vê nas aulas |
| `Dim_Cliente` | Dados do cliente, cidade, zona, país, tipo, segmento e vendedor atribuído | Responde a «quem comprou». A geografia, o tipo e o segmento são os critérios das análises 1, 2, 4 e 6 a 10 |
| `Dim_Produto` | Produto, família, categoria, classificação e taxa de IVA | Responde a «o que se vendeu». A família e a categoria são as duas hierarquias pedidas nas análises 1, 2 e 5 a 10 |
| `Dim_Fornecedor` | Fornecedor, tipo, cidade, zona e nacionalidade | Responde a «de quem vem». É pedida nas análises 3 e 10, e associa-se à linha pelo produto |
| `Dim_Funcionario` | Funcionário, grupo, departamento e chefe | Responde a «quem vendeu». É pedida nas análises 3 e 4 |
| `Dim_Moeda` | Moeda original da fatura | Solução das aulas para várias moedas: medidas na moeda original e em euros, com uma dimensão de moeda |
| `Dim_Taxa_Cambio` | Taxa de conversão para euros por moeda e dia (tabela de conversão; chave primária composta) | É a tabela de conversão de moeda das aulas; permite uniformizar em euros, como o enunciado exige |

As medidas aditivas são a quantidade, o valor líquido, o IVA e o frete alocado. O preço unitário não é aditivo e só se agrega por média. As medidas que a gestão consulta são derivadas e calculadas, não guardadas, para evitar redundância: as vendas com IVA são o valor líquido mais o IVA (sem frete, porque na origem o IVA incide apenas sobre os produtos), e o total faturado acrescenta ainda o frete. Todas as dimensões usam chaves substitutas e guardam a chave de negócio da origem para o mapeamento. A chave primária de `Fact_Vendas` é uma chave substituta da própria linha (`SK_Venda`) e não o conjunto das chaves das dimensões, porque a origem não impede que o mesmo produto apareça em mais de uma linha da mesma fatura; a unicidade da linha de negócio garante-se por `BK_Linha_Fatura`, que é única. O fornecedor associa-se à linha através do produto vendido, porque a fatura não tem fornecedor; os 12 produtos sem fornecedor na origem ligam ao membro "Sem fornecedor", para que a venda não desapareça.

## Custo de expedição

O custo de expedição só existe no cabeçalho da fatura, não em cada linha, o que impede de o somar por produto ou família. Para o tornar aditivo à granularidade escolhida, é repartido por cada linha proporcionalmente ao seu valor líquido, e o resto do arredondamento fica na última linha, de modo que a soma do frete alocado das linhas é igual ao frete da fatura. Esta igualdade é verificada em cada carga. Rejeitámos quatro alternativas: repetir o frete em todas as linhas (duplicaria o valor ao somar), manter uma tabela de factos só ao nível da fatura (não permitiria analisar o frete por família), repartir por quantidade (penalizaria os artigos baratos) e repartir por igual entre as linhas (um artigo barato ficaria com o mesmo frete de um caro). A repartição proporcional ao valor é a que melhor reflete a origem: em 35 das 37 faturas o frete incluído no total é exatamente 2,5 % do total de produtos, pelo que cada linha fica com 2,5 % do seu valor.

## Hierarquias

As hierarquias de produto e de cliente são paralelas, não aninhadas, porque família e categoria são atributos independentes do produto, tal como a geografia, o tipo e o segmento são do cliente.

| Dimensão | Hierarquias |
|---|---|
| Data | Ano > Semestre > Trimestre > Mês > Dia; Ano > Quadrimestre > Mês; Ano > Semana > Dia; Ano > Estação > Dia |
| Produto | Classificação > Família > Produto; Categoria > Produto |
| Cliente | País > Zona > Cidade > Cliente; Tipo > Cliente; Segmento > Cliente |
| Fornecedor | Zona > Cidade > Fornecedor |
| Funcionário | Departamento > Grupo > Funcionário; Chefe > Funcionário |

Estas hierarquias suportam as operações pedidas: o *drill down* até ao produto ou ao cliente e o *roll up* até ao tipo de cliente, à zona ou ao trimestre.

## Slowly Changing Dimensions

A origem regista a data de criação e de cada alteração, mas não conserva os valores antigos; o histórico do data mart começa, por isso, na primeira carga. As alterações são detetadas comparando um valor de resumo dos atributos de cada tipo (SHA-256, em vez de um CRC) com o da versão corrente da dimensão. A estratégia depende do papel do atributo:

- **Tipo 1 (substituição)** para os atributos que apenas se corrigem ou que não explicam resultados passados, como o nome, o NIF, os contactos, a morada, os prazos de pagamento e a designação do produto.
- **Tipo 2 (nova versão)** para os atributos que classificam as vendas e cuja alteração mudaria relatórios passados: zona, cidade, tipo e segmento do cliente; família, categoria, classificação e taxa de IVA do produto; tipo, cidade e zona do fornecedor; grupo, departamento e chefe do funcionário.

O exemplo que justifica a escolha é a zona do cliente: se um cliente passar do Centro para o Norte, as vendas anteriores devem continuar atribuídas ao Centro, onde foram feitas; com tipo 1, as análises históricas por zona mudariam retroativamente. Cada versão tem data de início, data de fim e um indicador de versão corrente. A primeira versão começa em 1900-01-01 e, quando se abre uma nova, a anterior fecha no dia anterior, sem sobreposição; um índice único garante uma só versão corrente por chave de negócio. Cada linha do facto aponta para a versão corrente da dimensão no momento da carga, que é a vigente na data da fatura porque as faturas são carregadas quando existem; uma alteração retroativa não reaponta factos já carregados. A data e as taxas de câmbio são imutáveis e não têm SCD. Nos casos do vendedor do cliente e do chefe do funcionário, a deteção da alteração usa o número e não o nome, de modo que uma mudança de nome da mesma pessoa se limita a atualizar todas as versões.

## Clientes duplicados

O enunciado exige eliminar os registos duplicados, quer sejam iguais ou apenas aproximadamente iguais, e o profiling confirmou o problema: há três pares de clientes (10 e 18, 8 e 22, 5 e 26), que afetam 9 das 37 faturas e cerca de 26 % do valor faturado. Se ficassem separados, as análises por cliente ficariam distorcidas, porque as vendas de um mesmo cliente apareceriam divididas por dois registos.

Por isso os duplicados são consolidados num único cliente, o sobrevivente, que é o registo atualizado mais recentemente. A dimensão tem uma linha por cliente real, e cada atributo toma o valor do sobrevivente quando este é válido, ou o do registo absorvido quando o do sobrevivente é ausente ou inválido (por exemplo, o email correto do cliente 26 no par 5 e 26). A correspondência entre cada cliente de origem e o seu sobrevivente é guardada na Staging e é persistente: depois de decidida, só se desfaz por revisão explícita. Um protótipo da carga (incluído no repositório, em `prototipo-carga`) mostrou porquê: se o mapa fosse recalculado em cada carga, uma simples alteração a um atributo de um dos clientes podia dissolver o par e partir o histórico, deixando as faturas novas numa versão diferente das antigas. A tabela de factos guarda ainda o cliente de origem de cada fatura, o que permite reapontar faturas já carregadas se um duplicado só for detetado numa carga posterior. O risco assumido é que, nos pares 5 e 26 e 8 e 22, os NIF diferem em duas posições e os dados não permitem saber qual dos dois está correto; prevalece o do sobrevivente e a divergência fica registada.

## Valores em falta e registos rejeitados

O modelo segue uma regra comum com as da Staging. Um atributo descritivo opcional em falta, como o fornecedor de um produto, é carregado com um membro "Desconhecido", para que a venda continue visível; os clientes e fornecedores sem zona e os produtos sem designação, família ou categoria, que são atributos de que as análises dependem, não são carregados; uma fatura que aponta para um deles também fica de fora (R08), o que na amostra não afeta nenhuma venda. Um problema que afete a identificação do registo, as medidas ou uma relação leva à rejeição, e o registo fica em tabelas próprias da Staging, fora do data mart, como o enunciado exige. Três regras rejeitam faturas: uma linha cujo total difere de quantidade × preço (4 linhas), um cabeçalho cujo total de produtos difere da soma das linhas (2 faturas) e um cabeçalho cujo total final difere de produtos + frete + IVA (2 faturas). Rejeita-se sempre a fatura inteira, e não só a linha, porque o frete é repartido pelo conjunto das linhas; retirar uma linha deixaria o frete das restantes sobrestimado e a soma deixaria de reconciliar. No total ficam de fora 7 das 37 faturas, 4 989,88 de 49 341,33 (10,1 % do valor).

---

## Suporte a todas as análises

Os atributos pedidos pelas dez análises (semestre, quadrimestre, semana, estação, fim de semana, último dia do mês, zona, cidade, tipo de cliente, categoria, família, produto, fornecedor, zona do fornecedor, funcionário) existem todos no modelo, ao nível da granularidade escolhida. Os níveis de *drill down* e *roll up* exigidos correspondem às hierarquias descritas acima. Um conjunto adicional de análises (evolução temporal, rankings, devoluções, prazo de pagamento, peso do frete, vendas por país) também é suportado (Anexo A).

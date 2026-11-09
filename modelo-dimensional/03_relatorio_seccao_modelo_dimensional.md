# Modelo Dimensional (secção do relatório)

> Rascunho da Leonor (A). Texto para integrar no relatório final; as tabelas completas estão em `02_modelo_dimensional_dicionario_scd.md`.

## 1. Metodologia

O data mart foi desenhado segundo a metodologia de Kimball, que organiza a modelação em quatro passos: escolha do processo de negócio, definição da granularidade, identificação das dimensões e identificação dos factos. A gestão da More Rhythm quer analisar historicamente as **vendas a clientes**, por isso o processo de negócio é a **faturação**. O resultado é um esquema em estrela com uma tabela de factos e seis dimensões, que respeita o enunciado (consultas ao nível mais elementar, histórico, Euro como moeda de uniformização).

## 2. Requisitos analíticos

As dez análises do enunciado foram decompostas em medidas, filtros, atributos de agrupamento e operações de *drill down* e *roll up* (matriz no Anexo A). Destas resultaram os requisitos do modelo:

- calendário completo (semestre, trimestre, quadrimestre, mês, semana ISO, estação do ano) e indicadores de fim de semana e último dia do mês;
- duas hierarquias de produto (família e categoria) e geografia do cliente e do fornecedor;
- tipo de cliente como nível de *roll up* distinto da geografia;
- vendas com e sem IVA e custos de expedição ao nível de família e de produto.

As análises são **indicativas**, por isso o modelo inclui também outros atributos (segmento, grupo e chefia do funcionário, nacionalidade do fornecedor, prazo de pagamento) que permitem muitas outras consultas.

## 3. Granularidade

A tabela de factos tem a granularidade de **uma linha de fatura** (um produto numa fatura). Esta escolha justifica-se porque:

1. é o nível mais baixo de detalhe disponível (`invoices_lines`) e o enunciado exige o nível mais elementar;
2. permite cruzar produto, quantidade e valores. Uma tabela ao nível da fatura perderia o produto e impossibilitaria as análises por família, categoria e produto;
3. qualquer agregação superior se obtém por soma, mas o inverso é impossível.

### Custos de expedição

O custo de expedição existe apenas no cabeçalho da fatura. Para o tornar aditivo ao nível da linha, é **alocado proporcionalmente ao valor líquido de cada linha**, sendo o resto do arredondamento absorvido pela última linha. Assim, a soma do frete alocado das linhas é igual ao frete da fatura. Foram rejeitadas as alternativas de repetir o valor em todas as linhas (duplicaria ao somar) e de manter uma tabela de factos separada ao nível da fatura (não permitiria a análise 2, por família). A alocação é realizada na Staging Area e validada no ETL.

### Moeda

Os valores são guardados na moeda original e em euros, juntamente com a taxa de câmbio do dia da fatura, mantida numa tabela de taxas. A amostra só tem euros, mas a estrutura já suporta a futura sucursal no Reino Unido sem alterações.

## 4. Dimensões e factos

| Tabela | Tipo | Conteúdo principal |
|---|---|---|
| `Fact_Vendas` | Factos | Quantidade, valor líquido, IVA, frete alocado (moeda original e EUR), fatura (dimensão degenerada) |
| `Dim_Data` | Dimensão (2 papéis) | Data da fatura e data de pagamento, com todos os níveis do calendário |
| `Dim_Cliente` | Dimensão | Dados do cliente, cidade, zona, país, tipo, segmento, vendedor |
| `Dim_Produto` | Dimensão | Produto, família, categoria, classificação, taxa de IVA |
| `Dim_Fornecedor` | Dimensão | Fornecedor, cidade, zona, tipo, nacionalidade |
| `Dim_Funcionario` | Dimensão | Funcionário, grupo, departamento, chefe |
| `Dim_Moeda`, `Dim_Taxa_Cambio` | Dimensão de apoio | Moedas e taxas de conversão para EUR |

O diagrama está na Figura 1 (`diagrama_modelo_dimensional.png`) e o dicionário de dados completo (tipos, chaves, nulabilidade) no Anexo B.

As **medidas** são aditivas (quantidade, valor líquido, IVA, frete alocado); o preço unitário é não aditivo e só se agrega por média. "Vendas com IVA" é `Valor_Liquido + Valor_IVA`, sem frete; "Total faturado" é `Valor_Liquido + Valor_IVA + Frete_Alocado`. Estas medidas são calculadas, para evitar redundância e inconsistências.

**Dimensões conformes e chaves:** todas as dimensões usam chaves substitutas, mais a chave de negócio para mapeamento. Cada dimensão tem um membro "Desconhecido" (SK −1) para valores em falta que não impeçam o carregamento.

**Fornecedor:** associa-se à linha de fatura através do produto vendido (`products.supplyer`), o que viabiliza as análises 3 e 10.

## 5. Hierarquias

| Dimensão | Hierarquias |
|---|---|
| Data | Ano > Semestre > Trimestre > Mês > Dia · Ano > Quadrimestre > Mês · Ano > Semana > Dia · Ano > Estação > Dia |
| Produto | Classificação > Família > Produto · Categoria > Produto |
| Cliente | País > Zona > Cidade > Cliente · Tipo > Cliente · Segmento > Cliente |
| Fornecedor | Zona > Cidade > Fornecedor |
| Funcionário | Departamento > Grupo > Funcionário · Chefe > Funcionário |

As hierarquias de produto e de cliente são paralelas e não aninhadas, porque família e categoria são atributos independentes do produto, tal como tipo e zona são do cliente. Os níveis estão **desnormalizados** nas dimensões (estrela, sem *snowflake*), o que simplifica as consultas e melhora o desempenho.

## 6. Estratégias de Slowly Changing Dimensions

O sistema operacional regista data e hora de criação e de cada alteração, mas não conserva os valores antigos; o histórico no data mart começa, portanto, no primeiro carregamento. As alterações são detetadas comparando o registo da origem com a versão atual da dimensão.

- **SCD tipo 1** (substituição) para atributos que apenas se corrigem ou não afetam a análise: nomes, NIF, contactos, moradas, prazos de pagamento, designação do produto.
- **SCD tipo 2** (nova versão, com `Data_Inicio`, `Data_Fim` e `Versao_Atual`) para atributos que classificam as vendas: zona, cidade, tipo e segmento do cliente e vendedor atribuído; família, categoria, classificação e taxa de IVA do produto; zona, cidade e tipo do fornecedor; grupo, departamento e chefe do funcionário.

Justificação: se um cliente mudar de zona, as vendas passadas devem manter-se na zona em que foram realizadas; com tipo 1 as análises históricas seriam alteradas retroativamente. A tabela de factos referencia a versão da dimensão vigente na **data da fatura**. `Dim_Data` e as taxas de câmbio não têm SCD, por serem imutáveis.

## 7. Clientes duplicados

O enunciado pede a eliminação dos registos duplicados, iguais ou aproximadamente iguais. O profiling encontrou três pares de clientes (10/18, 8/22 e 5/26), que afetam 9 das 37 faturas e 26 % do valor. São consolidados no sobrevivente (o registo atualizado mais recentemente), com um mapa persistente na Staging que só se desfaz por revisão. A dimensão tem uma linha por cliente real e as faturas dos clientes absorvidos passam para o sobrevivente; o facto guarda o cliente de origem (`BK_Cliente_Origem`) para rastreabilidade e para reapontar faturas se um duplicado for detetado depois da carga.

## 7.1 Dados em falta e registos rejeitados

O modelo segue um princípio comum com as regras de limpeza da Staging: um **atributo descritivo em falta** é carregado com um membro "Desconhecido" (por exemplo, produtos sem fornecedor usam `SK_Fornecedor = −1`; clientes sem zona ficam em "Zona desconhecida"), para que a venda continue visível; um problema que afete a **identificação do registo ou as medidas** (linhas de fatura com total incoerente com quantidade × preço, ou faturas cujo cabeçalho diverge da soma das linhas) leva à **rejeição da fatura** para tabelas próprias da Staging. Rejeita-se a fatura inteira, e não só a linha, para que o frete alocado continue a reconciliar com o frete da fatura.

## 8. Suporte a todas as análises

Os atributos pedidos pelas dez análises (semestre, quadrimestre, semana, estação, fim de semana, último dia do mês, zona, cidade, tipo de cliente, categoria, família, produto, fornecedor, zona do fornecedor, funcionário) existem todos no modelo, ao nível da granularidade escolhida. Os níveis de *drill down* e *roll up* exigidos correspondem às hierarquias da secção 5. Um conjunto adicional de análises (evolução temporal, rankings, devoluções, prazo de pagamento, peso do frete, vendas por país) também é suportado (Anexo A, §3).

## 9. Decisões fechadas

- "Vendas com IVA" é `Valor_Liquido + Valor_IVA`, sem frete.
- As 4 linhas com sinal negativo, as 2 faturas com cabeçalho diferente das linhas (R07) e as 2 com frete incoerente (R11) são rejeitadas até validação de negócio: 7 de 37 faturas, 10,1 % do valor.
- "Desconhecido" é reservado a atributos descritivos; chaves, medidas e relações inválidas são rejeitadas.
- Os clientes duplicados (iguais e aproximados) são consolidados no sobrevivente, com mapa persistente; o facto guarda o cliente de origem.
- O mapeamento Staging → Data Mart e as regras de rejeição são os definidos em `mappings/source-to-staging.md` e `mappings/transformacoes-limpeza.md`.

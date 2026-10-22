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

As **medidas** são aditivas (quantidade, valor líquido, IVA, frete alocado); o preço unitário é não aditivo e só se agrega por média. Os valores "com IVA" e "total faturado" são medidas calculadas, para evitar redundância e inconsistências.

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

Os clientes duplicados (exatos ou aproximados) são consolidados num único registo sobrevivente em `Dim_Cliente`. A Staging mantém um mapa entre o identificador de origem e o sobrevivente, e as faturas dos duplicados apontam para o sobrevivente, sem perda de valores. Na amostra, o data profiling identificou como potenciais duplicados o cliente *Eira e Beira, lda* (NIF 502323434), registado com os números 10 e 18.

## 7.1 Dados em falta e registos rejeitados

O modelo segue um princípio comum com as regras de limpeza da Staging: um **atributo descritivo em falta** é carregado com um membro "Desconhecido" (por exemplo, produtos sem fornecedor usam `SK_Fornecedor = −1`; clientes sem zona ficam em "Zona desconhecida"), para que a venda continue visível; um problema que afete a **identificação do registo ou as medidas** (linhas de fatura com total incoerente com quantidade × preço, ou faturas cujo cabeçalho diverge da soma das linhas) leva à **rejeição da fatura** para tabelas próprias da Staging. Rejeita-se a fatura inteira, e não só a linha, para que o frete alocado continue a reconciliar com o frete da fatura.

## 8. Suporte a todas as análises

Os atributos pedidos pelas dez análises (semestre, quadrimestre, semana, estação, fim de semana, último dia do mês, zona, cidade, tipo de cliente, categoria, família, produto, fornecedor, zona do fornecedor, funcionário) existem todos no modelo, ao nível da granularidade escolhida. Os níveis de *drill down* e *roll up* exigidos correspondem às hierarquias da secção 5. Um conjunto adicional de análises (evolução temporal, rankings, devoluções, prazo de pagamento, peso do frete, vendas por país) também é suportado (Anexo A, §3).

## 9. Decisões a rever em conjunto

- Definição de "vendas com IVA" (com ou sem frete).
- Significado do sinal nas 4 linhas de fatura com total incoerente (devoluções?) e tratamento das 2 faturas em que o cabeçalho não coincide com a soma das linhas (proposta: rejeitar a fatura).
- Política "Desconhecido" vs. rejeição (secção 7.1) e a sua articulação com as regras R01–R10 da Staging.
- Critérios de deteção de duplicados aproximados.
- Mapeamentos Staging → Data Mart, conforme o dicionário do Anexo B.

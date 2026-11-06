
# Regras de Transformação e Limpeza de Dados

## 1. Objetivo e princípios

Este documento define as regras propostas para tratar os problemas de qualidade identificados na base de dados operacional `MoreRhythm`, no âmbito da preparação dos dados para o Data Mart.

As regras devem cumprir os seguintes princípios:

- **Preservação da origem:** não alterar os dados da base operacional e preservar na Staging Area os valores extraídos necessários à auditoria.
- **Rastreabilidade:** identificar o registo de origem, a execução de carregamento, a regra aplicada e o motivo de qualquer sinalização ou rejeição.
- **Correção determinística:** corrigir automaticamente apenas situações para as quais exista uma regra inequívoca e fundamentada.
- **Rejeição controlada:** os registos com problemas de qualidade que não possam ser corrigidos automaticamente devem permanecer armazenados em estruturas próprias da Staging Area e ser excluídos do carregamento para o Data Mart.
- **Não inferência:** não inventar identificadores, classificações, valores financeiros ou relações que não sejam suportados pelos dados ou por uma regra de negócio validada.

A identificação de uma anomalia não prova, por si só, que exista um erro de negócio. Em particular, os sinais das quantidades e dos preços e as diferenças entre cabeçalhos e linhas de fatura necessitam de confirmação.

## 2. Regras de tratamento

| ID | Problema observado | Regra proposta | Tratamento previsto |
|---|---|---|---|
| R01 | Clientes duplicados, iguais ou aproximadamente iguais: pares 10 e 18, 8 e 22 e 5 e 26 | Comparar todos os pares por semelhança de nome, com atributos corroborantes (§4). Escolher o sobrevivente e registar o mapeamento origem → sobrevivente. | Consolidar cada grupo num único cliente na Staging; as faturas dos clientes absorvidos passam para o sobrevivente. Os identificadores originais ficam no mapeamento e a origem não é alterada. |
| R02 | Email e telemóvel em falta; email com formato inválido (1 cliente, 2 funcionários); NIF não identificativo (vazio, só zeros) | Considerar ausente o valor vazio, só com espaços, ou que não cumpra o formato; distinguir atributos opcionais de obrigatórios. | Preservar o valor original; a coluna transformada fica `NULL`. A ausência de contacto, por si só, não exclui uma venda do Data Mart. Um NIF não identificativo não entra na deteção de duplicados. |
| R03 | Zona em falta em clientes | Verificar o valor de origem e a existência de uma correspondência válida. | Não inferir uma zona. Preservar o valor em falta e definir, no modelo dimensional, o tratamento adequado para a zona desconhecida, se aplicável. |
| R04 | Atributos de produto em falta | Validar designação, família, categoria, fornecedor, stock e preço de venda de acordo com a utilização analítica de cada atributo. | Preservar os valores originais e sinalizar os campos em falta. Não inventar valores comerciais nem rejeitar automaticamente todos os factos associados sem avaliar o impacto no modelo dimensional. |
| R05 | 12 linhas de compra sem referência de produto | Identificar referências nulas ou vazias em `purchases_lines.product`. | Manter os registos na Staging Area, encaminhá-los para uma estrutura própria de registos com problemas de qualidade e excluí-los do Data Mart enquanto não for possível identificar o produto de forma fiável. Não atribuir um produto arbitrário. |
| R06 | Quatro linhas de fatura em que quantidade × preço unitário difere de `line_total` | Comparar o valor registado com o cálculo, preservando os sinais e os valores originais. | Sinalizar os quatro casos para investigação. Não aplicar valores absolutos, inverter sinais ou substituir totais sem confirmação da regra de negócio. Se o problema não puder ser resolvido automaticamente e afetar a fiabilidade das medidas, manter os registos na estrutura própria de rejeições da Staging Area e excluí-los do carregamento analítico. |
| R07 | Duas faturas em que o total de produtos do cabeçalho difere da soma das linhas | Calcular e registar a diferença entre o cabeçalho e as linhas, com uma tolerância documentada de 0,01 para comparação monetária. | Sinalizar as duas faturas. Não escolher automaticamente um dos totais. Se a discrepância não puder ser corrigida de forma fiável e comprometer as medidas carregadas no Data Mart, manter os registos afetados na estrutura própria de rejeições da Staging Area e excluí-los do carregamento analítico. |
| R08 | Possíveis referências a entidades inexistentes | Validar as referências não nulas contra as entidades de origem correspondentes. | Os testes atuais não encontraram referências inválidas nas relações verificadas. Se forem detetadas em cargas futuras, sinalizar e manter os registos problemáticos na estrutura própria da Staging Area, excluindo-os do Data Mart até resolução. |
| R09 | Diferenças de representação textual | Aplicar normalização controlada, como remoção de espaços exteriores e normalização de maiúsculas/minúsculas para comparação. | Utilizar valores normalizados para validação e comparação, sem perder os valores originais. Não modificar nomes ou identificadores de negócio de forma irreversível. |
| R10 | Repetição de registos em cargas sucessivas | Usar as chaves primárias da origem e os atributos de criação/última atualização disponíveis para identificar registos novos ou alterados. | Implementar carregamento incremental idempotente. Uma nova execução não deve duplicar registos já carregados; a estratégia concreta depende da validação dos campos de auditoria e será especificada na etapa de carregamento incremental. |

## 3. Classificação dos problemas

Os registos e atributos devem ser classificados de acordo com a natureza do problema e o efeito sobre as análises:

- **Correção automática segura:** apenas quando a transformação é determinística, por exemplo, remover espaços exteriores para efeitos de comparação, mantendo o valor original.
- **Atributo opcional em falta:** preservar o valor nulo e permitir o carregamento do registo se este continuar válido para o processo analítico.
- **Problema por investigar:** preservar os dados, registar a regra violada e não assumir uma correção sem evidência suficiente.
- **Registo rejeitado do Data Mart:** quando um problema não pode ser corrigido automaticamente e compromete a identificação ou a interpretação correta do facto, manter o registo numa estrutura própria da Staging Area e excluí-lo do carregamento analítico.

A rejeição deve ser aplicada ao nível do registo e com base no impacto concreto. Um atributo opcional em falta não deve provocar a rejeição de toda a venda sem justificação. Inversamente, uma linha de compra sem produto não deve ser carregada como se o produto fosse conhecido.

## 4. Normalização e duplicados de clientes

O enunciado pede a eliminação das redundâncias «iguais ou aproximadamente iguais». A igualdade exata de contribuinte e nome só encontra um par (10 e 18); a comparação por semelhança encontra mais dois (8 e 22; 5 e 26). Os resultados estão em [`resultados.md`](../data-profiling/resultados.md), §5.

### 4.1. Normalização para comparação

A normalização aplica-se a cópias de comparação; os valores originais são preservados.

- **Nome:** maiúsculas, sem pontuação, sem as formas jurídicas `LDA` e `SA`, espaços repetidos reduzidos a um.
- **Morada:** maiúsculas, sem pontuação, `R` inicial expandido para `RUA`.
- **NIF:** só é considerado se tiver 9 dígitos e não for composto só por zeros.
- **Email:** só é considerado se tiver formato válido (um `@`, um `.` depois, sem espaços).
- **Telefone:** dígitos de `phone` e `mobile`, sem espaços nem prefixo `+`.

### 4.2. Critério de deteção

Para cada par de clientes calcula-se a semelhança do nome (1 menos a distância de Levenshtein dividida pelo comprimento da maior cadeia). Um par é duplicado quando:

1. a semelhança do nome é pelo menos 0,80; e
2. existem pelo menos dois atributos corroborantes entre: mesmo código postal; semelhança da morada pelo menos 0,80; mesmo telefone ou telemóvel; mesmo email válido; mesmo BBAN; NIF válidos com distância de Levenshtein não superior a 2.

O nome sozinho não decide (os clientes internos 24 e 25 têm semelhança 0,85 sem corroboração e ficam distintos). O dígito de controlo do NIF não é usado, porque a maior parte dos contribuintes da amostra falha a verificação, incluindo os dos pares encontrados. Nenhum cliente pertence a mais de um par; um grupo com mais de dois membros seria formado por componentes ligados.

O limiar 0,80 e o mínimo de duas corroborações foram validados sobre a amostra (sensibilidade em `resultados.md` §5.2). Na implementação em SSIS a deteção usa o componente *Fuzzy Grouping*, com o limiar de semelhança calibrado sobre os mesmos pares; o resultado esperado é o mesmo mapeamento.

### 4.3. Sobrevivente e valores consolidados

- **Sobrevivente:** o membro com a atualização mais recente (`last_update_date` e `last_update_time`); em caso de empate, o menor número de cliente. Resultado: 18 (grupo 10 e 18), 5 (grupo 5 e 26) e 8 (grupo 8 e 22).
- **Atributos:** para cada atributo usa-se o valor do sobrevivente quando é válido; se for ausente ou inválido, usa-se o valor válido do membro absorvido. Assim, o grupo 5 e 26 fica com o email `coro@sapo.pt` do cliente 26 (o do cliente 5 é inválido) e o grupo 8 e 22 fica com o telefone do cliente 22.
- **Divergências:** quando os dois valores são válidos e diferentes (NIF, nome, morada nos grupos 5 e 26 e 8 e 22), prevalece o do sobrevivente e a divergência fica registada em `review_note`. Os dados não permitem saber qual dos NIF está correto; o risco fica assumido e documentado.
- **Chave de negócio no Data Mart:** o número do sobrevivente. As faturas de todos os membros do grupo são ligadas ao sobrevivente antes da carga de `Fact_Vendas`.

### 4.4. Mapeamento e rastreabilidade

`stg_customer_duplicate_groups` guarda, por cliente de origem, o grupo, o sobrevivente, o critério (semelhança e atributos corroborantes) e a nota de divergência. O mapeamento é recalculado em cada carga, antes da dimensão Cliente. Se uma carga futura detetar um novo duplicado, as faturas ainda não carregadas seguem o novo mapeamento e as já carregadas são reapontadas ao sobrevivente.

### 4.5. Fornecedores

Os fornecedores 8 e 14 têm o mesmo NIF mas localidade, zona, contactos e produtos diferentes; são tratados como estabelecimentos distintos da mesma entidade e não são consolidados (a zona do fornecedor é usada na análise 10).

## 5. Tratamento dos problemas financeiros

O profiling identificou quatro linhas de fatura em que `line_total` difere de `quantity × unit_price`, bem como duas faturas cujo total de produtos no cabeçalho diverge da soma dos totais das linhas.

Os sinais observados podem estar relacionados com convenções de negócio, devoluções ou outros procedimentos, mas os resultados disponíveis não confirmam nenhuma dessas explicações. Assim:

1. Preservar os valores originais e calcular os indicadores de discrepância numa etapa de validação.
2. Registar o identificador do documento/linha, a regra violada e a diferença calculada.
3. Não alterar quantidades, preços ou totais sem uma regra de negócio validada.
4. Se não existir uma correção determinística e a discrepância afetar a fiabilidade das medidas, manter o registo na estrutura própria de rejeições da Staging Area e excluí-lo do Data Mart.

O custo de expedição está registado ao nível do cabeçalho da fatura. Não deve ser repetido em cada linha de produto nem somado como se fosse uma medida ao nível da linha, pois isso multiplicaria artificialmente o custo. O tratamento dimensional definitivo deve respeitar a granularidade aprovada para os factos.

## 6. Valores em falta e integridade referencial

Os resultados atuais identificam valores em falta em atributos de clientes e produtos e 12 linhas de compra sem produto. Os testes de integridade referencial realizados não encontraram referências inválidas nas relações verificadas; contudo, este resultado não elimina os problemas de completude.

O tratamento deve distinguir:

- **Contactos em falta:** preservar os nulos; não são, por si só, motivo para excluir um facto de venda.
- **Atributos descritivos de produto em falta:** preservar e sinalizar; avaliar se impedem a identificação ou análise do produto.
- **Zona em falta:** não inferir a zona; definir tratamento consistente com o modelo dimensional.
- **Produto em falta numa linha de compra:** não é possível atribuir a linha a um produto conhecido; manter na Staging Area de rejeições e excluir do Data Mart enquanto não for resolvida.
- **Referência não nula sem correspondência:** sinalizar como problema de integridade e impedir o carregamento da relação inválida.

A utilização de membros desconhecidos no Data Mart só deverá ocorrer quando for compatível com o modelo dimensional e não ocultar um problema que, segundo o enunciado, exige a exclusão do registo do Data Mart.

## 7. Rastreabilidade e auditoria

A Staging Area deverá permitir identificar, sempre que aplicável:

- a tabela e a chave do registo de origem;
- a execução de extração/carregamento;
- os valores originais relevantes;
- o estado de validação;
- o identificador da regra aplicada;
- a descrição do problema e a decisão de carregamento ou rejeição.

Os registos que não possam ser corrigidos automaticamente devem ser conservados em estruturas próprias da Staging Area, conforme o enunciado. A sua exclusão do Data Mart não significa apagar os dados da área de preparação nem da origem operacional.

## 8. Contrato de carregamento e decisões fechadas

As regras desta especificação são aplicadas pela ordem seguinte:

1. Extrair o valor original e os metadados técnicos para a Staging Area.
2. Normalizar apenas cópias de comparação e calcular os indicadores de validação.
3. Aplicar as correções determinísticas permitidas.
4. Classificar cada registo como `VALID`, `CORRIGIDO`, `PENDENTE` ou `REJEITADO`.
5. Carregar para o Data Mart apenas registos `VALID` ou `CORRIGIDO`.

Ficam fechadas as seguintes decisões para a Fase 1:

- **Clientes duplicados:** os pares 10 e 18, 8 e 22 e 5 e 26 são consolidados no sobrevivente (§4), com mapeamento origem → sobrevivente em `stg_customer_duplicate_groups`. Os identificadores originais não se perdem; a origem não é alterada.
- **Quantidades e preços negativos:** não são convertidos para valores absolutos nem reinterpretados como devoluções. As quatro linhas financeiras e as respetivas faturas são `REJEITADO` até existir confirmação da semântica.
- **Divergências de cabeçalho:** as duas faturas com diferença entre o total de produtos e a soma das linhas são rejeitadas integralmente. A rejeição ao nível da fatura preserva a reconciliação do frete alocado.
- **Produto desconhecido em compras:** as 12 linhas ficam em `stg_rejections` com os valores originais; não entram no Data Mart de vendas.
- **Membro desconhecido:** só é usado para atributos descritivos ausentes que não impedem a identificação do facto, por exemplo fornecedor, zona ou contacto. Nunca substitui uma referência de produto, cliente, documento, quantidade, preço ou total inválida.
- **Contactos opcionais:** permanecem `NULL`. Valores vazios são normalizados para `NULL` numa coluna transformada, conservando o valor bruto.
- **Vendas com IVA:** `Valor_Liquido + Valor_IVA`, sem frete. O frete apenas entra em `Total_Faturado` e nas análises que o pedem explicitamente. A origem indica IVA ao nível dos produtos, pelo que não se presume IVA sobre o frete.
- **Frete:** é alocado proporcionalmente ao valor líquido das linhas válidas da fatura, arredondado a 6 casas, e o resíduo é atribuído à última linha por ordem estável de `invoice_line_stamp_id`. Se alguma linha da fatura for rejeitada, a fatura inteira é rejeitada.
- **Moeda:** a taxa é obtida de uma fonte de câmbio versionada por moeda e data da fatura. Para EUR a taxa é 1. Se não existir taxa aplicável, o registo fica rejeitado; não se usa a taxa do dia anterior sem regra documentada.
- **Idempotência:** `source_table + source_pk + load_id` identifica a extração e `source_table + source_pk` identifica o registo lógico. O Data Mart usa as chaves de negócio e `MERGE`/upsert controlado; repetir o mesmo lote não cria factos adicionais.

Estas decisões substituem as formulações de “decisão pendente” existentes nos documentos e devem ser usadas como referência pelos mapeamentos e pelo ETL.

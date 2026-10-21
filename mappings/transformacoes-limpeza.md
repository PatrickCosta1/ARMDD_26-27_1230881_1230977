
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
| R01 | Clientes 10 e 18 com número de contribuinte e nome normalizados iguais | Comparar o contribuinte normalizado e outros atributos de identificação, preservando os identificadores originais. | Classificar como potenciais duplicados. Não consolidar automaticamente nem eliminar qualquer cliente antes de definir uma regra determinística e preservar as referências às faturas. |
| R02 | Email e telemóvel em falta em clientes | Distinguir atributos opcionais de atributos obrigatórios para cada análise. | Preservar os valores nulos. A ausência de contacto, por si só, não deve excluir uma venda do Data Mart, salvo se um requisito analítico justificado o exigir. |
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

## 4. Normalização e potenciais duplicados

Antes de comparar campos textuais, podem ser aplicadas regras de normalização, tais como remoção de espaços exteriores e uniformização de maiúsculas/minúsculas. Para números de contribuinte, a comparação pode ignorar separadores de formatação, desde que o valor original seja preservado.

Os clientes 10 e 18 apresentam o mesmo número de contribuinte normalizado (`502323434`), o mesmo nome normalizado (`EIRA E BEIRA, LDA`) e os mesmos principais atributos de identificação e contacto analisados. São, por isso, **potenciais duplicados**, não duplicados definitivamente confirmados.

A consolidação exige uma regra explícita para escolher a referência canónica, mapear os identificadores alternativos e preservar as relações com as faturas. Os resultados do profiling indicam faturas associadas a ambos os clientes; os respetivos valores não podem ser eliminados nem agregados sem uma decisão fundamentada.

Até essa decisão, ambos os registos devem ser preservados na Staging Area e a ambiguidade deve ser resolvida antes de carregar a dimensão Cliente.

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

## 8. Limitações e decisões pendentes

As regras são uma especificação de tratamento baseada nos resultados de profiling disponíveis. Não substituem a validação das regras de negócio nem a definição final do modelo dimensional.

Antes da implementação, é necessário confirmar:

- a regra de consolidação dos clientes 10 e 18;
- o significado dos sinais nas quatro linhas de fatura;
- a origem das diferenças nas duas faturas;
- quais os atributos de produto obrigatórios para as análises;
- a granularidade dos factos e a forma de tratar medidas ao nível do cabeçalho, incluindo o custo de expedição;
- os campos de auditoria efetivamente fiáveis para o carregamento incremental.

As decisões finais devem ser coerentes com o modelo dimensional e com o requisito de excluir do Data Mart os registos com problemas não corrigíveis automaticamente, mantendo-os em estruturas próprias da Staging Area.

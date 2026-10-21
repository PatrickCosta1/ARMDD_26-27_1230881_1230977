# Regras de Transformação e Limpeza de Dados

## 1. Objetivo

Este documento define as regras propostas para tratar os problemas de qualidade identificados na base de dados operacional MoreRhythm. As regras destinam-se a orientar a preparação dos dados na Staging Area e o seu posterior carregamento para o Data Mart.

As transformações devem preservar a rastreabilidade dos dados de origem. Os registos que não possam ser corrigidos de forma fiável devem ser identificados e encaminhados para análise, em vez de serem eliminados automaticamente.

## 2. Regras de tratamento

| ID | Problema | Regra proposta | Tratamento |
|---|---|---|---|
| R01 | Clientes potencialmente duplicados | Comparar o número de contribuinte normalizado e os atributos de identificação. | Identificar os clientes 10 e 18 como candidatos a consolidação. A decisão final deve ser validada antes de consolidar as referências. |
| R02 | Campos de contacto em falta | Identificar os campos nulos ou vazios, preservando o valor original. | Manter os campos opcionais sem valor e sinalizar os casos em que o atributo seja necessário para uma análise. |
| R03 | Zona do cliente em falta | Verificar se existe uma zona válida na origem. | Não atribuir uma zona por inferência. Manter o valor original e utilizar um membro desconhecido no Data Mart, se necessário. |
| R04 | Atributos de produto em falta | Validar designação, família, categoria, fornecedor, stock e preço de venda. | Preservar os dados originais e sinalizar os atributos em falta. Não inventar classificações ou valores comerciais. |
| R05 | Linhas de compra sem produto | Identificar as linhas em que a referência do produto é nula ou vazia. | Preservar as 12 linhas na Staging Area e encaminhá-las para investigação. Não associar um produto arbitrário. |
| R06 | Quantidade ou preço unitário negativo em linhas de fatura | Identificar os registos e analisar o documento associado antes de determinar o significado dos sinais. | Preservar os valores originais e sinalizar os casos para investigação. Não aplicar valores absolutos automaticamente. |
| R07 | Diferença entre total do cabeçalho e soma das linhas | Comparar o total de produtos da fatura com a soma dos totais das linhas. | Registar a diferença e sinalizar os documentos com discrepâncias superiores a 0,01, sem substituir automaticamente os valores. |
| R08 | Referência a entidade inexistente | Verificar as relações entre as tabelas de origem. | Sinalizar eventuais referências sem correspondência e impedir que sejam carregadas como relações válidas sem tratamento. |
| R09 | Normalização de texto | Remover espaços exteriores e uniformizar a representação textual quando adequado. | Aplicar a normalização de forma consistente, preservando os valores originais para auditoria. |
| R10 | Carregamentos repetidos | Identificar os registos através das chaves da origem e de critérios de atualização. | Definir o processo incremental para evitar a duplicação de registos no Data Mart. |

## 3. Normalização e identificação de duplicados

A normalização de campos textuais deve ser aplicada antes da comparação de registos, considerando espaços exteriores, diferenças entre maiúsculas e minúsculas e separadores nos números de contribuinte.

A normalização não deve alterar os identificadores originais. No caso dos clientes 10 e 18, os resultados observados indicam uma forte possibilidade de duplicação. A consolidação deverá preservar a rastreabilidade dos dois identificadores e das respetivas faturas.

## 4. Tratamento dos registos com problemas

Os registos com problemas devem ser classificados de acordo com a possibilidade de tratamento:

- **Corrigíveis automaticamente:** situações em que existe uma regra determinística e fundamentada, como a remoção de espaços exteriores.
- **A manter com informação em falta:** atributos opcionais que não impedem a utilização do registo em todas as análises.
- **A investigar:** casos em que a origem não permite determinar o valor correto, como as linhas de compra sem produto ou as inconsistências financeiras.
- **A rejeitar do carregamento analítico:** registos que não cumpram os requisitos mínimos de qualidade e não possam ser corrigidos de forma fiável, mantendo-se a informação necessária à sua análise na Staging Area.

A classificação definitiva de cada registo dependerá também dos requisitos do modelo dimensional e das análises pretendidas.

## 5. Rastreabilidade

Sempre que possível, a Staging Area deverá preservar as chaves de origem, os valores originais relevantes, a identificação da regra aplicada e o motivo pelo qual um registo foi sinalizado ou rejeitado.

Esta abordagem permite explicar as transformações efetuadas e investigar discrepâncias sem modificar a base de dados operacional.

## 6. Limitações

As regras aqui propostas não pressupõem que todas as situações identificadas sejam erros de origem. Em particular, os valores negativos nas linhas de fatura e as diferenças entre cabeçalhos e linhas carecem de confirmação da regra de negócio.

As regras deverão ser revistas após a definição da granularidade, das medidas e das dimensões do Data Mart.
Esta secção especifica a parte do processo que leva os registos validados da Staging para as dimensões e para a tabela de factos. Continua a anterior: o pacote `Mestre` abre o lote, a extração, a validação e a deteção de duplicados deixam a Staging pronta, e só então carregam as dimensões e o facto. Como na secção anterior, nada foi ainda construído no *Integration Services Project*: os nomes dos pacotes e a escolha dos componentes são a proposta para a 2.ª parte. A lógica de transformação foi experimentada num protótipo em T-SQL sobre a amostra (incluído no repositório, na pasta `prototipo-carga`), o que permitiu fixar as regras e os resultados esperados. O protótipo valida a lógica e não é o processo em SSIS.

## Pacotes e ordem de execução

| Ordem | Pacote (proposto) | Conteúdo | Depende de |
|---|---|---|---|
| 5 | `Calendario` | Carrega `Dim_Data` e `Dim_Taxa_Cambio` apenas para as datas e moedas que ainda não existem (executa-se na 1.ª carga e quando o calendário é alargado) | — |
| 6 | `Dimensoes` | Quatro fluxos de dados independentes, um por dimensão (cliente, produto, fornecedor e funcionário), num *Sequence Container* | Pacote 4 (mapa de duplicados) |
| 7 | `Facto` | Fluxo de dados de `Fact_Vendas`, dentro de uma transação | Pacotes 5 e 6 |
| 8 | `Reconciliacao` | Tarefas SQL de controlo; se alguma falhar, o lote fica `FAILED` | Pacote 7 |

As dimensões carregam antes do facto, porque o facto resolve as chaves substitutas nas dimensões. A dimensão do cliente espera pelo pacote dos duplicados, porque só os sobreviventes originam linhas.

## Dimensões

As quatro dimensões seguem o mesmo padrão. A origem é a consulta que junta as tabelas `stg_` envolvidas e devolve só os registos `VALID` ou `CORRIGIDO` do lote. A seguir:

1. Uma *Derived Column* aplica as transformações do mapeamento (limpeza de texto, `N/D` para o NIF não identificativo, valores por omissão) e calcula os dois *hashes*: `Hash_SCD1`, dos atributos de tipo 1, e `Hash_SCD2`, dos de tipo 2.
2. Um *Lookup* procura a versão corrente (`Versao_Atual = 1`) pela chave de negócio.
3. Um *Conditional Split* separa quatro casos:
   - **chave nova** → insere a 1.ª versão, com início em 1900-01-01, para que os factos históricos encontrem versão;
   - **`Hash_SCD1` diferente** → atualiza os atributos de tipo 1 em **todas** as versões dessa chave;
   - **`Hash_SCD2` diferente** → fecha a versão corrente (fim = início da nova menos um dia, `Versao_Atual = 0`) e insere a nova versão, que começa na data da alteração na origem (nunca antes do início da versão anterior mais um dia);
   - **hashes iguais** → não faz nada, pelo que repetir o lote é inofensivo.
4. As inserções vão por *fast load*. As atualizações e os fechamentos gravam-se numa tabela temporária e executam-se numa só instrução `UPDATE ... JOIN` por conjuntos. Não se usa o *OLE DB Command* (uma instrução por linha) nem o componente *Slowly Changing Dimension*, que processa registo a registo.

Algumas decisões ficam explícitas:

- **Cliente.** Só os sobreviventes do mapa de duplicados geram linhas. Cada atributo toma o valor do sobrevivente quando é válido, ou o do membro absorvido quando o do sobrevivente é ausente ou inválido. Quando muda o vendedor atribuído a um cliente, ou o chefe de um funcionário, compara-se o número do funcionário (que o identifica) e não o nome: se alguém apenas mudar de nome, o nome atualiza-se nas versões existentes e não se abre uma versão nova.
- **Registos que não carregam.** Os clientes sem zona e os produtos sem designação, família ou categoria não entram nas dimensões e ficam em `stg_rejections`; na amostra isso não afeta nenhuma fatura (clientes 2 e 20; produtos `Z001` e `CORSR`).
- **Membros "Desconhecido".** O membro `SK = −1` de cada dimensão existe desde a criação do esquema; só o fornecedor o usa em dados reais (12 produtos sem fornecedor).
- **Calendário.** `Dim_Data` cobre 2020 a 2035 e as taxas de câmbio EUR = 1; o intervalo de anos é um parâmetro.

## Tabela de factos

Cada linha de fatura válida origina uma linha de `Fact_Vendas`:

1. **Quais as linhas.** A consulta de origem junta `stg_invoices_lines` e `stg_invoices` e só devolve faturas que não foram rejeitadas por R06, R07 ou R11. As linhas de uma fatura rejeitada ficam todas de fora.
2. **Chaves substitutas.** São resolvidas pela data da fatura (`Data_Inicio ≤ data ≤ Data_Fim`) em `Dim_Cliente` (depois de passar pelo mapa de duplicados), `Dim_Produto`, `Dim_Funcionario`, `Dim_Moeda` e `Dim_Taxa_Cambio`; o fornecedor vem do produto vendido e usa o membro −1 quando o produto não tem fornecedor. Como o *Lookup* de cache total só compara igualdades, a pesquisa por intervalo de datas é feita por junção na própria consulta de origem, por conjuntos.
3. **Valores.** Quantidade, preço, valor líquido e IVA copiam-se da linha, sem alterar o sinal. O frete é o `frete_alocado` já calculado na validação (proporcional ao valor da linha, com o resto de arredondamento na última). Os valores em euros são o valor original vezes a taxa do dia da fatura, arredondados a seis casas.
4. **Rastreabilidade.** `BK_Cliente_Origem` guarda o cliente de origem da fatura antes de consolidar; `ID_Lote_ETL` o lote; `Data_Atualizacao_Origem` é a mais recente entre a linha e o cabeçalho; e `Hash_Linha` combina os *hashes* da linha e do cabeçalho, porque uma alteração ao frete no cabeçalho muda a alocação de todas as linhas sem alterar as linhas.
5. ***Upsert* por `BK_Linha_Fatura`.** Um `UPDATE` reaplica as linhas existentes cujo `Hash_Linha` mudou e um `INSERT` acrescenta as novas. Uma linha cujo *hash* não mudou não é tocada. A carga do facto corre numa só transação: se falhar, o Data Mart fica como estava.

Uma alteração a um atributo de tipo 2 de uma dimensão (por exemplo a zona de um cliente) não reaponta factos antigos, que continuam na versão com que foram carregados. Só as faturas posteriores à alteração usam a versão nova.

## Reconciliação

O pacote `Reconciliacao` faz, depois de cada carga, os seguintes controlos; se algum falhar, o lote fica `FAILED`:

| Controlo | Resultado esperado na amostra |
|---|---|
| Faturas e linhas carregadas igual às faturas e linhas válidas da Staging | 30 de 37 faturas e 82 de 93 linhas (ficam de fora as 7 faturas rejeitadas e as suas 11 linhas) |
| `Σ Frete_Alocado` por fatura igual a `shipping_cost` | diferença zero |
| `Σ (Valor_Liquido + Valor_IVA + Frete_Alocado)` por fatura igual a `final_total` (tolerância 0,01) | diferença zero |
| `Σ Valor_Liquido` igual à soma de `products_total` das faturas carregadas | os dois valores coincidem |
| Valores em euros iguais aos originais (moeda `EURO`, taxa 1) | iguais |
| As faturas dos clientes de cada par duplicado apontam para o mesmo `SK_Cliente` | sim; `BK_Cliente_Origem` guarda os dois clientes |
| Repetir a carga | 0 linhas inseridas e 0 atualizadas |

## Erros e repetição

Os erros técnicos (ligação, tipos, destino) falham o componente e o manipulador `OnError` do pacote `Mestre` marca o lote `FAILED`. Como o facto se carrega numa transação e as dimensões só alteram o que mudou, repetir a execução é seguro: o que já estava carregado não se repete e o que ficou por carregar volta a ser lido.

## Medidas de eficiência

- A carga é incremental: só se tocam registos novos ou alterados, detetados por *hash* e não por comparação coluna a coluna.
- As dimensões carregam em paralelo e as transformações fazem-se por conjuntos, em instruções SQL, e não registo a registo.
- O facto resolve as chaves por junção e escreve por *fast load*; as atualizações vão numa só instrução.
- Os índices sustentam as pesquisas: um índice único filtrado por chave de negócio nas versões correntes (que também garante uma só versão corrente por chave) e um índice único em `BK_Linha_Fatura`, para o *upsert*. Existe ainda um índice em `BK_Cliente_Origem` para o reapontamento.
- Não se usam componentes bloqueantes (*Sort*, *Aggregate*) no fluxo dos factos.

Não foram feitas medições de desempenho: a amostra é pequena e o volume real é muito superior; as medições ficam para a 2.ª parte.

## Duplicado detetado depois da carga

Se um duplicado só for detetado quando os dois clientes já foram carregados em separado, o mapa passa a ter uma decisão nova e é preciso reapontar as faturas já carregadas. O reapontamento fica especificado e **não é implementado nesta fase**: os factos dos clientes absorvidos (`BK_Cliente_Origem`) passam à versão do sobrevivente vigente na data de cada fatura, num só `UPDATE`, As linhas dos clientes absorvidos são depois removidas da dimensão, na mesma transação, para que a dimensão fique com uma linha por cliente real; o histórico fica guardado em `BK_Cliente_Origem` e no mapa da Staging.

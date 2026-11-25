# Missão NOVA — exercício interativo de prova social

Atividade concebida para o webinar **«Prova social no marketing: como as avaliações influenciam as decisões de compra?»** (e-Tutor Diogo Cruz). Utiliza o repositório **Mav_webinars** e o mesmo projeto Supabase do sistema «Jornada do Consumidor», sem substituir os ficheiros desse webinar.

## Preparação única

1. No projeto Supabase que já utiliza no MAV Pulse, abra **SQL Editor → New query**.
2. Abra [instalar.sql](instalar.sql), copie **todo** o conteúdo e execute-o no SQL Editor. O script acrescenta uma tabela de respostas e duas funções seguras. Não altera o webinar anterior nem elimina dados.
3. Confirme que a conta de apresentador tem permissões na tabela **public.jornada_hosts** (a mesma usada na Jornada do Consumidor).
4. Confirme que [../config.js](../config.js) está corretamente configurado; **não** cole chaves secretas neste ficheiro.
5. Utilize os links abaixo, quando o GitHub Pages tiver publicado os ficheiros.

## Links

- [Página inicial](https://diseven1990.github.io/Mav_webinars/prova-social/)
- [Painel do apresentador](https://diseven1990.github.io/Mav_webinars/prova-social/?modo=apresentador)
- [Entrada dos formandos](https://diseven1990.github.io/Mav_webinars/prova-social/?modo=participar)

A vista do OBS é gerada no painel depois de criar a sessão, porque cada sessão tem um identificador diferente. Ao selecionar **Abrir vista OBS**, copie o URL apresentado no separador e use-o como **Browser Source** do OBS, idealmente em **1280 × 720** ou **1920 × 1080**.

## Durante o webinar

1. Abra o painel do apresentador e inicie sessão com as credenciais habituais.
2. Crie uma nova sessão. O painel indica o código de 6 caracteres e fornece um link para o YouTube ou chat.
3. Mostre o QR Code apresentado no **painel do apresentador** ou na **vista OBS**, para os formandos entrarem diretamente com o código da sessão preenchido. Em alternativa, partilhe o link ou o código de seis caracteres. Os formandos introduzem o nome ou um pseudónimo e ficam na sala de espera.
4. No slide final da apresentação, abra a cena do OBS que mostra a Missão NOVA.
5. Carregue em **Iniciar decisão 1**; a pergunta aparece nos dispositivos dos formandos e na vista de transmissão.
6. Quando decidir, carregue em **Revelar respostas**. A correção, as percentagens e a classificação ficam visíveis.
7. Repita com as decisões 2 e 3. Cada resposta certa vale **100 pontos**; não existe bónus de rapidez.
8. Regresse à cena do OBS com a apresentação para concluir o webinar.

## Conteúdo dos 3 desafios

| Decisão | Pergunta | Resposta recomendada |
|---|---|---|
| 1 — Visibilidade | Onde mostrar testemunhos detalhados? | B — Na página de produto, perto da informação relevante |
| 2 — Reputação | Como responder a uma avaliação negativa legítima? | C — Reconhecer o problema e disponibilizar acompanhamento concreto |
| 3 — Métricas | Como medir o impacto da prova social? | A — Cruzar a interação com avaliações e a conversão |

O guião do webinar desenvolve a fundamentação de cada escolha.

## Notas técnicas

- O **GitHub Pages** aloja a interface, mas **não** armazena as respostas. A sincronização e os resultados dependem do Supabase.
- A resposta é corrigida **na base de dados**, não apenas no navegador. A função confirma que a pergunta está aberta e impede respostas repetidas.
- O painel do apresentador mostra participantes inscritos, presenças ativas e respostas recebidas. A contagem de presenças não corresponde à audiência total do YouTube.
- Os resultados só ficam disponíveis aos participantes quando o apresentador os revela.
- O acesso à sessão é feito por código. Se houver participações com nomes semelhantes, o ranking poderá mostrar nomes repetidos; cada conta anónima é contabilizada de forma independente.
- Para experimentar o formulário do participante, utilize **outro navegador, uma janela privada ou outro dispositivo**, para não interferir com a sessão autenticada do apresentador.
- O vídeo do YouTube pode ter atraso. As perguntas estão visíveis diretamente no jogo, e o apresentador decide quando revelar; não existe um limite de resposta automático.
- O ficheiro de apresentação do webinar é independente. **A apresentação não muda de slide automaticamente** com esta atividade. A vista específica do exercício é adicionada ao OBS como fonte de navegador e pode ser exibida numa cena própria.

Se aparecer **"Could not find function ps_stats"** ou **"relation prova_social_answers does not exist"**, verifique se o [instalar.sql](instalar.sql) foi executado no projeto Supabase correto.

## QR Code

O painel e a vista OBS geram um QR Code diferente para cada sessão, apontando para o endereço de participação com o código previamente preenchido. O QR Code é gerado pelo serviço externo `api.qrserver.com`; ao gerar a imagem, o endereço público de participação (incluindo o código da sessão) é enviado a esse serviço. **Não** inclui nomes, palavras-passe ou respostas. Se não quiser utilizar um serviço externo, partilhe o link e o código apresentados no painel.

/* Conteúdos pedagógicos baseados nos slides e notas do orador: Jornada do Consumidor. */
window.JORNADA_GAMES = [
  {
    id:'ordem', slide:2, type:'order', label:'01 / O percurso', title:'Ponha a jornada em ordem',
    description:'Organize as cinco etapas de referência. Na realidade, o consumidor pode avançar, recuar ou interromper este percurso.',
    duration:'2–3 min',
    initial:['compra','descoberta','poscompra','consideracao','decisao'],
    items:{descoberta:'Descoberta',consideracao:'Consideração',decisao:'Decisão',compra:'Compra',poscompra:'Pós-compra'},
    correct:['descoberta','consideracao','decisao','compra','poscompra'],
    explanation:'Descoberta → Consideração → Decisão → Compra → Pós-compra. É um modelo de análise: o percurso real não é linear.'
  },
  {
    id:'associar', slide:5, type:'match', label:'02 / Ligar os pontos', title:'Cada ação no seu momento',
    description:'Associe cada ação de marketing à etapa da jornada em que é mais relevante.',duration:'3 min',
    items:[
      {id:'post_blog',label:'Vídeo sobre como transportar o portátil sem desconforto'},
      {id:'comparador',label:'Comparação entre modelos, materiais e opiniões'},
      {id:'politica',label:'Explicação clara de garantia e devoluções'},
      {id:'checkout',label:'Pagamento com custo total visível'},
      {id:'seguimento',label:'Mensagem de acompanhamento da encomenda'}
    ],
    stages:['descoberta','consideracao','decisao','compra','poscompra'],
    correct:{post_blog:'descoberta',comparador:'consideracao',politica:'decisao',checkout:'compra',seguimento:'poscompra'},
    explanation:'O conteúdo informativo abre a descoberta; a comparação ajuda na consideração; garantias reduzem risco na decisão; checkout é compra; acompanhamento pertence ao pós-compra.'
  },
  {
    id:'erros', slide:6, type:'spot', label:'03 / Caça ao erro', title:'O que estraga este checkout?',
    description:'Esta loja já convenceu o consumidor. Selecione os TRÊS obstáculos que podem fazê-lo desistir da compra.', duration:'2 min',
    options:[
      {id:'portes',label:'Portes de envio apenas revelados no último ecrã'},
      {id:'resumo',label:'Resumo claro do preço antes de confirmar'},
      {id:'registo',label:'Obrigação de criar conta para pagar'},
      {id:'pagamentos',label:'Métodos de pagamento familiares e visíveis'},
      {id:'campos',label:'Formulário com muitos campos desnecessários'},
      {id:'movel',label:'Botões legíveis e acessíveis no telemóvel'}
    ],
    correct:['portes','registo','campos'],
    explanation:'Custos inesperados, registo obrigatório e formulários longos criam fricção. Nem todo o abandono é técnico: é preciso cruzar os dados com o comportamento.'
  },
  {
    id:'quiz', slide:9, type:'quiz', label:'04 / Mito ou realidade?',title:'Quatro decisões rápidas',
    description:'Assinale a resposta mais adequada em cada situação.',duration:'3 min',
    questions:[
      {q:'Uma pessoa visita o mesmo produto, interrompe a pesquisa e regressa semanas depois. O que mostra?',opts:[['linear','A jornada tem sempre uma sequência fixa'],['nao_linear','A jornada pode ser interrompida e retomada'],['erro','A campanha falhou necessariamente']],correct:'nao_linear'},
      {q:'Um visitante passa muito tempo numa página de produto. Podemos concluir que está interessado?',opts:[['sim','Sim, o tempo prova interesse'],['permanencia_nao_prova','Não. Pode estar com dificuldade em encontrar informação'],['nao','Não. Tempo longo significa sempre rejeição']],correct:'permanencia_nao_prova'},
      {q:'Uma loja tem muitos abandonos durante o pagamento. O que deve investigar primeiro?',opts:[['anuncio','Aumentar a frequência dos anúncios'],['checkout','Custos inesperados, passos e erros no checkout'],['logo','Mudar apenas o logótipo']],correct:'checkout'},
      {q:'A encomenda já foi paga. Qual a prioridade seguinte?',opts:[['terminou','Encerrar a relação'],['promo','Enviar promoções diariamente'],['pos_compra','Informar sobre entrega e oferecer apoio útil']],correct:'pos_compra'}
    ],
    explanation:'As métricas precisam de contexto; o percurso não é linear; o checkout deve ser simples; e a experiência pós-compra influencia a retenção.'
  },
  {
    id:'raiz', slide:10, type:'scenario', label:'05 / Missão RAIZ',title:'Tome as decisões da marca',
    description:'É responsável pelo marketing da RAIZ, uma marca fictícia de mochilas sustentáveis para profissionais dos 25 aos 40 anos. Escolha a melhor ação em cada momento.',duration:'4 min',
    questions:[
      {q:'1. Uma pessoa sente desconforto ao transportar o portátil. Como deve entrar no radar?',opts:[['desconto','Mostrar logo um desconto de última hora'],['artigo','Publicar um vídeo útil sobre ergonomia e mobilidade'],['carrinho','Enviar diretamente para o pagamento']],correct:'artigo'},
      {q:'2. O consumidor está a comparar mochilas de marcas diferentes. O que o ajuda?',opts:[['ficha','Comparar capacidade, materiais, dimensões e avaliações'],['slogan','Repetir «somos os melhores»'],['urgencia','Esconder as características e criar urgência']],correct:'ficha'},
      {q:'3. Já prefere a RAIZ, mas receia não poder devolver. Como responder?',opts:[['likes','Aumentar o número de seguidores'],['garantia','Dar destaque às devoluções, garantia e prazos'],['desconto','Aplicar um desconto sem esclarecer condições']],correct:'garantia'},
      {q:'4. Após o pagamento, qual é a melhor continuação?',opts:[['silencio','Não comunicar até haver uma reclamação'],['spam','Enviar publicidade todos os dias'],['acompanhamento','Confirmar encomenda, acompanhar entrega e partilhar cuidados']],correct:'acompanhamento'}
    ],
    explanation:'Na RAIZ, cada ação responde a uma necessidade específica: informar, comparar, reduzir o risco e apoiar depois da compra. Não existe uma única campanha que resolva todas as etapas.'
  }
];
window.JORNADA_STAGES={descoberta:'Descoberta',consideracao:'Consideração',decisao:'Decisão',compra:'Compra',poscompra:'Pós-compra'};
window.JORNADA_score=(id,payload)=>{
  const game=window.JORNADA_GAMES.find(x=>x.id===id);if(!game)return 0;
  if(id==='ordem')return JSON.stringify(payload.order||[])===JSON.stringify(game.correct)?100:0;
  if(id==='associar')return Object.entries(game.correct).reduce((n,[k,v])=>n+(payload.pairs?.[k]===v?20:0),0);
  if(id==='erros'){
    const choices=[...new Set(payload.selected||[])], valid=new Set(game.options.map(o=>o.id));
    if(choices.some(x=>!valid.has(x)))return 0;
    const good=choices.filter(x=>game.correct.includes(x)).length;
    const bad=choices.length-good;
    return Math.max(0,Math.min(100,good*35-bad*20));
  }
  if(['quiz','raiz'].includes(id))return game.questions.reduce((n,q,i)=>n+(payload.answers?.[i]===q.correct? (id==='quiz'?25:25):0),0);
  return 0;
};

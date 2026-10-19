'use strict';
const B={c:new JornadaClient(),s:null,stat:null,signature:''},H=JornadaHelpers;
const overlay=document.getElementById('overlay'),frame=document.getElementById('slides');
function slide(){if(B.s)frame.contentWindow?.postMessage({type:'JORNADA_SET_SLIDE',slide:B.s.slide},'*')}
frame.addEventListener('load',slide);
async function init(){const id=H.parseQuery('s');if(!id){error('Falta o identificador da sessão. Abra este ecrã a partir do painel do apresentador.');return;}
 try{await B.c.init();if(B.c.live)await B.c.ensureAnonymous();B.s=await B.c.getById(id);await B.c.watch('broadcast');B.c.on(t=>{if(t==='data')refresh()});await refresh();setInterval(refresh,6500);}catch(e){error(e.message)}}
function error(message){overlay.classList.remove('hidden');overlay.innerHTML=`<div class="eyebrow">ERRO DE LIGAÇÃO</div><div class="tv-title">Transmissão não disponível</div><div class="tv-sub">${H.escape(message)}</div>`}
let busy=false;
async function refresh(){if(!B.s||busy)return;busy=true;try{B.s=await B.c.refresh();slide();await render()}catch(e){console.warn(e)}finally{busy=false}}
async function render(){const s=B.s,g=H.game(s.active_game);if(s.phase==='lobby'||!g){overlay.classList.add('hidden');return;}
 overlay.classList.remove('hidden');if(s.phase==='playing'){
 overlay.innerHTML=`<div class="eyebrow">${H.escape(g.label)} / PARTICIPAÇÃO ABERTA</div><div class="tv-title">${H.escape(g.title)}</div><div class="tv-sub">${H.escape(g.description)}</div><div class="tv-bottom"><span>RESPONDA NO TELEMÓVEL OU NA JANELA DO JOGO</span><span>CÓDIGO ${H.escape(s.code)} ↗</span></div>`;
 return;
 }
 let stats=null;try{stats=await B.c.stats(g.id)}catch(e){console.warn('Sem estatísticas:',e.message)}
 overlay.innerHTML=`<div class="eyebrow">${H.escape(g.label)} / RESULTADOS REVELADOS</div><div class="tv-title">${H.escape(g.title)}</div><div class="tv-sub">${stats?`${stats.answered} resposta${stats.answered===1?'':'s'} · ${stats.correct} pontuação${stats.correct===1?'':'ões'} máxima${stats.correct===1?'':'s'} · média de ${stats.avg}/100`:'Resultados disponíveis no painel do apresentador.'}</div><div class="tv-correct">${H.escape(g.explanation)}</div><div class="tv-ranking">${(stats?.participants||[]).slice(0,4).map((p,i)=>`<div>${i+1}. ${H.escape(p.name)} <span style="float:right">${p.score} pts</span></div>`).join('')}</div><div class="tv-bottom"><span>JORNADA DO CONSUMIDOR / RESULTADOS</span><span>CONTINUAMOS JÁ ↗</span></div>`;
}
init();

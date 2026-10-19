'use strict';
const P={c:new JornadaClient(),s:null,stats:null,busy:false,lastStatsAt:0};
const H=JornadaHelpers;
const $=id=>document.getElementById(id);
const err=(id,e)=>H.showError($(id),e);
function mode(){const l=P.c.live;$('connectionTag').textContent=l?'Online / Supabase':'Demonstração local';$('connectionTag').classList.toggle('demo',!l);$('footerMode').textContent=l?'Ligado ao Supabase':'Modo de demonstração';$('credentials').classList.toggle('hidden',!l);$('loginHelp').textContent=l?'Inicie sessão com as credenciais do apresentador para criar ou retomar um webinar.':'Crie uma sessão de demonstração para experimentar os cinco jogos e a sincronização entre separadores.';$('demoWarning').classList.toggle('hidden',l);}
async function authenticate(){if(!P.c.live)return;const u=await P.c.getAuthUser();if(u&&!u.is_anonymous)return;const email=$('email').value.trim(),password=$('password').value;if(!email||!password)throw Error('Preencha o e-mail e a palavra-passe do apresentador.');await P.c.login(email,password);}
async function init(){try{await P.c.init();mode();const sid=localStorage.getItem('jornada_last_session');if(sid)$('resumeSession').classList.remove('hidden');$('startSession').addEventListener('click',async()=>{try{$('startSession').disabled=true;await authenticate();P.s=await P.c.createSession();localStorage.setItem('jornada_last_session',P.s.id);await dashboard();}catch(e){err('loginError',e);$('startSession').disabled=false}});$('resumeSession').addEventListener('click',async()=>{try{await authenticate();P.s=await P.c.getById(sid);await dashboard();}catch(e){err('loginError',e)}});bind();}catch(e){err('loginError',e)}}
function bind(){
 $('prevSlide').onclick=()=>setSlide(-1);$('nextSlide').onclick=()=>setSlide(1);
 $('slidePreview').addEventListener('load',()=>preview());
 $('copyLink').onclick=async()=>{const url=joinUrl();try{await navigator.clipboard.writeText(url);$('copyLink').textContent='Link copiado ✓';setTimeout(()=>$('copyLink').textContent='Copiar link de entrada',1900)}catch{window.prompt('Copie o link:',url)}};
 $('openBroadcast').onclick=()=>window.open('transmitir.html?s='+encodeURIComponent(P.s.id),'_blank');
 $('qrOpen').onclick=()=>{const v=$('qrBox').classList.toggle('hidden');if(!v)$('qrImg').src='https://api.qrserver.com/v1/create-qr-code/?size=180x180&data='+encodeURIComponent(joinUrl());};
 window.addEventListener('keydown',e=>{if(!P.s||['INPUT','TEXTAREA','SELECT'].includes(document.activeElement.tagName))return;if(e.key==='ArrowRight'||e.key==='PageDown'){e.preventDefault();setSlide(1)}if(e.key==='ArrowLeft'||e.key==='PageUp'){e.preventDefault();setSlide(-1)}});
}
function joinUrl(){const u=new URL('participar.html',location.href);u.searchParams.set('codigo',P.s.code);return u.href;}
async function dashboard(){if(!P.s)return;$('loginPane').classList.add('hidden');$('dashboard').classList.remove('hidden');$('code').textContent=P.s.code;$('joinUrl').textContent=joinUrl();$('online').textContent='0';await P.c.watch('presenter');P.c.on(type=>{if(type==='data'){refresh();scheduleStats()}if(type==='presence')renderPresence()});await refresh();await reloadStats();setInterval(()=>{if(P.s){renderPresence();reloadStats()}},5000);}
let refreshBusy=false;
async function refresh(){if(refreshBusy)return;refreshBusy=true;try{P.s=await P.c.refresh();$('code').textContent=P.s.code;renderGames();renderControl();preview();}catch(e){console.error(e)}finally{refreshBusy=false}}
function preview(){if(!P.s)return;$('slideCount').textContent=String(P.s.slide).padStart(2,'0')+' / 10';$('slidePreview').contentWindow?.postMessage({type:'JORNADA_SET_SLIDE',slide:P.s.slide},'*');}
async function setSlide(delta){if(!P.s)return;const slide=Math.max(0,Math.min(10,P.s.slide+delta));if(slide===P.s.slide)return;try{P.s=await P.c.update({slide});preview();renderGames()}catch(e){alert(e.message)}}
function renderGames(){const active=P.s?.active_game,phase=P.s?.phase;$('gamesList').innerHTML=JORNADA_GAMES.map(g=>{
 const isOn=g.id===active;const isBusy=phase!=='lobby';
 return `<div class="item ${isOn?'active':''}"><div class="item-head"><div><b>${H.escape(g.label)} — ${H.escape(g.title)}</b><p>Slide ${String(g.slide).padStart(2,'0')} · ${H.escape(g.duration)}</p></div><button class="btn mini ${isOn?'soft':'dark'}" data-game="${g.id}" ${isBusy?'disabled':''}>${isOn?'Em curso':'Lançar ↗'}</button></div></div>`;
 }).join('');$('gamesList').querySelectorAll('[data-game]').forEach(b=>b.addEventListener('click',()=>startGame(b.dataset.game)));
}
function renderControl(){const g=H.game(P.s.active_game),phase=P.s.phase;if(!g){$('activeControl').innerHTML='Não existe nenhum jogo em curso. Selecione «Lançar» quando quiser.';return;}
 let html=`<b>${H.escape(g.title)}</b><p style="margin:9px 0">${H.escape(g.description)}</p>`;
 if(phase==='playing')html+=`<div class="actions"><button class="btn dark" id="reveal">Revelar respostas e ranking ↗</button></div><p class="hint" style="margin:10px 0 0">Os formandos podem responder até revelar as respostas.</p>`;
 if(phase==='results')html+=`<div class="success">Resultados apresentados na transmissão e aos participantes.</div><div class="actions" style="margin-top:10px"><button class="btn dark" id="finish">Fechar desafio e voltar aos slides →</button></div>`;
 $('activeControl').innerHTML=html;
 $('reveal')?.addEventListener('click',async()=>{try{P.s=await P.c.update({phase:'results'});await refresh();await reloadStats()}catch(e){alert(e.message)}});
 $('finish')?.addEventListener('click',async()=>{try{P.s=await P.c.update({phase:'lobby',active_game:null});await refresh();await reloadStats()}catch(e){alert(e.message)}});
}
async function startGame(id){if(!P.s||P.s.phase!=='lobby')return;const g=H.game(id);if(!g)return;try{P.s=await P.c.update({active_game:g.id,phase:'playing',slide:g.slide});preview();renderGames();renderControl();await reloadStats()}catch(e){alert(e.message)}}
function renderPresence(){if(!P.s)return;$('online').textContent=P.c.getOnline();renderPlayers();}
function renderPlayers(){const p=P.stats?.participants||[];if(!p.length){$('playersTable').innerHTML='<p class="muted">Ainda não há participantes.</p>';return;}$('playersTable').innerHTML=`<table class="players"><thead><tr><th>Nome</th><th>Pontos</th><th>Resposta</th></tr></thead><tbody>${p.map(x=>`<tr><td><b>${H.escape(x.name)}</b></td><td>${x.score}</td><td><span class="pill ${x.hasAnswered?'online':''}">${P.s.active_game?(x.hasAnswered?'Enviada':'Por enviar'):'—'}</span></td></tr>`).join('')}</tbody></table>`;}
let statsBusy=false,statsTimer=null;
function scheduleStats(){if(statsTimer)clearTimeout(statsTimer);statsTimer=setTimeout(reloadStats,250)}
async function reloadStats(){if(!P.s||statsBusy)return;statsBusy=true;try{P.stats=await P.c.stats(P.s.active_game||null);$('registered').textContent=P.stats.participants.length;$('answered').textContent=P.s.active_game?P.stats.answered:'0';renderPlayers();renderStats();}catch(e){console.warn('Estatísticas:',e.message)}finally{statsBusy=false}}
function renderStats(){const g=H.game(P.s.active_game);if(!g){$('resultTitle').textContent='A aguardar desafio';$('analysis').innerHTML='<p class="muted">Os resultados aparecem quando um jogo estiver ativo.</p>';return;}
 $('resultTitle').textContent=g.title;const s=P.stats;if(!s)return;
 $('analysis').innerHTML=`<div class="stats"><div class="stat"><b>${s.answered}</b><span>Respostas</span></div><div class="stat"><b>${s.correct}</b><span>100 pontos</span></div><div class="stat"><b>${s.avg}</b><span>Média do jogo</span></div></div><div class="divider"></div><div class="eyebrow">CLASSIFICAÇÃO GERAL</div>${s.participants.slice(0,6).map((p,i)=>`<div class="leader"><div class="rank"><span class="position">${i+1}.</span><b>${H.escape(p.name)}</b></div><b>${p.score} pts</b></div>`).join('')||'<p class="muted">Sem participantes.</p>'}<p class="hint" style="margin-top:13px">${P.s.phase==='playing'?'Os resultados são privados até carregar em «Revelar respostas».':H.escape(g.explanation)}</p>`;
}
init();

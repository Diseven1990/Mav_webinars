(function(){
'use strict';
const C=window.JORNADA_CONFIG||{};
const live=Boolean(C.supabaseUrl&&C.supabaseAnonKey);
const K='jornada_demo_v3';
const initials=()=>({session:null,participants:[],answers:[],presence:{}});
const clone=x=>JSON.parse(JSON.stringify(x));
const safeId=()=>crypto.randomUUID?crypto.randomUUID():`j-${Math.random().toString(36).slice(2)}-${Date.now()}`;
const makeCode=()=>{const alphabet='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';let s='';const arr=new Uint8Array(6);crypto.getRandomValues(arr);arr.forEach(n=>s+=alphabet[n%alphabet.length]);return s;};
function demoRead(){try{return Object.assign(initials(),JSON.parse(localStorage.getItem(K)||'{}'))}catch{return initials()}}
function demoWrite(st){localStorage.setItem(K,JSON.stringify(st));try{const ch=new BroadcastChannel('jornada-sync');ch.postMessage({type:'changed'});ch.close()}catch{}}
function demoStats(st,gameId){const aa=st.answers.filter(a=>a.game_key===gameId);return {
 participants:st.participants.map(p=>({id:p.id,name:p.name,score:st.answers.filter(a=>a.participant_id===p.id).reduce((s,a)=>s+a.points,0),hasAnswered:aa.some(a=>a.participant_id===p.id)})).sort((a,b)=>b.score-a.score||a.name.localeCompare(b.name,'pt')),
 answered:aa.length,correct:aa.filter(a=>a.points===100).length,
 avg:aa.length?Math.round(aa.reduce((n,a)=>n+a.points,0)/aa.length):0
};}
class JornadaClient {
 constructor(){this.live=live;this.sb=null;this.channel=null;this.bc=null;this.callbacks=[];this.sessionId=null;this.presenceCount=0;this.session=null;this.role=null;this.participantId=null;this.timer=null;this.tabId=safeId();this.name='';this.credsPresent=live;}
 async init(){if(this.live){const sdk=await import('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm');this.sb=sdk.createClient(C.supabaseUrl,C.supabaseAnonKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false}});} else {
  this.bc=new BroadcastChannel('jornada-sync');this.bc.onmessage=()=>this.notify('data');
  window.addEventListener('storage',(e)=>{if(e.key===K)this.notify('data')});
 }}
 on(fn){this.callbacks.push(fn);return()=>this.callbacks=this.callbacks.filter(x=>x!==fn)}
 notify(type){for(const fn of this.callbacks)try{fn(type)}catch(e){console.error(e)}}
 async login(email,password){if(!live)return {user:{id:'demo-host'}};const {data,error}=await this.sb.auth.signInWithPassword({email,password});if(error)throw error;return data;}
 async getAuthUser(){if(!live)return null;const{data}=await this.sb.auth.getUser();return data.user;}
 async ensureAnonymous(){if(!live)return;const user=await this.getAuthUser();if(user)return user;const{data,error}=await this.sb.auth.signInAnonymously();if(error)throw error;return data.user;}
 async createSession(){const code=makeCode();if(live){const user=await this.getAuthUser();if(!user)throw Error('Inicie sessão como apresentador.');const{data,error}=await this.sb.from('sessions').insert({code,title:'Jornada do Consumidor',host_id:user.id,slide:0,phase:'lobby'}).select().single();if(error)throw error;this.session=data;return data;}
 const st=initials();st.session={id:safeId(),code,title:'Jornada do Consumidor',slide:0,phase:'lobby',active_game:null,created_at:new Date().toISOString()};demoWrite(st);this.session=st.session;return st.session;}
 async getById(id){if(live){const{data,error}=await this.sb.from('sessions').select('*').eq('id',id).single();if(error)throw error;this.session=data;return data;}
 const st=demoRead();if(st.session?.id!==id)throw Error('Sessão não encontrada nesta demonstração.');this.session=st.session;return this.session;}
 async getByCode(code){code=(code||'').trim().toUpperCase();if(!/^[A-Z2-9]{6}$/.test(code))throw Error('Introduza um código válido de 6 caracteres.');if(live){await this.ensureAnonymous();const{data,error}=await this.sb.from('sessions').select('*').eq('code',code).single();if(error||!data)throw Error('Não foi encontrada uma sessão com este código.');this.session=data;return data;}
 const st=demoRead();if(st.session?.code!==code)throw Error('Não foi encontrada uma sessão com este código nesta demonstração local.');this.session=st.session;return this.session;}
 async getLatestDemo(){return demoRead().session;}
 async update(patch){if(!this.session)throw Error('Não existe uma sessão ativa.');if(live){const{data,error}=await this.sb.from('sessions').update(patch).eq('id',this.session.id).select().single();if(error)throw error;this.session=data;this.notify('data');return data;}
 const st=demoRead();if(!st.session)throw Error('Não existe uma sessão ativa.');Object.assign(st.session,patch);demoWrite(st);this.session=st.session;this.notify('data');return st.session;}
 async refresh(){if(!this.session)return null;return this.getById(this.session.id)}
 async join(code,name){name=(name||'').trim().replace(/\s+/g,' ').slice(0,32);if(name.length<2)throw Error('Introduza um nome com pelo menos dois caracteres.');const session=await this.getByCode(code);const lock='jornada-player-'+session.id;
 if(live){const user=await this.ensureAnonymous();const{data,error}=await this.sb.from('participants').upsert({session_id:session.id,user_id:user.id,name},{onConflict:'session_id,user_id'}).select().single();if(error)throw error;this.participantId=data.id;}
 else {const st=demoRead();let id=sessionStorage.getItem(lock);let p=st.participants.find(x=>x.id===id);if(!p){p={id:safeId(),session_id:session.id,name};st.participants.push(p);sessionStorage.setItem(lock,p.id)}else{p.name=name;}this.participantId=p.id;demoWrite(st);}
 this.name=name;return session;}
 async myScore(){if(!this.participantId)return 0;if(live){const{data,error}=await this.sb.from('answers').select('points').eq('participant_id',this.participantId);if(error)throw error;return (data||[]).reduce((n,a)=>n+a.points,0)}return demoRead().answers.filter(a=>a.participant_id===this.participantId).reduce((n,a)=>n+a.points,0);}
 async myAnswer(gameId){if(!this.participantId)return null;if(live){const{data,error}=await this.sb.from('answers').select('points,game_key').eq('participant_id',this.participantId).eq('game_key',gameId).maybeSingle();if(error)throw error;return data;}
 return demoRead().answers.find(a=>a.participant_id===this.participantId&&a.game_key===gameId)||null;}
 async submit(gameId,payload){if(!this.participantId)throw Error('Tem de entrar na sessão primeiro.');if(live){const {data,error}=await this.sb.rpc('submit_jornada_answer',{p_session_id:this.session.id,p_game_key:gameId,p_payload:payload});if(error)throw error;this.notify('data');return data;}
 const st=demoRead();if(st.session?.active_game!==gameId||st.session.phase!=='playing')throw Error('O desafio já não está aberto.');if(st.answers.some(a=>a.participant_id===this.participantId&&a.game_key===gameId))throw Error('Já respondeu a este desafio.');const points=window.JORNADA_score(gameId,payload);st.answers.push({id:safeId(),participant_id:this.participantId,session_id:this.session.id,game_key:gameId,payload,points,created_at:new Date().toISOString()});demoWrite(st);return {accepted:true};}
 async stats(gameId){if(live){const{data,error}=await this.sb.rpc('get_jornada_stats',{p_session_id:this.session.id,p_game_key:gameId||null});if(error)throw error;return data;}
 return demoStats(demoRead(),gameId);}
 getOnline(){if(live)return this.presenceCount;const st=demoRead();const now=Date.now();return Object.values(st.presence).filter(p=>p.role==='player'&&p.sessionId===this.session?.id&&now-p.at<18000).length;}
 async watch(role){if(!this.session)return;this.role=role;this.sessionId=this.session.id;const sid=this.session.id;if(live){
 if(this.channel)await this.sb.removeChannel(this.channel);
 const ch=this.sb.channel('jornada-'+sid,{config:{presence:{key:this.tabId}}});this.channel=ch;
 ch.on('postgres_changes',{event:'*',schema:'public',table:'sessions',filter:'id=eq.'+sid},()=>this.notify('data'));
 ch.on('postgres_changes',{event:'*',schema:'public',table:'participants',filter:'session_id=eq.'+sid},()=>this.notify('data'));
 ch.on('postgres_changes',{event:'*',schema:'public',table:'answers',filter:'session_id=eq.'+sid},()=>this.notify('data'));
 ch.on('presence',{event:'sync'},()=>{const pres=Object.values(ch.presenceState()).flat();this.presenceCount=new Set(pres.filter(p=>p.role==='player'&&p.participantId).map(p=>p.participantId)).size;this.notify('presence');});
 ch.subscribe(async(status)=>{if(status==='SUBSCRIBED'){await ch.track({role,participantId:this.participantId||null,name:this.name||null});this.notify('connected')}if(status==='CHANNEL_ERROR'||status==='TIMED_OUT')this.notify('offline');});
 }else{
 const write=()=>{const st=demoRead();st.presence[this.tabId]={role,sessionId:sid,at:Date.now()};Object.keys(st.presence).forEach(k=>{if(Date.now()-st.presence[k].at>22000)delete st.presence[k]});demoWrite(st)};
 write();this.timer=setInterval(write,8000);window.addEventListener('beforeunload',()=>{const st=demoRead();delete st.presence[this.tabId];demoWrite(st);});
 }
 }
 async leave(){if(this.timer)clearInterval(this.timer);if(live&&this.channel)await this.sb.removeChannel(this.channel);if(this.bc)this.bc.close();}
}
window.JornadaClient=JornadaClient;
window.JornadaHelpers={
 escape(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));},
 parseQuery(k){return new URLSearchParams(location.search).get(k)||'';},
 showError(el,e){el.textContent=typeof e==='string'?e:(e?.message||'Ocorreu um erro.');el.classList.remove('hidden');},
 setText(id,value){const e=document.getElementById(id);if(e)e.textContent=value;},
 game(id){return window.JORNADA_GAMES.find(x=>x.id===id)},
 points(n){return `${n||0} pts`},
 baseUrl(path){return new URL(path,location.href).href}
};
})();

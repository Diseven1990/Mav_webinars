-- CONCORRENCIA INTERATIVA | Configuração de base de dados (Supabase > SQL Editor)
-- 1. Ative Authentication > Providers > Anonymous Sign-Ins.
-- 2. Crie um utilizador do apresentador em Authentication > Users.
-- 3. Execute este ficheiro SQL; depois execute o INSERT indicado no fim com o UUID desse utilizador.
-- É seguro expor apenas a chave anon/publishable no config.js. Nunca a service_role.

create table if not exists public.concorrencia_hosts (
 user_id uuid primary key references auth.users(id) on delete cascade
);
create table if not exists public.concorrencia_sessions (
 id uuid primary key default gen_random_uuid(),
 code text not null unique check (code ~ '^[A-Z2-9]{6}$'),
 title text not null default 'Análise da concorrência',
 host_id uuid not null references auth.users(id),
 slide int not null default 0 check (slide between 0 and 19),
 phase text not null default 'lobby' check (phase in ('lobby','playing','results')),
 active_game text check (active_game is null or active_game in ('alternativas','preco','percurso','evidencia','mentoria','metodo')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.concorrencia_participants (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.concorrencia_sessions(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 name text not null check(char_length(trim(name)) between 2 and 32),
 joined_at timestamptz not null default now(),
 unique(session_id,user_id)
);
create table if not exists public.concorrencia_answers (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.concorrencia_sessions(id) on delete cascade,
 participant_id uuid not null references public.concorrencia_participants(id) on delete cascade,
 game_key text not null check(game_key in ('alternativas','preco','percurso','evidencia','mentoria','metodo')),
 payload jsonb not null,
 points int not null check(points between 0 and 100),
 created_at timestamptz not null default now(),
 unique(participant_id,game_key)
);
create index if not exists concorrencia_answers_session_game on public.concorrencia_answers(session_id,game_key);
create index if not exists concorrencia_participants_session on public.concorrencia_participants(session_id);

create or replace function public.concorrencia_is_host(p_session_id uuid)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from public.concorrencia_sessions s join public.concorrencia_hosts h on h.user_id=s.host_id where s.id=p_session_id and s.host_id=auth.uid());
$$;

alter table public.concorrencia_hosts enable row level security;
alter table public.concorrencia_sessions enable row level security;
alter table public.concorrencia_participants enable row level security;
alter table public.concorrencia_answers enable row level security;

-- O código de 6 caracteres é partilhado apenas com os participantes. As sessões
-- podem ser lidas sem expor os nomes ou respostas dos restantes utilizadores.
drop policy if exists concorrencia_hosts_self on public.concorrencia_hosts;
create policy concorrencia_hosts_self on public.concorrencia_hosts for select to authenticated using(user_id=auth.uid());
drop policy if exists concorrencia_session_read on public.concorrencia_sessions;
create policy concorrencia_session_read on public.concorrencia_sessions for select to authenticated using(true);
drop policy if exists concorrencia_session_create on public.concorrencia_sessions;
create policy concorrencia_session_create on public.concorrencia_sessions for insert to authenticated
 with check(host_id=auth.uid() and exists(select 1 from public.concorrencia_hosts h where h.user_id=auth.uid()));
drop policy if exists concorrencia_session_update on public.concorrencia_sessions;
create policy concorrencia_session_update on public.concorrencia_sessions for update to authenticated
 using(public.concorrencia_is_host(id)) with check(public.concorrencia_is_host(id));
drop policy if exists concorrencia_participant_read on public.concorrencia_participants;
create policy concorrencia_participant_read on public.concorrencia_participants for select to authenticated
 using(user_id=auth.uid() or public.concorrencia_is_host(session_id));
drop policy if exists concorrencia_participant_join on public.concorrencia_participants;
create policy concorrencia_participant_join on public.concorrencia_participants for insert to authenticated
 with check(user_id=auth.uid());
drop policy if exists concorrencia_participant_name on public.concorrencia_participants;
create policy concorrencia_participant_name on public.concorrencia_participants for update to authenticated
 using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists concorrencia_answers_read on public.concorrencia_answers;
create policy concorrencia_answers_read on public.concorrencia_answers for select to authenticated
 using(public.concorrencia_is_host(session_id) or participant_id in(select id from public.concorrencia_participants where user_id=auth.uid()));

-- A correção ocorre na base de dados, não no JavaScript do formando.
-- A inserção direta em answers não tem política permissiva.
create or replace function public.submit_concorrencia_answer(p_session_id uuid,p_game_key text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
 st public.concorrencia_sessions%rowtype;
 p_id uuid;
 grade int:=0;
 hits int:=0;
 total int;
 k text;
 val text;
 g jsonb;
 selected text[];
 defs jsonb:='{"alternativas": {"id": "alternativas", "slide": 4, "type": "match", "label": "01 / Após o slide 4", "title": "Escolher quem comparar", "description": "Uma escola dá aulas de inglês em grupo a adultos. Associar cada alternativa ao papel que tem nesta análise.", "explanation": "A outra escola disputa a mesma inscrição. A aplicação responde à necessidade de aprender inglês de outra forma. A clínica serve de referência apenas para a experiência de marcação.", "duration": "1–2 min", "items": [{"id": "app", "label": "Uma aplicação de estudo autónomo para adultos que querem aprender inglês."}, {"id": "clinica", "label": "Uma clínica que a escola usa como exemplo de marcação simples pela internet."}, {"id": "escola", "label": "Outra escola que dá aulas de inglês em grupo aos mesmos adultos."}], "stages": ["d", "i", "r"], "correct": {"app": "i", "clinica": "r", "escola": "d"}}, "preco": {"id": "preco", "slide": 8, "type": "quiz", "label": "02 / Após o slide 8", "title": "Comparar o custo de um ano", "description": "Dois serviços oferecem o mesmo apoio durante 12 meses. O plano A custa 20 € por mês, mais 60 € de adesão. O plano B custa 24 € por mês, sem adesão. Estes são os preços finais.", "explanation": "O plano A custa 300 € (12 × 20 € + 60 €). O plano B custa 288 € (12 × 24 €). A mensalidade mais baixa acaba por custar mais 12 € no primeiro ano.", "duration": "1–2 min", "questions": [{"q": "Qual é o plano mais barato no primeiro ano e por quanto?", "opts": [["0", "O A, por 48 €."], ["1", "O B, por 12 €."], ["2", "O B, por 60 €."]], "correct": "1"}]}, "percurso": {"id": "percurso", "slide": 12, "type": "spot", "label": "03 / Após o slide 12", "title": "Encontrar os obstáculos à inscrição", "description": "Um anúncio promete uma aula experimental gratuita. Selecionar os três pormenores que tornam a inscrição mais difícil ou deixam dúvidas sobre a oferta.", "explanation": "Uma página sem referência à aula interrompe o percurso iniciado no anúncio. Pedir dados de faturação sem explicar porquê cria dúvidas. Revelar uma taxa no último passo põe em causa a promessa de gratuitidade.", "duration": "1–2 min", "options": [{"id": "pagina", "label": "O anúncio abre uma página genérica que não menciona a aula."}, {"id": "horario", "label": "O calendário mostra as vagas antes de pedir dados pessoais."}, {"id": "dados", "label": "O formulário exige dados de faturação sem explicar para quê."}, {"id": "taxa", "label": "Só no último passo aparece uma taxa de reserva obrigatória."}, {"id": "email", "label": "A confirmação inclui a data, a hora e a ligação para a aula."}], "correct": ["pagina", "dados", "taxa"]}, "evidencia": {"id": "evidencia", "slide": 14, "type": "match", "label": "04 / Após o slide 14", "title": "Distinguir o que se sabe do que falta testar", "description": "Uma escola está a analisar a página de apoio de outra marca. Classificar cada frase.", "explanation": "O prazo publicado pode ser confirmado na página. A intenção atribuída à marca é uma interpretação. O possível efeito de publicar um prazo na nossa página é uma hipótese que podemos testar.", "duration": "1–2 min", "items": [{"id": "efeito", "label": "Publicar o nosso prazo poderá aumentar os pedidos de contacto."}, {"id": "prazo", "label": "Na página lê-se «Respondemos em dois dias úteis»."}, {"id": "intencao", "label": "A marca parece querer tranquilizar quem receia ficar sem resposta."}], "stages": ["o", "l", "h"], "correct": {"efeito": "h", "prazo": "o", "intencao": "l"}}, "mentoria": {"id": "mentoria", "slide": 17, "type": "scenario", "label": "05 / Após o slide 17", "title": "Decidir o que testar na página do curso", "description": "No caso apresentado, a nossa marca oferece mentoria individual. A página explica pouco sobre o acompanhamento. O objetivo é ajudar potenciais formandos a perceber se o curso lhes serve.", "explanation": "Explicar a mentoria torna visível um serviço que a escola já presta. Comparar a proporção de visitantes que fazem pedidos adequados ao curso aproxima a avaliação do objetivo. Convém registar outras alterações que possam ter influenciado o resultado.", "duration": "1–2 min", "questions": [{"q": "Qual seria a primeira alteração a testar?", "opts": [["0", "Substituir a mentoria individual por sessões de grupo, como faz a marca B."], ["1", "Baixar o preço para compensar as dúvidas sobre a mentoria."], ["2", "Indicar quantas sessões estão incluídas e dar um exemplo do que se trabalha numa sessão."]], "correct": "2"}, {"q": "Que indicador ajudaria a avaliar essa alteração em períodos comparáveis?", "opts": [["0", "A percentagem de visitantes da página que enviam um pedido de informação adequado ao curso."], ["1", "O total de seguidores da escola no fim do mês."], ["2", "O número de sessões de mentoria realizadas com antigos alunos."]], "correct": "0"}]}, "metodo": {"id": "metodo", "slide": 19, "type": "order", "label": "06 / Após o slide 19", "title": "Reconstruir o método", "description": "Uma equipa vai rever a página de um curso. Ordenar os cinco passos da análise que vai apoiar essa decisão.", "explanation": "A decisão e o público orientam a escolha das alternativas. Critérios comuns permitem comparar as evidências. Dessa comparação nasce uma alteração concreta que a equipa pode testar e rever.", "duration": "1–2 min", "items": {"decisao": "Definir a decisão a tomar e o público a considerar.", "alternativas": "Identificar as alternativas que esse público considera.", "observar": "Recolher informação sobre cada alternativa com os mesmos critérios.", "comparar": "Comparar o que as fontes mostram e registar as dúvidas.", "testar": "Escolher uma alteração, testá-la e rever os resultados."}, "initial": ["observar", "testar", "alternativas", "comparar", "decisao"], "correct": ["decisao", "alternativas", "observar", "comparar", "testar"]}}'::jsonb;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
 if p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Resposta inválida';end if;
 if octet_length(p_payload::text)>3000 then raise exception 'Resposta demasiado longa';end if;
 select * into st from public.concorrencia_sessions where id=p_session_id for update;
 if not found then raise exception 'Sessão inexistente';end if;
 if st.phase<>'playing' or st.active_game is distinct from p_game_key then raise exception 'Atividade encerrada';end if;
 select id into p_id from public.concorrencia_participants where session_id=p_session_id and user_id=auth.uid();
 if p_id is null then raise exception 'Participante não encontrado';end if;
 if exists(select 1 from public.concorrencia_answers where participant_id=p_id and game_key=p_game_key) then raise exception 'Já respondeu a esta atividade';end if;
 g:=defs->p_game_key;
 if g is null then raise exception 'Atividade inválida';end if;
 case g->>'type'
 when 'order' then
  if p_payload->'order'=g->'correct' then grade:=100;end if;
 when 'match' then
  select count(*) into total from jsonb_object_keys(g->'correct');
  for k,val in select key,value from jsonb_each_text(g->'correct') loop
   if p_payload->'pairs'->>k=val then hits:=hits+1;end if;
  end loop;
  grade:=round(100.0*hits/total);
 when 'spot' then
  if jsonb_typeof(p_payload->'selected') is distinct from 'array' then raise exception 'Resposta inválida';end if;
  select array_agg(distinct v) into selected from jsonb_array_elements_text(p_payload->'selected') t(v);
  total:=jsonb_array_length(g->'correct');
  if coalesce(cardinality(selected),0)=total and not exists(select 1 from unnest(selected) v where not exists(select 1 from jsonb_array_elements(g->'options') o where o->>'id'=v)) then
   select count(*) into hits from unnest(selected) v where (g->'correct') ? v;
   grade:=round(100.0*hits/total);
  end if;
 else
  total:=jsonb_array_length(g->'questions');
  for i in 0..total-1 loop
   if p_payload->'answers'->>i=g->'questions'->i->>'correct' then hits:=hits+1;end if;
  end loop;
  grade:=round(100.0*hits/total);
 end case;
 insert into public.concorrencia_answers(session_id,participant_id,game_key,payload,points) values(p_session_id,p_id,p_game_key,p_payload,grade);
 return jsonb_build_object('accepted',true);
end $$;

-- Estatísticas privadas para o apresentador; partilhadas com o público apenas
-- durante a fase de resultados, depois de o apresentador carregar em revelar.
create or replace function public.get_concorrencia_stats(p_session_id uuid,p_game_key text default null)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare
 current_phase text;
 host_ok boolean;
 result jsonb;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária';end if;
 select phase into current_phase from public.concorrencia_sessions where id=p_session_id;
 if not found then raise exception 'Sessão inexistente';end if;
 host_ok:=public.concorrencia_is_host(p_session_id);
 if not host_ok and current_phase<>'results' then raise exception 'Resultados ainda não revelados';end if;
 with ranked as (
  select p.id,p.name,
   coalesce((select sum(a.points) from public.concorrencia_answers a where a.participant_id=p.id),0)::int as score,
   exists(select 1 from public.concorrencia_answers a where a.participant_id=p.id and a.game_key=p_game_key) as has_answered
  from public.concorrencia_participants p where p.session_id=p_session_id
 ), agg as (
  select count(*)::int as answered,
         count(*) filter(where points=100)::int as correct,
         coalesce(round(avg(points)),0)::int as avg
  from public.concorrencia_answers where session_id=p_session_id and game_key=p_game_key
 )
 select jsonb_build_object(
  'participants',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'score',score,'hasAnswered',has_answered) order by score desc,name asc) from ranked),'[]'::jsonb),
  'answered',agg.answered,'correct',agg.correct,'avg',agg.avg
 ) into result from agg;
 return result;
end $$;

revoke all on function public.concorrencia_is_host(uuid) from public,anon;
revoke all on function public.submit_concorrencia_answer(uuid,text,jsonb) from public,anon;
revoke all on function public.get_concorrencia_stats(uuid,text) from public,anon;
grant execute on function public.concorrencia_is_host(uuid) to authenticated;
grant execute on function public.submit_concorrencia_answer(uuid,text,jsonb) to authenticated;
grant execute on function public.get_concorrencia_stats(uuid,text) to authenticated;
grant select on public.concorrencia_sessions,public.concorrencia_hosts,public.concorrencia_participants,public.concorrencia_answers to authenticated;
grant insert,update on public.concorrencia_sessions,public.concorrencia_participants to authenticated;
-- Postgres Changes, necessário para sincronizar slides e respostas em tempo real.
do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='concorrencia_sessions') then
  alter publication supabase_realtime add table public.concorrencia_sessions;
 end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='concorrencia_participants') then
  alter publication supabase_realtime add table public.concorrencia_participants;
 end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='concorrencia_answers') then
  alter publication supabase_realtime add table public.concorrencia_answers;
 end if;
end $$;

-- AÇÃO MANUAL APÓS EXECUTAR ESTE FICHEIRO:
-- substitua o UUID pelo ID do utilizador do apresentador em Authentication > Users
-- insert into public.concorrencia_hosts(user_id) values ('COLE_AQUI_O_UUID_DO_APRESENTADOR');

-- CAMADAS INTERATIVA | Configuração de base de dados (Supabase > SQL Editor)
-- 1. Ative Authentication > Providers > Anonymous Sign-Ins.
-- 2. Crie um utilizador do apresentador em Authentication > Users.
-- 3. Execute este ficheiro SQL; depois execute o INSERT indicado no fim com o UUID desse utilizador.
-- É seguro expor apenas a chave anon/publishable no config.js. Nunca a service_role.

create table if not exists public.camadas_hosts (
 user_id uuid primary key references auth.users(id) on delete cascade
);
create table if not exists public.camadas_sessions (
 id uuid primary key default gen_random_uuid(),
 code text not null unique check (code ~ '^[A-Z2-9]{6}$'),
 title text not null default 'Camadas no Photoshop',
 host_id uuid not null references auth.users(id),
 slide int not null default 0 check (slide between 0 and 8),
 phase text not null default 'lobby' check (phase in ('lobby','playing','results')),
 active_game text check (active_game is null or active_game in ('ordem','pedidos','diagnostico')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.camadas_participants (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.camadas_sessions(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 name text not null check(char_length(trim(name)) between 2 and 32),
 joined_at timestamptz not null default now(),
 unique(session_id,user_id)
);
create table if not exists public.camadas_answers (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.camadas_sessions(id) on delete cascade,
 participant_id uuid not null references public.camadas_participants(id) on delete cascade,
 game_key text not null check(game_key in ('ordem','pedidos','diagnostico')),
 payload jsonb not null,
 points int not null check(points between 0 and 100),
 created_at timestamptz not null default now(),
 unique(participant_id,game_key)
);
create index if not exists camadas_answers_session_game on public.camadas_answers(session_id,game_key);
create index if not exists camadas_participants_session on public.camadas_participants(session_id);

create or replace function public.camadas_is_host(p_session_id uuid)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from public.camadas_sessions s join public.camadas_hosts h on h.user_id=s.host_id where s.id=p_session_id and s.host_id=auth.uid());
$$;

alter table public.camadas_hosts enable row level security;
alter table public.camadas_sessions enable row level security;
alter table public.camadas_participants enable row level security;
alter table public.camadas_answers enable row level security;

-- O código de 6 caracteres é partilhado apenas com os participantes. As sessões
-- podem ser lidas sem expor os nomes ou respostas dos restantes utilizadores.
drop policy if exists camadas_hosts_self on public.camadas_hosts;
create policy camadas_hosts_self on public.camadas_hosts for select to authenticated using(user_id=auth.uid());
drop policy if exists camadas_session_read on public.camadas_sessions;
create policy camadas_session_read on public.camadas_sessions for select to authenticated using(true);
drop policy if exists camadas_session_create on public.camadas_sessions;
create policy camadas_session_create on public.camadas_sessions for insert to authenticated
 with check(host_id=auth.uid() and exists(select 1 from public.camadas_hosts h where h.user_id=auth.uid()));
drop policy if exists camadas_session_update on public.camadas_sessions;
create policy camadas_session_update on public.camadas_sessions for update to authenticated
 using(public.camadas_is_host(id)) with check(public.camadas_is_host(id));
drop policy if exists camadas_participant_read on public.camadas_participants;
create policy camadas_participant_read on public.camadas_participants for select to authenticated
 using(user_id=auth.uid() or public.camadas_is_host(session_id));
drop policy if exists camadas_participant_join on public.camadas_participants;
create policy camadas_participant_join on public.camadas_participants for insert to authenticated
 with check(user_id=auth.uid());
drop policy if exists camadas_participant_name on public.camadas_participants;
create policy camadas_participant_name on public.camadas_participants for update to authenticated
 using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists camadas_answers_read on public.camadas_answers;
create policy camadas_answers_read on public.camadas_answers for select to authenticated
 using(public.camadas_is_host(session_id) or participant_id in(select id from public.camadas_participants where user_id=auth.uid()));

-- A correção ocorre na base de dados, não no JavaScript do formando.
-- A inserção direta em answers não tem política permissiva.
create or replace function public.submit_camadas_answer(p_session_id uuid,p_game_key text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
 st public.camadas_sessions%rowtype;
 p_id uuid;
 grade int:=0;
 hits int:=0;
 total int;
 k text;
 val text;
 g jsonb;
 selected text[];
 defs jsonb:='{"ordem": {"id": "ordem", "slide": 4, "type": "quiz", "label": "Desafio 1", "title": "Prever o resultado", "description": "A fotografia ocupa toda a área do cartaz. O título está visível à sua frente.", "duration": "1 min", "questions": [{"q": "O que acontece se a fotografia opaca passar para cima do título no painel?", "opts": [["opacidade", "O título fica semitransparente."], ["coberto", "O título fica tapado pela fotografia."], ["raster", "As letras deixam de ser editáveis."]], "correct": "coberto"}], "explanation": "A fotografia cobre as letras na zona de sobreposição. O título continua editável e recupera a visibilidade se voltar para cima da fotografia."}, "pedidos": {"id": "pedidos", "slide": 6, "type": "match", "label": "Desafio 2", "title": "Escolher a camada certa", "description": "O cartaz recebeu três pedidos de alteração. Associar cada pedido à camada adequada.", "duration": "1 min", "items": [{"id": "nome", "label": "Corrigir o nome do concerto."}, {"id": "mover", "label": "Reposicionar a fotografia do público."}, {"id": "cor", "label": "Experimentar outra tonalidade sem alterar os píxeis originais."}], "stages": ["ajuste", "texto", "foto"], "correct": {"nome": "texto", "mover": "foto", "cor": "ajuste"}, "explanation": "O nome altera-se na camada de texto e a posição da fotografia na camada de imagem. Uma camada de ajuste de Matiz/Saturação permite experimentar outra tonalidade. Para afetar apenas a fotografia imediatamente abaixo, use uma máscara de corte."}, "diagnostico": {"id": "diagnostico", "slide": 8, "type": "quiz", "label": "Desafio 3", "title": "Descobrir porque desapareceu o título", "description": "O olho da camada de texto está ativo. A opacidade está a 100%. Há uma fotografia opaca acima do título.", "duration": "1 min", "questions": [{"q": "Qual é o primeiro teste para confirmar a causa?", "opts": [["criar", "Criar outra camada de texto."], ["pintar", "Pintar a branco na fotografia."], ["olho", "Ocultar a fotografia por instantes."]], "correct": "olho"}], "explanation": "Se as letras reaparecerem ao ocultar a fotografia, a sobreposição explica o desaparecimento. Volte a mostrar a fotografia e ajuste a ordem das camadas."}}'::jsonb;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
 if p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Resposta inválida';end if;
 if octet_length(p_payload::text)>3000 then raise exception 'Resposta demasiado longa';end if;
 select * into st from public.camadas_sessions where id=p_session_id for update;
 if not found then raise exception 'Sessão inexistente';end if;
 if st.phase<>'playing' or st.active_game is distinct from p_game_key then raise exception 'Atividade encerrada';end if;
 select id into p_id from public.camadas_participants where session_id=p_session_id and user_id=auth.uid();
 if p_id is null then raise exception 'Participante não encontrado';end if;
 if exists(select 1 from public.camadas_answers where participant_id=p_id and game_key=p_game_key) then raise exception 'Já respondeu a esta atividade';end if;
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
 insert into public.camadas_answers(session_id,participant_id,game_key,payload,points) values(p_session_id,p_id,p_game_key,p_payload,grade);
 return jsonb_build_object('accepted',true);
end $$;

-- Estatísticas privadas para o apresentador; partilhadas com o público apenas
-- durante a fase de resultados, depois de o apresentador carregar em revelar.
create or replace function public.get_camadas_stats(p_session_id uuid,p_game_key text default null)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare
 current_phase text;
 host_ok boolean;
 result jsonb;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária';end if;
 select phase into current_phase from public.camadas_sessions where id=p_session_id;
 if not found then raise exception 'Sessão inexistente';end if;
 host_ok:=public.camadas_is_host(p_session_id);
 if not host_ok and current_phase<>'results' then raise exception 'Resultados ainda não revelados';end if;
 with ranked as (
  select p.id,p.name,
   coalesce((select sum(a.points) from public.camadas_answers a where a.participant_id=p.id),0)::int as score,
   exists(select 1 from public.camadas_answers a where a.participant_id=p.id and a.game_key=p_game_key) as has_answered
  from public.camadas_participants p where p.session_id=p_session_id
 ), agg as (
  select count(*)::int as answered,
         count(*) filter(where points=100)::int as correct,
         coalesce(round(avg(points)),0)::int as avg
  from public.camadas_answers where session_id=p_session_id and game_key=p_game_key
 )
 select jsonb_build_object(
  'participants',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'score',score,'hasAnswered',has_answered) order by score desc,name asc) from ranked),'[]'::jsonb),
  'answered',agg.answered,'correct',agg.correct,'avg',agg.avg
 ) into result from agg;
 return result;
end $$;

revoke all on function public.camadas_is_host(uuid) from public,anon;
revoke all on function public.submit_camadas_answer(uuid,text,jsonb) from public,anon;
revoke all on function public.get_camadas_stats(uuid,text) from public,anon;
grant execute on function public.camadas_is_host(uuid) to authenticated;
grant execute on function public.submit_camadas_answer(uuid,text,jsonb) to authenticated;
grant execute on function public.get_camadas_stats(uuid,text) to authenticated;
grant select on public.camadas_sessions,public.camadas_hosts,public.camadas_participants,public.camadas_answers to authenticated;
grant insert,update on public.camadas_sessions,public.camadas_participants to authenticated;
-- Postgres Changes, necessário para sincronizar slides e respostas em tempo real.
do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='camadas_sessions') then
  alter publication supabase_realtime add table public.camadas_sessions;
 end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='camadas_participants') then
  alter publication supabase_realtime add table public.camadas_participants;
 end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='camadas_answers') then
  alter publication supabase_realtime add table public.camadas_answers;
 end if;
end $$;


insert into public.camadas_hosts(user_id) select user_id from public.concorrencia_hosts where (select count(*) from public.concorrencia_hosts)=1 on conflict do nothing;
select count(*) as apresentadores_ativos from public.camadas_hosts;

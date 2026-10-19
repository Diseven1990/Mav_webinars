-- JORNADA INTERATIVA | Configuração de base de dados (Supabase > SQL Editor)
-- 1. Ative Authentication > Providers > Anonymous Sign-Ins.
-- 2. Crie um utilizador do apresentador em Authentication > Users.
-- 3. Execute este ficheiro SQL; depois execute o INSERT indicado no fim com o UUID desse utilizador.
-- É seguro expor apenas a chave anon/publishable no config.js. Nunca a service_role.

create table if not exists public.jornada_hosts (
 user_id uuid primary key references auth.users(id) on delete cascade
);
create table if not exists public.sessions (
 id uuid primary key default gen_random_uuid(),
 code text not null unique check (code ~ '^[A-Z2-9]{6}$'),
 title text not null default 'Jornada do Consumidor',
 host_id uuid not null references auth.users(id),
 slide int not null default 0 check (slide between 0 and 10),
 phase text not null default 'lobby' check (phase in ('lobby','playing','results')),
 active_game text check (active_game is null or active_game in ('ordem','associar','erros','quiz','raiz')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.participants (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.sessions(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 name text not null check(char_length(trim(name)) between 2 and 32),
 joined_at timestamptz not null default now(),
 unique(session_id,user_id)
);
create table if not exists public.answers (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.sessions(id) on delete cascade,
 participant_id uuid not null references public.participants(id) on delete cascade,
 game_key text not null check(game_key in ('ordem','associar','erros','quiz','raiz')),
 payload jsonb not null,
 points int not null check(points between 0 and 100),
 created_at timestamptz not null default now(),
 unique(participant_id,game_key)
);
create index if not exists jornada_answers_session_game on public.answers(session_id,game_key);
create index if not exists jornada_participants_session on public.participants(session_id);

create or replace function public.jornada_is_host(p_session_id uuid)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from public.sessions s join public.jornada_hosts h on h.user_id=s.host_id where s.id=p_session_id and s.host_id=auth.uid());
$$;

alter table public.jornada_hosts enable row level security;
alter table public.sessions enable row level security;
alter table public.participants enable row level security;
alter table public.answers enable row level security;

-- O código de 6 caracteres é partilhado apenas com os participantes. As sessões
-- podem ser lidas sem expor os nomes ou respostas dos restantes utilizadores.
drop policy if exists jornada_hosts_self on public.jornada_hosts;
create policy jornada_hosts_self on public.jornada_hosts for select to authenticated using(user_id=auth.uid());
drop policy if exists jornada_session_read on public.sessions;
create policy jornada_session_read on public.sessions for select to authenticated using(true);
drop policy if exists jornada_session_create on public.sessions;
create policy jornada_session_create on public.sessions for insert to authenticated
 with check(host_id=auth.uid() and exists(select 1 from public.jornada_hosts h where h.user_id=auth.uid()));
drop policy if exists jornada_session_update on public.sessions;
create policy jornada_session_update on public.sessions for update to authenticated
 using(public.jornada_is_host(id)) with check(public.jornada_is_host(id));
drop policy if exists jornada_participant_read on public.participants;
create policy jornada_participant_read on public.participants for select to authenticated
 using(user_id=auth.uid() or public.jornada_is_host(session_id));
drop policy if exists jornada_participant_join on public.participants;
create policy jornada_participant_join on public.participants for insert to authenticated
 with check(user_id=auth.uid());
drop policy if exists jornada_participant_name on public.participants;
create policy jornada_participant_name on public.participants for update to authenticated
 using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists jornada_answers_read on public.answers;
create policy jornada_answers_read on public.answers for select to authenticated
 using(public.jornada_is_host(session_id) or participant_id in(select id from public.participants where user_id=auth.uid()));

-- A correção ocorre na base de dados, não no JavaScript do formando.
-- A inserção direta em answers não tem política permissiva.
create or replace function public.submit_jornada_answer(p_session_id uuid,p_game_key text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
 st public.sessions%rowtype;
 p_id uuid;
 grade int:=0;
 k text;
 val text;
 opts text[];
 nr_right int:=0;
 nr_wrong int:=0;
 pairs jsonb:='{"post_blog":"descoberta","comparador":"consideracao","politica":"decisao","checkout":"compra","seguimento":"poscompra"}'::jsonb;
 quiz_expected text[]:=array['nao_linear','permanencia_nao_prova','checkout','pos_compra'];
 raiz_expected text[]:=array['artigo','ficha','garantia','acompanhamento'];
 expected text[];
 i int;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
 if octet_length(coalesce(p_payload::text,''))>3000 then raise exception 'Resposta demasiado longa'; end if;
 select * into st from public.sessions where id=p_session_id for update;
 if not found then raise exception 'Sessão inexistente'; end if;
 if st.phase<>'playing' or st.active_game is distinct from p_game_key then raise exception 'Este jogo não está disponível'; end if;
 select id into p_id from public.participants where session_id=p_session_id and user_id=auth.uid();
 if p_id is null then raise exception 'Participante não encontrado'; end if;
 if exists(select 1 from public.answers where participant_id=p_id and game_key=p_game_key) then raise exception 'Já respondeu a este jogo'; end if;
 case p_game_key
 when 'ordem' then
  if p_payload->'order'='["descoberta","consideracao","decisao","compra","poscompra"]'::jsonb then grade:=100;end if;
 when 'associar' then
  for k,val in select key,value#>>'{}' from jsonb_each(pairs) loop
   if p_payload->'pairs'->>k=val then grade:=grade+20; end if;
  end loop;
 when 'erros' then
  if jsonb_typeof(p_payload->'selected')<>'array' then raise exception 'Formato inválido';end if;
  select coalesce(array_agg(distinct v),array[]::text[]) into opts
   from jsonb_array_elements_text(p_payload->'selected') as x(v);
  if array_length(opts,1)>6 then raise exception 'Resposta inválida';end if;
  select count(*) into nr_right from unnest(opts) x where x=any(array['portes','registo','campos']);
  select count(*) into nr_wrong from unnest(opts) x where x<>all(array['portes','registo','campos']);
  grade:=greatest(0,least(100,nr_right*35-nr_wrong*20));
 when 'quiz' then
  expected:=quiz_expected;
  for i in 0..3 loop
   if p_payload->'answers'->>i=expected[i+1] then grade:=grade+25; end if;
  end loop;
 when 'raiz' then
  expected:=raiz_expected;
  for i in 0..3 loop
   if p_payload->'answers'->>i=expected[i+1] then grade:=grade+25; end if;
  end loop;
 else raise exception 'Jogo inválido';
 end case;
 insert into public.answers(session_id,participant_id,game_key,payload,points)
 values(p_session_id,p_id,p_game_key,p_payload,grade);
 return jsonb_build_object('accepted',true);
end $$;

-- Estatísticas privadas para o apresentador; partilhadas com o público apenas
-- durante a fase de resultados, depois de o apresentador carregar em revelar.
create or replace function public.get_jornada_stats(p_session_id uuid,p_game_key text default null)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare
 current_phase text;
 host_ok boolean;
 result jsonb;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária';end if;
 select phase into current_phase from public.sessions where id=p_session_id;
 if not found then raise exception 'Sessão inexistente';end if;
 host_ok:=public.jornada_is_host(p_session_id);
 if not host_ok and current_phase<>'results' then raise exception 'Resultados ainda não revelados';end if;
 with ranked as (
  select p.id,p.name,
   coalesce((select sum(a.points) from public.answers a where a.participant_id=p.id),0)::int as score,
   exists(select 1 from public.answers a where a.participant_id=p.id and a.game_key=p_game_key) as has_answered
  from public.participants p where p.session_id=p_session_id
 ), agg as (
  select count(*)::int as answered,
         count(*) filter(where points=100)::int as correct,
         coalesce(round(avg(points)),0)::int as avg
  from public.answers where session_id=p_session_id and game_key=p_game_key
 )
 select jsonb_build_object(
  'participants',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'score',score,'hasAnswered',has_answered) order by score desc,name asc) from ranked),'[]'::jsonb),
  'answered',agg.answered,'correct',agg.correct,'avg',agg.avg
 ) into result from agg;
 return result;
end $$;

revoke all on function public.jornada_is_host(uuid) from public,anon;
revoke all on function public.submit_jornada_answer(uuid,text,jsonb) from public,anon;
revoke all on function public.get_jornada_stats(uuid,text) from public,anon;
grant execute on function public.jornada_is_host(uuid) to authenticated;
grant execute on function public.submit_jornada_answer(uuid,text,jsonb) to authenticated;
grant execute on function public.get_jornada_stats(uuid,text) to authenticated;
grant select on public.sessions,public.jornada_hosts,public.participants,public.answers to authenticated;
grant insert,update on public.sessions,public.participants to authenticated;
-- Postgres Changes, necessário para sincronizar slides e respostas em tempo real.
do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='sessions') then
  alter publication supabase_realtime add table public.sessions;
 end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='participants') then
  alter publication supabase_realtime add table public.participants;
 end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='answers') then
  alter publication supabase_realtime add table public.answers;
 end if;
end $$;

-- AÇÃO MANUAL APÓS EXECUTAR ESTE FICHEIRO:
-- substitua o UUID pelo ID do utilizador do apresentador em Authentication > Users
-- insert into public.jornada_hosts(user_id) values ('COLE_AQUI_O_UUID_DO_APRESENTADOR');

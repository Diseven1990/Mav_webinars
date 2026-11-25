-- MAV PULSE | MISSÃO NOVA / PROVA SOCIAL
-- Executar UMA VEZ no SQL Editor do mesmo projeto Supabase da Jornada do Consumidor.
-- Reutiliza: public.sessions, public.participants e public.jornada_hosts.
-- Não elimina nem altera dados existentes.

create table if not exists public.prova_social_answers (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions(id) on delete cascade,
  participant_id uuid not null references public.participants(id) on delete cascade,
  question_no integer not null check (question_no between 1 and 3),
  option_key text not null check (option_key in ('A','B','C')),
  points integer not null check (points in (0,100)),
  answered_at timestamptz not null default now(),
  unique (participant_id, question_no)
);
create index if not exists ps_answers_session_question on public.prova_social_answers(session_id,question_no);
alter table public.prova_social_answers enable row level security;

drop policy if exists ps_answers_self_read on public.prova_social_answers;
create policy ps_answers_self_read on public.prova_social_answers
for select to authenticated using (
  public.jornada_is_host(session_id)
  or exists (select 1 from public.participants p where p.id=participant_id and p.user_id=auth.uid())
);

revoke all on public.prova_social_answers from anon, authenticated, public;
grant select on public.prova_social_answers to authenticated;

create or replace function public.ps_submit(
 p_session_id uuid, p_question_no integer, p_option_key text
) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare
 s public.sessions%rowtype;
 p uuid;
 correct text;
 score integer;
begin
 if auth.uid() is null then raise exception 'É necessário entrar na sessão'; end if;
 if p_question_no not between 1 and 3 then raise exception 'Pergunta inválida'; end if;
 if p_option_key not in ('A','B','C') then raise exception 'Opção inválida'; end if;
 select * into s from public.sessions where id=p_session_id for update;
 if not found then raise exception 'Sessão inexistente'; end if;
 if s.title <> 'Prova social | Missão NOVA' then raise exception 'Esta sessão não pertence à Missão NOVA'; end if;
 if s.phase <> 'playing' or s.slide <> p_question_no then
   raise exception 'Esta pergunta já não está aberta';
 end if;
 select id into p from public.participants
 where session_id=p_session_id and user_id=auth.uid();
 if p is null then raise exception 'Participante não encontrado'; end if;
 if exists(select 1 from public.prova_social_answers
           where participant_id=p and question_no=p_question_no) then
   raise exception 'Já respondeu a esta pergunta';
 end if;
 correct := case p_question_no when 1 then 'B' when 2 then 'C' when 3 then 'A' end;
 score := case when p_option_key=correct then 100 else 0 end;
 insert into public.prova_social_answers
   (session_id,participant_id,question_no,option_key,points)
 values (p_session_id,p,p_question_no,p_option_key,score);
 return jsonb_build_object('accepted',true,'question',p_question_no);
end $$;

create or replace function public.ps_stats(p_session_id uuid)
returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare
 s public.sessions%rowtype;
 is_host boolean;
 output jsonb;
begin
 if auth.uid() is null then raise exception 'É necessário autenticação'; end if;
 select * into s from public.sessions where id=p_session_id;
 if not found then raise exception 'Sessão inexistente'; end if;
 if s.title <> 'Prova social | Missão NOVA' then raise exception 'Sessão inválida'; end if;
 is_host := public.jornada_is_host(p_session_id);
 if not is_host and s.phase <> 'results' then
   raise exception 'Resultados ainda não revelados';
 end if;
 with scores as (
  select p.id, p.name,
    coalesce(sum(a.points),0)::integer as points,
    count(a.id) filter (where a.question_no=s.slide)::integer as answered_now,
    max(a.option_key) filter (where a.question_no=s.slide) as selected_now
  from public.participants p
  left join public.prova_social_answers a on a.participant_id=p.id
  where p.session_id=p_session_id
  group by p.id,p.name
 ),
 tally as (
  select count(*)::integer as answers,
    count(*) filter (where option_key='A')::integer as a,
    count(*) filter (where option_key='B')::integer as b,
    count(*) filter (where option_key='C')::integer as c
  from public.prova_social_answers
  where session_id=p_session_id and question_no=s.slide
 )
 select jsonb_build_object(
  'players', coalesce((
     select jsonb_agg(jsonb_build_object(
       'id',id,'name',name,'points',points,
       'answered_now',(answered_now>0),'selected_now',selected_now
     ) order by points desc,name asc) from scores
  ),'[]'::jsonb),
  'answers',tally.answers,
  'counts',jsonb_build_object('A',tally.a,'B',tally.b,'C',tally.c),
  'question',s.slide,
  'phase',s.phase
 ) into output from tally;
 return output;
end $$;

revoke all on function public.ps_submit(uuid,integer,text) from public,anon;
revoke all on function public.ps_stats(uuid) from public,anon;
grant execute on function public.ps_submit(uuid,integer,text) to authenticated;
grant execute on function public.ps_stats(uuid) to authenticated;

-- Realtime já está ativo em public.sessions e public.participants,
-- graças à instalação original da Jornada do Consumidor.
-- As respostas são atualizadas por pedidos de estatísticas periódicos;
-- não é necessária uma subscrição pública à tabela de respostas.

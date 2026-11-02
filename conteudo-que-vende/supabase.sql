-- CONTEUDO INTERATIVA | Configuração de base de dados (Supabase > SQL Editor)
-- 1. Ative Authentication > Providers > Anonymous Sign-Ins.
-- 2. Crie um utilizador do apresentador em Authentication > Users.
-- 3. Execute este ficheiro SQL; depois execute o INSERT indicado no fim com o UUID desse utilizador.
-- É seguro expor apenas a chave anon/publishable no config.js. Nunca a service_role.

create table if not exists public.conteudo_hosts (
 user_id uuid primary key references auth.users(id) on delete cascade
);
create table if not exists public.conteudo_sessions (
 id uuid primary key default gen_random_uuid(),
 code text not null unique check (code ~ '^[A-Z2-9]{6}$'),
 title text not null default 'Conteúdo que vende',
 host_id uuid not null references auth.users(id),
 slide int not null default 0 check (slide between 0 and 11),
 phase text not null default 'lobby' check (phase in ('lobby','playing','results')),
 active_game text check (active_game is null or active_game in ('utilidade','necessidade','beneficios','estrutura','abertura','provas','convite','medicao')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.conteudo_participants (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.conteudo_sessions(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 name text not null check(char_length(trim(name)) between 2 and 32),
 joined_at timestamptz not null default now(),
 unique(session_id,user_id)
);
create table if not exists public.conteudo_answers (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.conteudo_sessions(id) on delete cascade,
 participant_id uuid not null references public.conteudo_participants(id) on delete cascade,
 game_key text not null check(game_key in ('utilidade','necessidade','beneficios','estrutura','abertura','provas','convite','medicao')),
 payload jsonb not null,
 points int not null check(points between 0 and 110),
 created_at timestamptz not null default now(),
 unique(participant_id,game_key)
);
create index if not exists conteudo_answers_session_game on public.conteudo_answers(session_id,game_key);
create index if not exists conteudo_participants_session on public.conteudo_participants(session_id);

create or replace function public.conteudo_is_host(p_session_id uuid)
returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select exists(select 1 from public.conteudo_sessions s join public.conteudo_hosts h on h.user_id=s.host_id where s.id=p_session_id and s.host_id=auth.uid());
$$;

alter table public.conteudo_hosts enable row level security;
alter table public.conteudo_sessions enable row level security;
alter table public.conteudo_participants enable row level security;
alter table public.conteudo_answers enable row level security;

-- O código de 6 caracteres é partilhado apenas com os participantes. As sessões
-- podem ser lidas sem expor os nomes ou respostas dos restantes utilizadores.
drop policy if exists conteudo_hosts_self on public.conteudo_hosts;
create policy conteudo_hosts_self on public.conteudo_hosts for select to authenticated using(user_id=auth.uid());
drop policy if exists conteudo_session_read on public.conteudo_sessions;
create policy conteudo_session_read on public.conteudo_sessions for select to authenticated using(true);
drop policy if exists conteudo_session_create on public.conteudo_sessions;
create policy conteudo_session_create on public.conteudo_sessions for insert to authenticated
 with check(host_id=auth.uid() and exists(select 1 from public.conteudo_hosts h where h.user_id=auth.uid()));
drop policy if exists conteudo_session_update on public.conteudo_sessions;
create policy conteudo_session_update on public.conteudo_sessions for update to authenticated
 using(public.conteudo_is_host(id)) with check(public.conteudo_is_host(id));
drop policy if exists conteudo_participant_read on public.conteudo_participants;
create policy conteudo_participant_read on public.conteudo_participants for select to authenticated
 using(user_id=auth.uid() or public.conteudo_is_host(session_id));
drop policy if exists conteudo_participant_join on public.conteudo_participants;
create policy conteudo_participant_join on public.conteudo_participants for insert to authenticated
 with check(user_id=auth.uid());
drop policy if exists conteudo_participant_name on public.conteudo_participants;
create policy conteudo_participant_name on public.conteudo_participants for update to authenticated
 using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists conteudo_answers_read on public.conteudo_answers;
create policy conteudo_answers_read on public.conteudo_answers for select to authenticated
 using(public.conteudo_is_host(session_id) or participant_id in(select id from public.conteudo_participants where user_id=auth.uid()));

-- A correção ocorre na base de dados, não no JavaScript do formando.
-- A inserção direta em answers não tem política permissiva.
create or replace function public.submit_conteudo_answer(p_session_id uuid,p_game_key text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
 st public.conteudo_sessions%rowtype;
 p_id uuid;
 grade int:=0;
 hits int:=0;
 total int;
 k text;
 val text;
 g jsonb;
 selected text[];
 defs jsonb:='{"utilidade": {"id": "utilidade", "slide": 3, "type": "quiz", "label": "01 / Utilidade", "title": "Reconhecer um conteúdo útil", "description": "Depois de explicar a utilidade do conteúdo, escolher a opção mais adequada em cada situação.", "duration": "1–2 min", "questions": [{"q": "Uma marca quer ajudar quem ainda não sabe que café comprar. Que publicação oferece uma ajuda concreta?", "opts": [["elogio", "“O nosso café é extraordinário.”"], ["guia", "Um guia para escolher a moagem em função da cafeteira."], ["pressao", "“Comprar já, antes que seja tarde!”"]], "correct": "guia"}, {"q": "Um conteúdo útil pode ter uma intenção comercial?", "opts": [["ocultar", "Sim, desde que esconda a marca."], ["claro", "Sim. Pode ajudar o cliente e identificar claramente a marca."], ["nunca", "Não. Qualquer referência ao produto elimina a utilidade."]], "correct": "claro"}], "explanation": "Um guia responde a uma dúvida concreta. A utilidade é compatível com a intenção comercial, desde que a marca e as parcerias sejam claras."}, "necessidade": {"id": "necessidade", "slide": 4, "type": "quiz", "label": "02 / Necessidade do cliente", "title": "Identificar a dúvida do cliente", "description": "Com base na situação apresentada no slide, distinguir o desejo do cliente e o obstáculo à compra.", "duration": "1 min", "questions": [{"q": "“Quero fazer um café melhor em casa, mas não sei que moagem escolher.” Qual é o obstáculo?", "opts": [["preco", "O preço, embora não tenha sido referido."], ["duvida", "A dúvida sobre a moagem adequada."], ["marca", "A falta de seguidores da marca."]], "correct": "duvida"}, {"q": "Como confirmar se esta dúvida é frequente?", "opts": [["ouvir", "Analisar perguntas, comentários e conversas com clientes."], ["assumir", "Assumir que todos os clientes têm a mesma dúvida."], ["inventar", "Criar uma necessidade sem falar com os clientes."]], "correct": "ouvir"}], "explanation": "O desejo é preparar um café melhor. O obstáculo é não saber que moagem escolher. Para confirmar esta necessidade, procurar dúvidas recorrentes nas conversas com clientes."}, "beneficios": {"id": "beneficios", "slide": 5, "type": "match", "label": "03 / Características e benefícios", "title": "Ligar a característica ao benefício", "description": "Associar cada característica ao benefício correspondente, sem acrescentar promessas que o produto não garante.", "duration": "1–2 min", "items": [{"id": "moagem", "label": "Moagem à escolha"}, {"id": "torra", "label": "Data de torra na embalagem"}, {"id": "guia", "label": "Guia de preparação"}], "stages": ["orientacao", "data", "equipamento"], "correct": {"moagem": "equipamento", "torra": "data", "guia": "orientacao"}, "explanation": "Moagem à escolha: escolher a opção adequada à cafeteira. Data de torra: saber quando o café foi torrado. Guia: ter uma orientação para preparar o café."}, "estrutura": {"id": "estrutura", "slide": 6, "type": "order", "label": "04 / Estrutura da mensagem", "title": "Organizar a mensagem", "description": "Ordenar as quatro partes segundo a estrutura apresentada: situação, ajuda, prova e convite.", "duration": "1–2 min", "initial": ["convite", "prova", "situacao", "ajuda"], "items": {"situacao": "Situação: identificar a dúvida sobre a moagem.", "ajuda": "Ajuda: explicar como escolher a moagem.", "prova": "Prova: mostrar a preparação e as condições.", "convite": "Convite: consultar o guia para a cafeteira."}, "correct": ["situacao", "ajuda", "prova", "convite"], "explanation": "Situação → Ajuda → Prova → Convite. Esta sequência liga a dúvida do cliente a uma ajuda concreta, sustenta a promessa e indica o próximo passo. É um apoio à escrita, não uma regra para todas as publicações."}, "abertura": {"id": "abertura", "slide": 7, "type": "quiz", "label": "05 / Abertura da mensagem", "title": "Escolher como começar", "description": "Público: pessoas que querem preparar um café melhor em casa e ainda não conhecem a marca. Objetivo: despertar interesse através de uma ajuda concreta.", "duration": "1 min", "questions": [{"q": "Qual é a abertura mais adequada a este público e objetivo?", "opts": [["melhor", "“O melhor café do mercado. Comprar agora!”"], ["problema", "“O café fica amargo? Descobrir como ajustar a moagem.”"], ["desconto", "“20% de desconto em todo o café.”"]], "correct": "problema"}], "explanation": "A pergunta sobre o café amargo parte de um problema reconhecível e oferece uma ajuda concreta. O desconto pode fazer sentido para quem já está a pensar comprar. A escolha depende do público e do objetivo."}, "provas": {"id": "provas", "slide": 8, "type": "spot", "label": "06 / Provas", "title": "Escolher provas credíveis", "description": "Selecionar as TRÊS formas de sustentar uma promessa, de acordo com o que foi explicado no slide.", "duration": "1–2 min", "options": [{"id": "demonstracao", "label": "Mostrar o produto em uso e explicar as condições."}, {"id": "adjetivo", "label": "Repetir “excelente” em todas as publicações."}, {"id": "testemunho", "label": "Apresentar um testemunho real, autorizado e com contexto."}, {"id": "inventado", "label": "Inventar uma avaliação para tornar a oferta convincente."}, {"id": "limites", "label": "Apresentar resultados de uma demonstração, indicando os seus limites."}, {"id": "garantia", "label": "Garantir o mesmo resultado para todas as pessoas, sem o comprovar."}], "correct": ["demonstracao", "testemunho", "limites"], "explanation": "Uma demonstração com condições claras, um testemunho real e resultados acompanhados dos seus limites ajudam a avaliar a promessa. Adjetivos, avaliações inventadas e garantias sem prova não a sustentam."}, "convite": {"id": "convite", "slide": 9, "type": "match", "label": "07 / Próximo passo", "title": "Adequar o convite ao momento", "description": "Associar cada convite ao momento em que faz mais sentido, seguindo os exemplos do slide.", "duration": "1–2 min", "items": [{"id": "teste", "label": "Ver uma explicação mais completa do problema."}, {"id": "opcoes", "label": "Comparar opções e escolher a moagem adequada."}, {"id": "comprar", "label": "Consultar o preço e as condições para comprar."}], "stages": ["decisao", "descoberta", "consideracao"], "correct": {"teste": "descoberta", "opcoes": "consideracao", "comprar": "decisao"}, "explanation": "Na descoberta, aprofundar a informação. Na consideração, comparar e escolher. Na decisão, esclarecer as condições e comprar. São momentos de análise, não um percurso obrigatório."}, "medicao": {"id": "medicao", "slide": 10, "type": "scenario", "label": "08 / Medição", "title": "Escolher o que avaliar", "description": "Aplicar a ideia do slide: definir o que se pretende conseguir com cada conteúdo e escolher um resultado observável.", "duration": "1–2 min", "questions": [{"q": "O objetivo de uma publicação é levar pessoas à página do produto. Que resultado acompanhar primeiro?", "opts": [["seguidores", "O número total de seguidores."], ["visitas", "As visitas à página do produto provenientes da publicação."], ["tamanho", "O número de palavras da publicação."]], "correct": "visitas"}, {"q": "Para comparar duas formas de começar a mensagem, como preparar o teste?", "opts": [["tudo", "Mudar também o público, o produto e a oferta."], ["comparavel", "Manter as restantes condições semelhantes e definir o período e a métrica."], ["cedo", "Escolher uma vencedora depois do primeiro clique."]], "correct": "comparavel"}], "explanation": "A métrica deve corresponder ao objetivo: neste caso, visitas à página do produto. Para comparar aberturas, manter as restantes condições semelhantes e definir antecipadamente o período e a métrica. Evitar conclusões com poucos dados."}}'::jsonb;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
 if p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'Resposta inválida';end if;
 if octet_length(p_payload::text)>3000 then raise exception 'Resposta demasiado longa';end if;
 select * into st from public.conteudo_sessions where id=p_session_id for update;
 if not found then raise exception 'Sessão inexistente';end if;
 if st.phase<>'playing' or st.active_game is distinct from p_game_key then raise exception 'Atividade encerrada';end if;
 select id into p_id from public.conteudo_participants where session_id=p_session_id and user_id=auth.uid();
 if p_id is null then raise exception 'Participante não encontrado';end if;
 if exists(select 1 from public.conteudo_answers where participant_id=p_id and game_key=p_game_key) then raise exception 'Já respondeu a esta atividade';end if;
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
 insert into public.conteudo_answers(session_id,participant_id,game_key,payload,points) values(p_session_id,p_id,p_game_key,p_payload,grade);
 return jsonb_build_object('accepted',true);
end $$;

-- Estatísticas privadas para o apresentador; partilhadas com o público apenas
-- durante a fase de resultados, depois de o apresentador carregar em revelar.
create or replace function public.get_conteudo_stats(p_session_id uuid,p_game_key text default null)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare
 current_phase text;
 host_ok boolean;
 result jsonb;
begin
 if auth.uid() is null then raise exception 'Autenticação necessária';end if;
 select phase into current_phase from public.conteudo_sessions where id=p_session_id;
 if not found then raise exception 'Sessão inexistente';end if;
 host_ok:=public.conteudo_is_host(p_session_id);
 if not host_ok and current_phase<>'results' then raise exception 'Resultados ainda não revelados';end if;
 with ranked as (
  select p.id,p.name,
   coalesce((select sum(a.points) from public.conteudo_answers a where a.participant_id=p.id),0)::int as score,
   exists(select 1 from public.conteudo_answers a where a.participant_id=p.id and a.game_key=p_game_key) as has_answered
  from public.conteudo_participants p where p.session_id=p_session_id
 ), agg as (
  select count(*)::int as answered,
         count(*) filter(where points=100)::int as correct,
         coalesce(round(avg(points)),0)::int as avg
  from public.conteudo_answers where session_id=p_session_id and game_key=p_game_key
 )
 select jsonb_build_object(
  'participants',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'score',score,'hasAnswered',has_answered) order by score desc,name asc) from ranked),'[]'::jsonb),
  'answered',agg.answered,'correct',agg.correct,'avg',agg.avg
 ) into result from agg;
 return result;
end $$;

revoke all on function public.conteudo_is_host(uuid) from public,anon;
revoke all on function public.submit_conteudo_answer(uuid,text,jsonb) from public,anon;
revoke all on function public.get_conteudo_stats(uuid,text) from public,anon;
grant execute on function public.conteudo_is_host(uuid) to authenticated;
grant execute on function public.submit_conteudo_answer(uuid,text,jsonb) to authenticated;
grant execute on function public.get_conteudo_stats(uuid,text) to authenticated;
grant select on public.conteudo_sessions,public.conteudo_hosts,public.conteudo_participants,public.conteudo_answers to authenticated;
grant insert,update on public.conteudo_sessions,public.conteudo_participants to authenticated;
-- Postgres Changes, necessário para sincronizar slides e respostas em tempo real.
do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='conteudo_sessions') then
  alter publication supabase_realtime add table public.conteudo_sessions;
 end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='conteudo_participants') then
  alter publication supabase_realtime add table public.conteudo_participants;
 end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='conteudo_answers') then
  alter publication supabase_realtime add table public.conteudo_answers;
 end if;
end $$;

-- AÇÃO MANUAL APÓS EXECUTAR ESTE FICHEIRO:
-- substitua o UUID pelo ID do utilizador do apresentador em Authentication > Users
-- insert into public.conteudo_hosts(user_id) values ('COLE_AQUI_O_UUID_DO_APRESENTADOR');

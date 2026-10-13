-- =====================================================================
-- Fiscalização + — estrutura do banco (Supabase / Postgres)
-- Perfis: filial (abre chamado), juridico (atende), compliance (monitora e administra)
-- Rodar uma vez no SQL Editor do projeto "Gestao de Fiscalizacao".
-- =====================================================================

-- ---------- Cadastros ----------
create table if not exists public.filiais (
  codigo text primary key,
  nome   text,
  ativa  boolean not null default true
);

create table if not exists public.listas (
  id     bigint generated always as identity primary key,
  tipo   text not null check (tipo in ('orgao','nc','motivo')),
  valor  text not null,
  ordem  int  not null default 0,
  unique (tipo, valor)
);

-- ---------- Usuários (perfil de acesso) ----------
create table if not exists public.perfis (
  id        uuid primary key references auth.users(id) on delete cascade,
  email     text,
  nome      text,
  papel     text not null default 'pendente' check (papel in ('pendente','filial','juridico','compliance')),
  filial    text references public.filiais(codigo),
  criado_em timestamptz not null default now()
);

-- cria o perfil automaticamente quando um usuário é cadastrado no Auth
create or replace function public.novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- o PRIMEIRO usuário cadastrado vira Compliance (administrador); os demais entram como "pendente"
  insert into public.perfis (id, email, nome, papel)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'nome', split_part(new.email,'@',1)),
          case when exists (select 1 from public.perfis where papel = 'compliance') then 'pendente' else 'compliance' end)
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists ao_criar_usuario on auth.users;
create trigger ao_criar_usuario after insert on auth.users
  for each row execute function public.novo_usuario();

-- funções auxiliares para as regras de acesso
create or replace function public.meu_papel() returns text
language sql stable security definer set search_path = public as $$
  select papel from public.perfis where id = auth.uid()
$$;
create or replace function public.minha_filial() returns text
language sql stable security definer set search_path = public as $$
  select filial from public.perfis where id = auth.uid()
$$;

-- ---------- Chamados ----------
create sequence if not exists public.chamado_seq;

create table if not exists public.chamados (
  id              text primary key default ('FIS-' || lpad(nextval('public.chamado_seq')::text, 4, '0')),
  filial          text not null references public.filiais(codigo),
  unidade         text not null default 'Loja' check (unidade in ('Loja','Loja do Mall','CD','Obra')),
  lojista         text,
  obra            text,
  orgao           text not null,
  motivo          text not null,
  forma           text not null default 'Presencial',
  data            date not null default current_date,
  fiscal          text,
  recebeu         text,
  acompanhou      text,
  resultados      text[] not null default '{}',
  doc             text,
  prazo           date,                       -- prazo do órgão (crucial)
  ncs             text[] not null default '{}',
  no_ato          text,
  apreensao       text,
  relato          text,
  status          text not null default 'aberto' check (status in ('aberto','analise','aguard_filial','respondido','encerrado')),
  desfecho        text,
  multa_valor     numeric(12,2),
  multa_motivo    text,
  envios_juridico int not null default 0,     -- envios Jurídico -> Filial
  envios_filial   int not null default 0,     -- envios Filial -> Jurídico
  limite_envios   int not null default 2,     -- +2 a cada liberação do Compliance
  criado_por      uuid references auth.users(id) default auth.uid(),
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);

-- Histórico (linha do tempo)
create table if not exists public.eventos (
  id         bigint generated always as identity primary key,
  chamado_id text not null references public.chamados(id) on delete cascade,
  papel      text not null check (papel in ('filial','juridico','compliance')),
  autor      text not null,
  texto      text not null,
  usuario    uuid references auth.users(id) default auth.uid(),
  criado_em  timestamptz not null default now()
);

-- Retornos entre setores (cada envio tem prazo de retorno)
create table if not exists public.retornos (
  id         bigint generated always as identity primary key,
  chamado_id text not null references public.chamados(id) on delete cascade,
  de         text not null check (de in ('filial','juridico')),
  para       text not null check (para in ('filial','juridico')),
  enviado    date not null default current_date,
  prazo      date not null,
  respondido date,
  criado_em  timestamptz not null default now()
);

-- Pedidos de liberação de reenvio (limite de 2 envios por setor)
create table if not exists public.liberacoes (
  id           bigint generated always as identity primary key,
  chamado_id   text not null references public.chamados(id) on delete cascade,
  pedido_por   text not null check (pedido_por in ('filial','juridico')),
  motivo       text not null,
  pedido_em    date not null default current_date,
  status       text not null default 'pendente' check (status in ('pendente','liberada','negada')),
  obs          text,
  decidido_por uuid references auth.users(id),
  decidido_em  timestamptz
);

-- Multa contratual ao lojista do Mall (filial propõe, Jurídico confirma)
create table if not exists public.multas_lojista (
  chamado_id   text primary key references public.chamados(id) on delete cascade,
  valor        numeric(12,2) not null,
  motivo       text not null,
  status       text not null default 'pendente' check (status in ('pendente','confirmada','nao_aplicada')),
  valor_final  numeric(12,2),
  obs          text,
  atualizado_em timestamptz not null default now()
);

create index if not exists eventos_chamado_idx    on public.eventos(chamado_id);
create index if not exists retornos_chamado_idx   on public.retornos(chamado_id);
create index if not exists liberacoes_chamado_idx on public.liberacoes(chamado_id);

-- quem pode ver um chamado
create or replace function public.pode_ver(cid text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.chamados c
    where c.id = cid
      and ( public.meu_papel() in ('juridico','compliance')
            or (public.meu_papel() = 'filial' and c.filial = public.minha_filial()) )
  )
$$;

-- ---------- Segurança (RLS) ----------
alter table public.filiais        enable row level security;
alter table public.listas         enable row level security;
alter table public.perfis         enable row level security;
alter table public.chamados       enable row level security;
alter table public.eventos        enable row level security;
alter table public.retornos       enable row level security;
alter table public.liberacoes     enable row level security;
alter table public.multas_lojista enable row level security;

-- cadastros: todos logados leem; só Compliance altera
drop policy if exists filiais_ler on public.filiais;
create policy filiais_ler on public.filiais for select to authenticated using (true);
drop policy if exists filiais_admin on public.filiais;
create policy filiais_admin on public.filiais for all to authenticated
  using (public.meu_papel() = 'compliance') with check (public.meu_papel() = 'compliance');

drop policy if exists listas_ler on public.listas;
create policy listas_ler on public.listas for select to authenticated using (true);
drop policy if exists listas_admin on public.listas;
create policy listas_admin on public.listas for all to authenticated
  using (public.meu_papel() = 'compliance') with check (public.meu_papel() = 'compliance');

-- perfis: cada um vê o seu; Jurídico e Compliance veem todos; só Compliance altera
drop policy if exists perfis_ler on public.perfis;
create policy perfis_ler on public.perfis for select to authenticated
  using (id = auth.uid() or public.meu_papel() in ('juridico','compliance'));
drop policy if exists perfis_admin on public.perfis;
create policy perfis_admin on public.perfis for update to authenticated
  using (public.meu_papel() = 'compliance') with check (public.meu_papel() = 'compliance');

-- chamados: filial só os da própria filial; Jurídico e Compliance todos
drop policy if exists chamados_ler on public.chamados;
create policy chamados_ler on public.chamados for select to authenticated
  using ( public.meu_papel() in ('juridico','compliance')
          or (public.meu_papel() = 'filial' and filial = public.minha_filial()) );
drop policy if exists chamados_criar on public.chamados;
create policy chamados_criar on public.chamados for insert to authenticated
  with check ( public.meu_papel() = 'compliance'
               or (public.meu_papel() = 'filial' and filial = public.minha_filial()) );
drop policy if exists chamados_alterar on public.chamados;
create policy chamados_alterar on public.chamados for update to authenticated
  using ( public.meu_papel() in ('juridico','compliance')
          or (public.meu_papel() = 'filial' and filial = public.minha_filial()) )
  with check ( public.meu_papel() in ('juridico','compliance')
               or (public.meu_papel() = 'filial' and filial = public.minha_filial()) );

-- tabelas filhas: quem vê o chamado lê e registra
drop policy if exists eventos_ler on public.eventos;
create policy eventos_ler on public.eventos for select to authenticated using (public.pode_ver(chamado_id));
drop policy if exists eventos_criar on public.eventos;
create policy eventos_criar on public.eventos for insert to authenticated with check (public.pode_ver(chamado_id));

drop policy if exists retornos_ler on public.retornos;
create policy retornos_ler on public.retornos for select to authenticated using (public.pode_ver(chamado_id));
drop policy if exists retornos_gravar on public.retornos;
create policy retornos_gravar on public.retornos for insert to authenticated with check (public.pode_ver(chamado_id));
drop policy if exists retornos_alterar on public.retornos;
create policy retornos_alterar on public.retornos for update to authenticated
  using (public.pode_ver(chamado_id)) with check (public.pode_ver(chamado_id));

drop policy if exists liberacoes_ler on public.liberacoes;
create policy liberacoes_ler on public.liberacoes for select to authenticated using (public.pode_ver(chamado_id));
drop policy if exists liberacoes_pedir on public.liberacoes;
create policy liberacoes_pedir on public.liberacoes for insert to authenticated with check (public.pode_ver(chamado_id));
drop policy if exists liberacoes_decidir on public.liberacoes;
create policy liberacoes_decidir on public.liberacoes for update to authenticated
  using (public.meu_papel() = 'compliance') with check (public.meu_papel() = 'compliance');

drop policy if exists multas_ler on public.multas_lojista;
create policy multas_ler on public.multas_lojista for select to authenticated using (public.pode_ver(chamado_id));
drop policy if exists multas_propor on public.multas_lojista;
create policy multas_propor on public.multas_lojista for insert to authenticated with check (public.pode_ver(chamado_id));
drop policy if exists multas_decidir on public.multas_lojista;
create policy multas_decidir on public.multas_lojista for update to authenticated
  using (public.meu_papel() in ('juridico','compliance')) with check (public.meu_papel() in ('juridico','compliance'));

-- ---------- Tempo real ----------
do $$
declare t text;
begin
  foreach t in array array['chamados','eventos','retornos','liberacoes','multas_lojista','perfis','listas','filiais'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- ---------- Cadastro por filial e setor ----------
alter table public.perfis add column if not exists setor text not null default 'Administrativo';
alter table public.perfis add column if not exists ativo boolean not null default true;

-- ---------- Manter o projeto ativo (plano gratuito pausa após 7 dias sem uso) ----------
-- Chamado 2x por dia pelo GitHub Actions (.github/workflows/manter-ativo.yml)
create table if not exists public.sinais_atividade (
  id        bigint generated always as identity primary key,
  origem    text not null default 'desconhecida',
  criado_em timestamptz not null default now()
);
alter table public.sinais_atividade enable row level security;  -- ninguém lê/grava direto; só pela função abaixo
create or replace function public.manter_ativo(p_origem text default 'github-actions') returns text
language plpgsql security definer set search_path = public as $$
begin
  insert into public.sinais_atividade (origem) values (left(coalesce(p_origem,'desconhecida'), 40));
  delete from public.sinais_atividade where criado_em < now() - interval '30 days';
  return 'ok ' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI');
end $$;
grant execute on function public.manter_ativo(text) to anon, authenticated;

-- ---------- Dados iniciais dos cadastros ----------
insert into public.filiais (codigo) values ('IMB'),('TAM'),('GUS'),('CAU'),('PAL'),('BAR'),('JPA'),('PNG'),('REC')
  on conflict do nothing;

insert into public.listas (tipo, valor, ordem) values
  ('orgao','Procon',1),('orgao','Inmetro / IPEM',2),('orgao','Vigilância Sanitária',3),('orgao','Corpo de Bombeiros',4),
  ('orgao','Ministério do Trabalho',5),('orgao','Ministério Público',6),('orgao','Órgão de tributação',7),
  ('orgao','Órgão ambiental',8),('orgao','Crea / CAU',9),('orgao','Prefeitura',10),
  ('motivo','Licença',1),('motivo','Denúncia',2),('motivo','Iniciativa do órgão',3),('motivo','Retorno ou reinspeção',4),
  ('motivo','Requisição de outra autoridade',5),('motivo','Apuração de acidente ou incidente',6),
  ('nc','Preço ou etiqueta divergente',1),('nc','Produto sem selo / certificação',2),('nc','Licença ou alvará',3),
  ('nc','Prevenção de incêndio (AVCB)',4),('nc','Condições sanitárias',5),('nc','Documentação trabalhista',6),
  ('nc','Atendimento ou troca ao consumidor',7),('nc','Questão ambiental',8)
  on conflict do nothing;

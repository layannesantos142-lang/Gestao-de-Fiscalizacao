-- =====================================================================
-- Fiscalização + — Auditoria completa, comentários, datas de cada etapa e histórico anual
-- (rodar depois do 07_compliance_corporativo.sql)
-- Regra: nada do que é preenchido pode ser perdido.
-- =====================================================================

-- ---------- 1) Datas-chave do chamado (para medir tempos e prazos) ----------
alter table public.chamados add column if not exists inicio_analise_em   timestamptz;
alter table public.chamados add column if not exists respondido_orgao_em timestamptz;
alter table public.chamados add column if not exists encerrado_em        timestamptz;

create or replace function public.chamado_datas() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.status is distinct from old.status then
    if old.status = 'aberto' and new.inicio_analise_em is null then new.inicio_analise_em := now(); end if;
    if new.status = 'respondido' and new.respondido_orgao_em is null then new.respondido_orgao_em := now(); end if;
    if new.status = 'encerrado' then new.encerrado_em := now(); end if;
    if old.status = 'encerrado' and new.status <> 'encerrado' then new.encerrado_em := null; end if;  -- reaberto
  end if;
  return new;
end $$;
drop trigger if exists chamados_datas on public.chamados;
create trigger chamados_datas before update on public.chamados for each row execute function public.chamado_datas();

-- preenche as datas dos chamados que já existem, a partir do histórico
update public.chamados c set inicio_analise_em = e.q from (
  select chamado_id, min(criado_em) q from public.eventos where texto like 'An_lise iniciada%' group by chamado_id) e
  where e.chamado_id = c.id and c.inicio_analise_em is null;
update public.chamados c set respondido_orgao_em = e.q from (
  select chamado_id, min(criado_em) q from public.eventos where texto like 'Resposta protocolada%' group by chamado_id) e
  where e.chamado_id = c.id and c.respondido_orgao_em is null;
update public.chamados c set encerrado_em = e.q from (
  select chamado_id, max(criado_em) q from public.eventos where texto like 'Desfecho:%' group by chamado_id) e
  where e.chamado_id = c.id and c.status = 'encerrado' and c.encerrado_em is null;

-- ---------- 2) Comentários (separados do histórico) ----------
create table if not exists public.comentarios (
  id               bigint generated always as identity primary key,
  chamado_id       text not null references public.chamados(id),
  papel            text not null check (papel in ('filial','juridico','compliance')),
  autor            text not null,
  texto            text not null,
  criado_por       uuid references auth.users(id) default auth.uid(),
  criado_em        timestamptz not null default now(),
  lido_juridico_em timestamptz,
  lido_filial_em   timestamptz
);
create index if not exists comentarios_chamado_idx on public.comentarios (chamado_id);
alter table public.comentarios enable row level security;
drop policy if exists comentarios_ler on public.comentarios;
create policy comentarios_ler on public.comentarios for select to authenticated using (public.pode_ver(chamado_id));
drop policy if exists comentarios_criar on public.comentarios;
create policy comentarios_criar on public.comentarios for insert to authenticated with check (public.pode_ver(chamado_id));
-- sem update/delete: comentário não é alterado nem apagado; a leitura é marcada pela função abaixo

create or replace function public.marcar_comentarios_lidos(cid text) returns void
language plpgsql security definer set search_path = public as $$
declare p text := public.meu_papel();
begin
  if not public.pode_ver(cid) then return; end if;
  if p in ('juridico','compliance') then
    update public.comentarios set lido_juridico_em = now() where chamado_id = cid and papel = 'filial' and lido_juridico_em is null;
  elsif p = 'filial' then
    update public.comentarios set lido_filial_em = now() where chamado_id = cid and papel <> 'filial' and lido_filial_em is null;
  end if;
end $$;
revoke execute on function public.marcar_comentarios_lidos(text) from public, anon;
grant execute on function public.marcar_comentarios_lidos(text) to authenticated;

do $$ begin alter publication supabase_realtime add table public.comentarios; exception when duplicate_object then null; end $$;

-- ---------- 3) Auditoria: quem entrou, viu, mudou (antes/depois) e saiu ----------
create table if not exists public.auditoria (
  id          bigint generated always as identity primary key,
  quando      timestamptz not null default now(),
  usuario     uuid,
  nome        text,
  email       text,
  papel       text,
  acao        text not null,          -- entrou | saiu | visualizou | criou | alterou | exportou | ...
  tabela      text,
  chamado_id  text,
  filial      text,
  protocolo   text,
  detalhes    jsonb
);
create index if not exists auditoria_quando_idx  on public.auditoria (quando desc);
create index if not exists auditoria_chamado_idx on public.auditoria (chamado_id);
create index if not exists auditoria_filial_idx  on public.auditoria (filial);
alter table public.auditoria enable row level security;
drop policy if exists auditoria_ler on public.auditoria;
create policy auditoria_ler on public.auditoria for select to authenticated using (public.meu_papel() = 'compliance');
-- ninguém grava, altera ou apaga direto: só as funções abaixo escrevem

-- grava uma alteração de tabela (antes/depois só dos campos que mudaram)
create or replace function public.auditar() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  n jsonb := case when tg_op = 'DELETE' then null else to_jsonb(new) end;
  o jsonb := case when tg_op = 'INSERT' then null else to_jsonb(old) end;
  r jsonb := coalesce(n, o);
  det jsonb; k text; cid text; fil text; prot text;
  q_nome text; q_email text; q_papel text;
begin
  if tg_op = 'UPDATE' then
    det := '{}'::jsonb;
    for k in select jsonb_object_keys(n) loop
      if k not in ('atualizado_em') and (n -> k) is distinct from (o -> k) then
        det := det || jsonb_build_object(k, jsonb_build_object('antes', o -> k, 'depois', n -> k));
      end if;
    end loop;
    if det = '{}'::jsonb then return null; end if;
  else
    det := r;
  end if;

  if tg_table_name = 'chamados' then cid := r ->> 'id';
  elsif r ? 'chamado_id' then cid := r ->> 'chamado_id'; end if;
  if cid is not null then select filial, protocolo into fil, prot from public.chamados where id = cid; end if;
  if tg_table_name = 'perfis' then fil := r ->> 'filial'; end if;

  select p.nome, p.email, p.papel into q_nome, q_email, q_papel from public.perfis p where p.id = auth.uid();
  insert into public.auditoria (usuario, nome, email, papel, acao, tabela, chamado_id, filial, protocolo, detalhes)
  values (auth.uid(), q_nome, q_email, coalesce(q_papel, case when auth.uid() is null then 'sistema' end),
          case tg_op when 'INSERT' then 'criou' when 'UPDATE' then 'alterou' else 'apagou' end,
          tg_table_name, cid, fil, prot, det);
  return null;
end $$;

do $$ declare t text; begin
  foreach t in array array['chamados','eventos','retornos','liberacoes','multas_lojista','anexos','comentarios','perfis','filiais','listas'] loop
    execute format('drop trigger if exists auditar_%s on public.%I', t, t);
    execute format('create trigger auditar_%s after insert or update or delete on public.%I for each row execute function public.auditar()', t, t);
  end loop;
end $$;

-- acessos registrados pelo app (entrou, saiu, visualizou, exportou...)
create or replace function public.registrar_acesso(p_acao text, p_chamado text default null, p_detalhes jsonb default null) returns void
language plpgsql security definer set search_path = public as $$
declare q_nome text; q_email text; q_papel text; q_filial text; fil text; prot text;
begin
  if auth.uid() is null then return; end if;
  select p.nome, p.email, p.papel, p.filial into q_nome, q_email, q_papel, q_filial from public.perfis p where p.id = auth.uid();
  if p_chamado is not null then select filial, protocolo into fil, prot from public.chamados where id = p_chamado; end if;
  insert into public.auditoria (usuario, nome, email, papel, acao, tabela, chamado_id, filial, protocolo, detalhes)
  values (auth.uid(), q_nome, q_email, q_papel, left(p_acao, 40), null, p_chamado, coalesce(fil, q_filial), prot, p_detalhes);
end $$;
revoke execute on function public.registrar_acesso(text, text, jsonb) from public, anon;
grant execute on function public.registrar_acesso(text, text, jsonb) to authenticated;

-- ---------- 4) Backup: histórico anual completo ----------
-- todas as cópias diárias dos últimos 12 meses + a primeira cópia de cada mês para sempre
create or replace function backup.fazer_copia() returns int
language plpgsql security definer set search_path = public as $$
declare t text; n int; v jsonb; v_lote timestamptz := now(); total int := 0;
begin
  for t in select tablename from pg_tables where schemaname = 'public'
           and tablename not in ('sinais_atividade', 'auditoria') order by tablename loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb), count(*) from %I x', t) into v, n;
    insert into backup.copias (lote, tabela, linhas, dados) values (v_lote, t, n, v);
    total := total + 1;
  end loop;
  delete from backup.copias c
  where c.lote < now() - interval '366 days'
    and c.lote <> (select min(c2.lote) from backup.copias c2
                   where date_trunc('month', c2.lote) = date_trunc('month', c.lote));
  return total;
end $$;
revoke execute on function backup.fazer_copia() from public, anon, authenticated;

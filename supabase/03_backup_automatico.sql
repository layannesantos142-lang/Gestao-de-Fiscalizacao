-- =====================================================================
--  Fiscalização + — Backup automático diário (dentro do próprio Supabase, sem depender de ninguém)
--  - Todo dia às 03h (Brasília) copia todas as tabelas do sistema para backup.copias
--  - Guarda 30 dias de cópias diárias + 1 cópia por mês durante 12 meses
--  - O esquema "backup" não é exposto pela API: só a administração do banco acessa
--  - O Compliance vê o status (último backup e último sinal do "manter ativo") e baixa um backup completo em Excel
-- =====================================================================
create extension if not exists pg_cron;

create schema if not exists backup;
revoke all on schema backup from public, anon, authenticated;

create table if not exists backup.copias (
  id        bigserial primary key,
  lote      timestamptz not null,          -- todas as tabelas de uma mesma cópia têm o mesmo lote
  tabela    text not null,
  linhas    int  not null,
  dados     jsonb not null
);
create index if not exists copias_lote_idx on backup.copias (lote desc, tabela);
alter table backup.copias enable row level security;  -- ninguém lê direto; só pelas funções abaixo

create or replace function backup.fazer_copia() returns int
language plpgsql security definer set search_path = public as $$
declare t text; n int; v jsonb; v_lote timestamptz := now(); total int := 0;
begin
  for t in select tablename from pg_tables where schemaname = 'public'
           and tablename not in ('sinais_atividade') order by tablename loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb), count(*) from %I x', t) into v, n;
    insert into backup.copias (lote, tabela, linhas, dados) values (v_lote, t, n, v);
    total := total + 1;
  end loop;
  -- retenção: últimos 30 dias inteiros + o primeiro lote de cada mês por 12 meses
  delete from backup.copias c
  where c.lote < now() - interval '30 days'
    and (c.lote < now() - interval '12 months'
         or c.lote <> (select min(c2.lote) from backup.copias c2
                       where date_trunc('month', c2.lote) = date_trunc('month', c.lote)));
  return total;
end $$;
revoke execute on function backup.fazer_copia() from public, anon, authenticated;

-- restauração de UMA tabela a partir de um lote (uso pela administração do banco, sob pedido)
create or replace function backup.restaurar_tabela(p_tabela text, p_lote timestamptz) returns int
language plpgsql security definer set search_path = public as $$
declare v jsonb; n int;
begin
  select dados into v from backup.copias where tabela = p_tabela and lote = p_lote;
  if v is null then raise exception 'Cópia de % em % não encontrada.', p_tabela, p_lote; end if;
  execute format('delete from %I', p_tabela);
  execute format('insert into %I select * from jsonb_populate_recordset(null::%I, $1)', p_tabela, p_tabela) using v;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function backup.restaurar_tabela(text, timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Para a tela do Compliance
-- ---------------------------------------------------------------------
create or replace function public.status_sistema() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if public.meu_papel() <> 'compliance' then raise exception 'Apenas o Compliance.'; end if;
  return json_build_object(
    'backups', (select coalesce(json_agg(x order by x.lote desc), '[]'::json) from (
                  select lote, count(*) tabelas, sum(linhas) linhas from backup.copias group by lote) x),
    'ultimo_sinal', (select max(criado_em) from public.sinais_atividade),
    'sinais_7d', (select count(*) from public.sinais_atividade where criado_em > now() - interval '7 days')
  );
end $$;
revoke execute on function public.status_sistema() from public, anon;
grant execute on function public.status_sistema() to authenticated;

-- backup completo dos dados atuais (todas as tabelas) para download em Excel
create or replace function public.exportar_backup() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t text; v jsonb; r jsonb := '{}'::jsonb;
begin
  if public.meu_papel() <> 'compliance' then raise exception 'Apenas o Compliance.'; end if;
  for t in select tablename from pg_tables where schemaname = 'public' order by tablename loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from %I x', t) into v;
    r := r || jsonb_build_object(t, v);
  end loop;
  return r;
end $$;
revoke execute on function public.exportar_backup() from public, anon;
grant execute on function public.exportar_backup() to authenticated;

-- agenda diária: 06h UTC = 03h Brasília
select cron.unschedule(jobid) from cron.job where jobname = 'backup-diario';
select cron.schedule('backup-diario', '0 6 * * *', 'select backup.fazer_copia()');

-- primeira cópia agora
select backup.fazer_copia() as tabelas_copiadas;

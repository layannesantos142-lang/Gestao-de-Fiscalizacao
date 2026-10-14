-- =====================================================================
-- Fiscalização + — Backup sem lotar o banco + medidor de espaço
-- (rodar depois do 08_auditoria_comentarios_tempos.sql)
--  - Cópias diárias: últimos 30 dias (sem a auditoria, que já guarda todas as mudanças de todos os dias)
--  - Cópia mensal (1ª cópia de cada mês): guardada PARA SEMPRE e inclui também a auditoria
--  - A auditoria em si nunca é apagada
-- =====================================================================
create or replace function backup.fazer_copia() returns int
language plpgsql security definer set search_path = public as $$
declare t text; n int; v jsonb; v_lote timestamptz := now(); total int := 0;
  mensal boolean := not exists (select 1 from backup.copias where date_trunc('month', lote) = date_trunc('month', now()));
begin
  for t in select tablename from pg_tables where schemaname = 'public'
           and tablename <> 'sinais_atividade'
           and (mensal or tablename <> 'auditoria') order by tablename loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb), count(*) from %I x', t) into v, n;
    insert into backup.copias (lote, tabela, linhas, dados) values (v_lote, t, n, v);
    total := total + 1;
  end loop;
  -- mantém: tudo dos últimos 30 dias + a primeira cópia de cada mês (para sempre)
  delete from backup.copias c
  where c.lote < now() - interval '30 days'
    and c.lote <> (select min(c2.lote) from backup.copias c2
                   where date_trunc('month', c2.lote) = date_trunc('month', c.lote));
  return total;
end $$;
revoke execute on function backup.fazer_copia() from public, anon, authenticated;

-- situação do sistema para a tela do Compliance, agora com o uso de espaço
create or replace function public.status_sistema() returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if public.meu_papel() <> 'compliance' then raise exception 'Apenas o Compliance.'; end if;
  return json_build_object(
    'backups', (select coalesce(json_agg(x order by x.lote desc), '[]'::json) from (
                  select lote, count(*) tabelas, sum(linhas) linhas from backup.copias group by lote) x),
    'ultimo_sinal', (select max(criado_em) from public.sinais_atividade),
    'sinais_7d', (select count(*) from public.sinais_atividade where criado_em > now() - interval '7 days'),
    'banco_bytes', pg_database_size(current_database()),
    'backup_bytes', pg_total_relation_size('backup.copias'),
    'auditoria_bytes', pg_total_relation_size('public.auditoria'),
    'anexos_bytes', (select coalesce(sum((metadata->>'size')::bigint), 0) from storage.objects where bucket_id = 'anexos'),
    'anexos_qtd', (select count(*) from storage.objects where bucket_id = 'anexos'),
    'ultimo_download', (select max(quando) from public.auditoria where acao = 'exportou' and detalhes->>'tipo' = 'backup completo')
  );
end $$;
revoke execute on function public.status_sistema() from public, anon;
grant execute on function public.status_sistema() to authenticated;

-- limpa já as cópias diárias antigas que não são a cópia do mês
delete from backup.copias c
where c.lote < now() - interval '30 days'
  and c.lote <> (select min(c2.lote) from backup.copias c2
                 where date_trunc('month', c2.lote) = date_trunc('month', c.lote));

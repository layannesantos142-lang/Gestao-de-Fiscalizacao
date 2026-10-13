-- =====================================================================
-- Fiscalização + — Protocolo do órgão e ID sequencial do chamado
-- (rodar depois do 03_backup_automatico.sql)
-- =====================================================================

-- Número de protocolo / processo informado pelo órgão (preenchido pela filial ao abrir ou depois pelo Jurídico/Compliance)
alter table public.chamados add column if not exists protocolo text;
create index if not exists chamados_protocolo_idx on public.chamados (protocolo);

-- ID do chamado: gerado pelo sistema, sequencial e único (FIS-0001, FIS-0002, ...).
-- Ajusta a sequência para continuar a partir do maior número já usado (ou começar em FIS-0001 se não houver chamados).
select setval('public.chamado_seq',
  coalesce((select max(nullif(regexp_replace(id, '\D', '', 'g'), '')::int) from public.chamados), 0) + 1,
  false);
